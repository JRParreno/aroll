"""Server-side head-turn liveness challenge validation."""

from __future__ import annotations

import random
import uuid
from dataclasses import dataclass
from datetime import datetime, timedelta, timezone

from fastapi import HTTPException
from sqlalchemy.orm import Session

from app.core.config import settings
from app.models.employee import Employee
from app.models.face_embedding import EmployeeFaceEmbedding
from app.models.face_liveness import FaceLivenessChallenge
from app.services.face_embedding import (
    FaceObservation,
    best_match_score,
    cosine_similarity,
    detect_and_observe,
    match_passed,
    mean_match_score,
)

DIRECTIONS = ("turn_left", "turn_right")

INSTRUCTION_TEXT = {
    "turn_left": "Look straight, then turn your head LEFT, then look straight again.",
    "turn_right": "Look straight, then turn your head RIGHT, then look straight again.",
}


class LivenessError(HTTPException):
    def __init__(self, code: str, message: str, status_code: int = 400, **extra) -> None:
        detail: dict = {"code": code, "message": message}
        detail.update(extra)
        super().__init__(status_code=status_code, detail=detail)


@dataclass(frozen=True)
class LivenessResult:
    match_score: float
    threshold: float
    direction: str
    liveness_passed: bool
    center_yaw: float
    turn_yaw: float
    return_yaw: float
    continuity_scores: tuple[float, float]
    message: str


@dataclass(frozen=True)
class PoseObserveResult:
    """Soft pose guidance for auto-capture. Does not consume the challenge."""

    ready: bool
    step: str
    direction: str
    face_detected: bool
    face_count: int
    yaw: float | None
    detection_score: float | None
    guidance: str
    reason_code: str | None = None


def create_challenge(
    db: Session,
    *,
    employee: Employee,
    requested_by: uuid.UUID,
) -> FaceLivenessChallenge:
    now = datetime.now(timezone.utc)
    challenge = FaceLivenessChallenge(
        employee_id=employee.id,
        requested_by=requested_by,
        direction=random.choice(DIRECTIONS),
        expires_at=now
        + timedelta(seconds=settings.face_liveness_challenge_ttl_seconds),
    )
    db.add(challenge)
    db.commit()
    db.refresh(challenge)
    return challenge


def _load_challenge(
    db: Session,
    challenge_id: uuid.UUID,
    *,
    employee_id: uuid.UUID | None = None,
) -> FaceLivenessChallenge:
    challenge = db.get(FaceLivenessChallenge, challenge_id)
    if challenge is None:
        raise LivenessError(
            "challenge_not_found",
            "Liveness challenge was not found. Start a new challenge.",
            status_code=404,
        )
    if employee_id is not None and challenge.employee_id != employee_id:
        raise LivenessError(
            "challenge_mismatch",
            "This challenge belongs to a different employee.",
            status_code=403,
        )
    now = datetime.now(timezone.utc)
    expires = challenge.expires_at
    if expires.tzinfo is None:
        expires = expires.replace(tzinfo=timezone.utc)
    if challenge.consumed_at is not None:
        raise LivenessError(
            "challenge_used",
            "This liveness challenge was already used. Start a new one.",
            status_code=409,
        )
    if now > expires:
        raise LivenessError(
            "challenge_expired",
            "This liveness challenge expired. Start a new one.",
            status_code=410,
        )
    return challenge


def _require_centered(obs: FaceObservation, *, label: str) -> None:
    if abs(obs.yaw) > settings.face_liveness_center_yaw_max:
        raise LivenessError(
            "pose_not_centered",
            f"{label} frame is not looking straight at the camera. "
            "Look forward and try again.",
            yaw=round(obs.yaw, 4),
            limit=settings.face_liveness_center_yaw_max,
        )


def _require_turn(obs: FaceObservation, direction: str, center_yaw: float) -> None:
    if direction == "turn_left":
        # Subject turns left → nose moves toward image-right in typical frontal
        # landmark space for YuNet (left_eye is on image-left from viewer).
        # Empirically nose_x - eye_mid becomes more negative when subject turns left
        # (exposing left cheek toward camera). Accept either sign convention by
        # requiring the instructed magnitude and matching the expected sign.
        expected_sign = -1.0
        label = "LEFT"
    else:
        expected_sign = 1.0
        label = "RIGHT"

    if abs(obs.yaw) < settings.face_liveness_turn_yaw_min:
        raise LivenessError(
            "turn_not_detected",
            f"Turn frame did not show a clear {label} head turn. "
            f"Turn your head farther {label.lower()} and try again.",
            yaw=round(obs.yaw, 4),
            required_min=settings.face_liveness_turn_yaw_min,
        )

    if obs.yaw * expected_sign < 0:
        # Wrong direction relative to expected sign.
        raise LivenessError(
            "turn_wrong_direction",
            f"Turn frame turned the wrong way. Please turn your head {label}.",
            yaw=round(obs.yaw, 4),
            expected_direction=direction,
        )

    if abs(obs.yaw - center_yaw) < settings.face_liveness_turn_delta_min:
        raise LivenessError(
            "turn_not_detected",
            f"Turn frame is too similar to the center pose. "
            f"Turn your head farther {label.lower()}.",
            yaw=round(obs.yaw, 4),
            center_yaw=round(center_yaw, 4),
            delta=round(abs(obs.yaw - center_yaw), 4),
        )


def _require_continuity(a: FaceObservation, b: FaceObservation, *, pair: str) -> float:
    score = cosine_similarity(a.embedding, b.embedding)
    if score < settings.face_liveness_continuity_threshold:
        raise LivenessError(
            "identity_changed",
            f"Face identity changed between {pair} frames. "
            "Keep the same person in frame for the whole challenge.",
            continuity_score=round(score, 4),
            threshold=settings.face_liveness_continuity_threshold,
        )
    return score


