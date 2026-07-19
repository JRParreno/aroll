"""Owner face enrollment, identity verify, and liveness challenge endpoints."""

from __future__ import annotations

import uuid
from datetime import datetime, timezone
from typing import Annotated

from fastapi import APIRouter, Depends, File, Form, HTTPException, UploadFile
from sqlalchemy.orm import Session

from app.core.config import settings
from app.core.deps import get_current_user, require_roles
from app.db.session import get_db
from app.models.employee import Employee
from app.models.enums import UserRole
from app.models.face_embedding import EmployeeFaceEmbedding
from app.models.user import User
from app.schemas.face import (
    FaceEnrollResponse,
    FaceLivenessVerifyResponse,
    FaceStatusResponse,
    FaceVerifyResponse,
    LivenessChallengeCreateRequest,
    LivenessChallengeResponse,
    LivenessPoseMetrics,
    LivenessPoseObserveResponse,
)
from app.services.face_embedding import (
    MODEL_VERSION,
    best_match_score,
    detect_and_embed,
    match_passed,
    mean_match_score,
)
from app.services.face_liveness import (
    challenge_instruction,
    create_challenge,
    observe_pose,
    validate_liveness_sequence,
)

router = APIRouter(tags=["face"])


def _get_business_employee(
    db: Session, employee_id: uuid.UUID, business_id: uuid.UUID
) -> Employee:
    emp = (
        db.query(Employee)
        .filter(Employee.id == employee_id, Employee.business_id == business_id)
        .first()
    )
    if emp is None:
        raise HTTPException(404, "Employee not found")
    return emp


def _employee_for_user(db: Session, user: User) -> Employee:
    emp = db.query(Employee).filter(Employee.user_id == user.id).first()
    if emp is None:
        raise HTTPException(400, "No employee profile for this account")
    return emp


async def _read_uploads(files: list[UploadFile]) -> list[bytes]:
    payloads: list[bytes] = []
    for upload in files:
        data = await upload.read()
        if not data:
            raise HTTPException(400, f"Empty file: {upload.filename or 'upload'}")
        payloads.append(data)
    return payloads


@router.get(
    "/employees/{employee_id}/face-status",
    response_model=FaceStatusResponse,
)
def get_face_status(
    employee_id: uuid.UUID,
    db: Annotated[Session, Depends(get_db)],
    user: Annotated[User, Depends(require_roles(UserRole.owner, UserRole.manager))],
):
    if user.business_id is None:
        raise HTTPException(400, "No business context")
    emp = _get_business_employee(db, employee_id, user.business_id)
    samples = (
        db.query(EmployeeFaceEmbedding)
        .filter(EmployeeFaceEmbedding.employee_id == emp.id)
        .order_by(EmployeeFaceEmbedding.sample_index.asc())
        .all()
    )
    model_version = samples[0].model_version if samples else None
    return FaceStatusResponse(
        employee_id=str(emp.id),
        face_registration_status=emp.face_registration_status,
        sample_count=len(samples),
        model_version=model_version,
        face_registered_at=(
            emp.face_registered_at.isoformat() if emp.face_registered_at else None
        ),
        threshold=settings.face_match_threshold,
    )


@router.post(
    "/employees/{employee_id}/face-samples",
    response_model=FaceEnrollResponse,
    status_code=201,
)
async def enroll_face_samples(
    employee_id: uuid.UUID,
    db: Annotated[Session, Depends(get_db)],
    user: Annotated[User, Depends(require_roles(UserRole.owner, UserRole.manager))],
    files: Annotated[list[UploadFile], File(..., description="3–5 face images")],
):
    if user.business_id is None:
        raise HTTPException(400, "No business context")
    emp = _get_business_employee(db, employee_id, user.business_id)

    payloads = await _read_uploads(files)
    min_n = settings.face_min_enrollment_samples
    max_n = settings.face_max_enrollment_samples
    if len(payloads) < min_n or len(payloads) > max_n:
        raise HTTPException(
            400,
            f"Upload between {min_n} and {max_n} face images (got {len(payloads)}).",
        )

    embeddings: list[list[float]] = []
    for data in payloads:
        embeddings.append(detect_and_embed(data))

    db.query(EmployeeFaceEmbedding).filter(
        EmployeeFaceEmbedding.employee_id == emp.id
    ).delete(synchronize_session=False)

    now = datetime.now(timezone.utc)
    for index, vector in enumerate(embeddings, start=1):
        db.add(
            EmployeeFaceEmbedding(
                employee_id=emp.id,
                embedding=vector,
                model_version=MODEL_VERSION,
                sample_index=index,
                enrolled_by=user.id,
                enrolled_at=now,
            )
        )

    emp.face_registration_status = "completed"
    emp.face_registered_at = now
    emp.face_registration_skipped_at = None
    db.commit()

    return FaceEnrollResponse(
        employee_id=str(emp.id),
        face_registration_status=emp.face_registration_status,
        sample_count=len(embeddings),
        model_version=MODEL_VERSION,
        message=f"Enrolled {len(embeddings)} face sample(s).",
    )