def validate_liveness_sequence(
    db: Session,
    *,
    challenge_id: uuid.UUID,
    employee: Employee,
    center_bytes: bytes,
    turn_bytes: bytes,
    return_bytes: bytes,
    consume: bool = True,
) -> LivenessResult:
    """Validate a center → turn → center sequence against a one-time challenge."""
    challenge = _load_challenge(db, challenge_id, employee_id=employee.id)

    samples = (
        db.query(EmployeeFaceEmbedding)
        .filter(EmployeeFaceEmbedding.employee_id == employee.id)
        .all()
    )
    if not samples:
        raise LivenessError(
            "not_enrolled",
            "Face is not enrolled. Complete face registration first.",
        )

    center = detect_and_observe(center_bytes)
    turn = detect_and_observe(turn_bytes)
    ret = detect_and_observe(return_bytes)

    _require_centered(center, label="Center")
    _require_turn(turn, challenge.direction, center.yaw)
    _require_centered(ret, label="Return")

    cont_ct = _require_continuity(center, turn, pair="center/turn")
    cont_tr = _require_continuity(turn, ret, pair="turn/return")

    gallery = [list(row.embedding) for row in samples]
    # Use the return-to-center frame as the identity probe for enrollment match.
    # Mean across enrolled samples is stricter against lookalike/sibling luck.
    match_score = mean_match_score(ret.embedding, gallery)
    threshold = settings.face_match_threshold
    if not match_passed(match_score, threshold):
        raise LivenessError(
            "face_mismatch",
            (
                f"Face did not match enrolled samples "
                f"(mean score {match_score:.3f} < {threshold:.3f}; "
                f"best {best_match_score(ret.embedding, gallery):.3f})."
            ),
            status_code=403,
            match_score=round(match_score, 4),
            threshold=threshold,
        )

    if consume:
        challenge.consumed_at = datetime.now(timezone.utc)
        db.commit()

    return LivenessResult(
        match_score=round(match_score, 4),
        threshold=threshold,
        direction=challenge.direction,
        liveness_passed=True,
        center_yaw=round(center.yaw, 4),
        turn_yaw=round(turn.yaw, 4),
        return_yaw=round(ret.yaw, 4),
        continuity_scores=(round(cont_ct, 4), round(cont_tr, 4)),
        message=(
            f"Liveness passed ({challenge.direction.replace('_', ' ')}). "
            f"Face match score: {match_score:.3f}."
        ),
    )


def challenge_instruction(direction: str) -> str:
    return INSTRUCTION_TEXT.get(
        direction,
        "Look straight, turn your head as instructed, then look straight again.",
    )


def _step_guidance(step: str, direction: str) -> str:
    if step in ("center", "return"):
        return "Look straight at the camera."
    label = "LEFT" if direction == "turn_left" else "RIGHT"
    return f"Turn your head {label}."


def _evaluate_step_ready(
    obs: FaceObservation,
    *,
    step: str,
    direction: str,
) -> tuple[bool, str | None, str]:
    """Return (ready, reason_code, guidance) without raising for soft pose misses."""
    if step in ("center", "return"):
        if abs(obs.yaw) > settings.face_liveness_center_yaw_max:
            return (
                False,
                "pose_not_centered",
                "Look straight at the camera.",
            )
        return True, None, "Hold still — capturing…"

    # turn step — absolute yaw only (final verify still checks delta vs center)
    expected_sign = -1.0 if direction == "turn_left" else 1.0
    label = "LEFT" if direction == "turn_left" else "RIGHT"
    if abs(obs.yaw) < settings.face_liveness_turn_yaw_min:
        return (
            False,
            "turn_not_detected",
            f"Turn your head farther {label}.",
        )
    if obs.yaw * expected_sign < 0:
        return (
            False,
            "turn_wrong_direction",
            f"Turn the other way — look {label}.",
        )
    return True, None, "Hold the turn — capturing…"


def observe_pose(
    db: Session,
    *,
    challenge_id: uuid.UUID,
    employee: Employee,
    step: str,
    frame_bytes: bytes,
) -> PoseObserveResult:
    """Non-consuming pose check for auto-capture UI guidance.

    Hard failures (expired challenge, no face) raise LivenessError / FacePipelineError.
    Soft pose mismatches return ready=False with guidance text.
    """
    if step not in ("center", "turn", "return"):
        raise LivenessError(
            "invalid_step",
            "step must be one of: center, turn, return.",
        )

    challenge = _load_challenge(db, challenge_id, employee_id=employee.id)

    enrolled = (
        db.query(EmployeeFaceEmbedding.id)
        .filter(EmployeeFaceEmbedding.employee_id == employee.id)
        .first()
    )
    if enrolled is None:
        raise LivenessError(
            "not_enrolled",
            "Face is not enrolled. Complete face registration first.",
        )

    obs = detect_and_observe(frame_bytes)
    if obs.face_count > 1:
        return PoseObserveResult(
            ready=False,
            step=step,
            direction=challenge.direction,
            face_detected=True,
            face_count=obs.face_count,
            yaw=round(obs.yaw, 4),
            detection_score=round(obs.score, 4),
            guidance="Only one face should be in frame.",
            reason_code="multiple_faces",
        )

    ready, reason, guidance = _evaluate_step_ready(
        obs, step=step, direction=challenge.direction
    )
    return PoseObserveResult(
        ready=ready,
        step=step,
        direction=challenge.direction,
        face_detected=True,
        face_count=obs.face_count,
        yaw=round(obs.yaw, 4),
        detection_score=round(obs.score, 4),
        guidance=guidance if ready else guidance or _step_guidance(step, challenge.direction),
        reason_code=reason,
    )