@router.delete("/employees/{employee_id}/face-samples")
def delete_face_samples(
    employee_id: uuid.UUID,
    db: Annotated[Session, Depends(get_db)],
    user: Annotated[User, Depends(require_roles(UserRole.owner, UserRole.manager))],
):
    if user.business_id is None:
        raise HTTPException(400, "No business context")
    emp = _get_business_employee(db, employee_id, user.business_id)

    deleted = (
        db.query(EmployeeFaceEmbedding)
        .filter(EmployeeFaceEmbedding.employee_id == emp.id)
        .delete(synchronize_session=False)
    )
    emp.face_registration_status = "not_registered"
    emp.face_registered_at = None
    db.commit()
    return {
        "status": "ok",
        "deleted_count": deleted,
        "face_registration_status": emp.face_registration_status,
    }


@router.post("/face/verify", response_model=FaceVerifyResponse)
async def verify_face(
    db: Annotated[Session, Depends(get_db)],
    user: Annotated[User, Depends(require_roles(UserRole.owner, UserRole.manager))],
    employee_id: Annotated[uuid.UUID, Form(...)],
    file: Annotated[UploadFile, File(...)],
):
    """Identity-only diagnostic compare. Does NOT prove liveness — use verify-liveness."""
    if user.business_id is None:
        raise HTTPException(400, "No business context")
    emp = _get_business_employee(db, employee_id, user.business_id)

    samples = (
        db.query(EmployeeFaceEmbedding)
        .filter(EmployeeFaceEmbedding.employee_id == emp.id)
        .all()
    )
    if not samples:
        raise HTTPException(
            400,
            detail={
                "code": "not_enrolled",
                "message": "Employee has no face samples. Enroll first.",
            },
        )

    probe = detect_and_embed(await file.read())
    gallery = [list(row.embedding) for row in samples]
    score = mean_match_score(probe, gallery)
    passed = match_passed(score)
    threshold = settings.face_match_threshold
    best = best_match_score(probe, gallery)

    return FaceVerifyResponse(
        employee_id=str(emp.id),
        match_score=round(score, 4),
        passed=passed,
        threshold=threshold,
        model_version=MODEL_VERSION,
        liveness_checked=False,
        message=(
            (
                f"Identity match passed (mean {score:.3f}, best {best:.3f}). "
                "Blink/smile is client-side only — use Strong head-turn for "
                "server-verified liveness."
            )
            if passed
            else (
                f"Face match failed (mean {score:.3f} < {threshold:.3f}; "
                f"best {best:.3f})."
            )
        ),
    )


@router.post("/face/liveness/challenges", response_model=LivenessChallengeResponse)
def create_liveness_challenge(
    body: LivenessChallengeCreateRequest,
    db: Annotated[Session, Depends(get_db)],
    user: Annotated[User, Depends(get_current_user)],
):
    """Issue a one-time random head-turn challenge for an employee."""
    if user.role in (UserRole.owner, UserRole.manager):
        if not body.employee_id:
            raise HTTPException(400, "employee_id is required for owner/manager")
        if user.business_id is None:
            raise HTTPException(400, "No business context")
        emp = _get_business_employee(
            db, uuid.UUID(body.employee_id), user.business_id
        )
    elif user.role == UserRole.employee:
        emp = _employee_for_user(db, user)
        if body.employee_id and str(emp.id) != body.employee_id:
            raise HTTPException(403, "Employees can only create challenges for themselves")
    else:
        raise HTTPException(403, "Insufficient permissions")

    challenge = create_challenge(db, employee=emp, requested_by=user.id)
    return LivenessChallengeResponse(
        challenge_id=str(challenge.id),
        employee_id=str(emp.id),
        direction=challenge.direction,
        instruction=challenge_instruction(challenge.direction),
        expires_at=challenge.expires_at.isoformat(),
        ttl_seconds=settings.face_liveness_challenge_ttl_seconds,
    )


@router.post("/face/liveness/observe", response_model=LivenessPoseObserveResponse)
async def observe_liveness_pose(
    db: Annotated[Session, Depends(get_db)],
    user: Annotated[User, Depends(get_current_user)],
    challenge_id: Annotated[uuid.UUID, Form(...)],
    step: Annotated[str, Form(...)],
    frame: Annotated[UploadFile, File(...)],
    employee_id: Annotated[uuid.UUID | None, Form()] = None,
):
    """Non-consuming pose observation for auto-capture UI guidance.

    Clients may poll this while a challenge is active. Final pass/fail still
    requires POST /face/verify-liveness with all three frames.
    """
    from app.models.face_liveness import FaceLivenessChallenge

    if user.role in (UserRole.owner, UserRole.manager):
        if employee_id is None:
            raise HTTPException(400, "employee_id is required for owner/manager")
        if user.business_id is None:
            raise HTTPException(400, "No business context")
        emp = _get_business_employee(db, employee_id, user.business_id)
    elif user.role == UserRole.employee:
        emp = _employee_for_user(db, user)
    else:
        raise HTTPException(403, "Insufficient permissions")

    result = observe_pose(
        db,
        challenge_id=challenge_id,
        employee=emp,
        step=step.strip().lower(),
        frame_bytes=await frame.read(),
    )
    challenge = db.get(FaceLivenessChallenge, challenge_id)
    expires_at = (
        challenge.expires_at.isoformat()
        if challenge is not None
        else ""
    )
    return LivenessPoseObserveResponse(
        challenge_id=str(challenge_id),
        employee_id=str(emp.id),
        step=result.step,
        direction=result.direction,
        ready=result.ready,
        face_detected=result.face_detected,
        face_count=result.face_count,
        yaw=result.yaw,
        detection_score=result.detection_score,
        guidance=result.guidance,
        reason_code=result.reason_code,
        expires_at=expires_at,
    )


@router.post("/face/verify-liveness", response_model=FaceLivenessVerifyResponse)
async def verify_face_liveness(
    db: Annotated[Session, Depends(get_db)],
    user: Annotated[User, Depends(get_current_user)],
    challenge_id: Annotated[uuid.UUID, Form(...)],
    center_frame: Annotated[UploadFile, File(...)],
    turn_frame: Annotated[UploadFile, File(...)],
    return_frame: Annotated[UploadFile, File(...)],
    employee_id: Annotated[uuid.UUID | None, Form()] = None,
):
    """Validate center → turn → center frames against a one-time challenge."""
    if user.role in (UserRole.owner, UserRole.manager):
        if employee_id is None:
            raise HTTPException(400, "employee_id is required for owner/manager")
        if user.business_id is None:
            raise HTTPException(400, "No business context")
        emp = _get_business_employee(db, employee_id, user.business_id)
    elif user.role == UserRole.employee:
        emp = _employee_for_user(db, user)
    else:
        raise HTTPException(403, "Insufficient permissions")

    result = validate_liveness_sequence(
        db,
        challenge_id=challenge_id,
        employee=emp,
        center_bytes=await center_frame.read(),
        turn_bytes=await turn_frame.read(),
        return_bytes=await return_frame.read(),
        consume=True,
    )

    return FaceLivenessVerifyResponse(
        employee_id=str(emp.id),
        challenge_id=str(challenge_id),
        direction=result.direction,
        match_score=result.match_score,
        passed=True,
        liveness_passed=True,
        threshold=result.threshold,
        model_version=MODEL_VERSION,
        pose=LivenessPoseMetrics(
            center_yaw=result.center_yaw,
            turn_yaw=result.turn_yaw,
            return_yaw=result.return_yaw,
            continuity_center_turn=result.continuity_scores[0],
            continuity_turn_return=result.continuity_scores[1],
        ),
        message=result.message,
    )
