"""Shared face sample enrollment for owner and employee self-enroll."""

from __future__ import annotations

import logging
import uuid
from datetime import datetime, timezone

from fastapi import HTTPException
from sqlalchemy.orm import Session

from app.core.config import settings
from app.models.employee import Employee
from app.models.face_embedding import EmployeeFaceEmbedding
from app.services.face_embedding import (
    MODEL_VERSION,
    gallery_pairwise_consistency,
    mean_match_score,
)
from app.services.demo_tenant import (
    load_business_for_employee,
    raise_if_demo_enrollment_locked,
)

logger = logging.getLogger("aroll.face")


def _prune_weak_enrollment_samples(
    embeddings: list[list[float]],
    *,
    min_n: int,
) -> list[list[float]]:
    """Keep the most mutually consistent samples (drop blink/blur outliers)."""
    kept = list(embeddings)
    # Always drop clear outliers while we have spare samples, not only when
    # overall consistency is below the floor.
    while len(kept) > min_n:
        scores: list[float] = []
        for i, probe in enumerate(kept):
            others = [v for j, v in enumerate(kept) if j != i]
            scores.append(mean_match_score(probe, others) if others else 0.0)
        worst_i = int(min(range(len(scores)), key=lambda i: scores[i]))
        best = max(scores)
        worst = scores[worst_i]
        consistency = gallery_pairwise_consistency(kept)
        # Drop if overall weak, or one sample is far below the strongest.
        if consistency >= settings.face_enrollment_consistency_min and (
            best - worst
        ) < 0.08:
            break
        kept.pop(worst_i)
    return kept


def enroll_face_sample_bytes(
    db: Session,
    employee: Employee,
    payloads: list[bytes],
    *,
    enrolled_by: uuid.UUID | None,
    allow_demo_seed: bool = False,
) -> dict:
    from app.services.face_embedding import detect_and_observe_mirror_aware

    # Seed may attempt the real pipeline once; live DEMO01 enrollment stays locked.
    if not allow_demo_seed:
        raise_if_demo_enrollment_locked(load_business_for_employee(db, employee))

    min_n = settings.face_min_enrollment_samples
    max_n = settings.face_max_enrollment_samples
    if len(payloads) < min_n or len(payloads) > max_n:
        raise HTTPException(
            400,
            f"Upload between {min_n} and {max_n} face images (got {len(payloads)}).",
        )

    embeddings: list[list[float]] = []
    logger.info(
        "FACE_ENROLL employee_id=%s captured_frames=%s accepted_pending=%s "
        "min_n=%s max_n=%s",
        employee.id,
        len(payloads),
        len(payloads),
        min_n,
        max_n,
    )
    for index, data in enumerate(payloads, start=1):
        observation, mirrored = detect_and_observe_mirror_aware(data)
        if observation.face_count != 1:
            raise HTTPException(
                400,
                detail={
                    "code": "multiple_faces",
                    "message": "Only one person should be visible during attendance.",
                },
            )
        # Prefer the orientation that is more consistent with samples already
        # accepted; for the first sample keep the primary (unmirrored) vector.
        chosen = observation.embedding
        if embeddings:
            primary_mean = mean_match_score(observation.embedding, embeddings)
            mirror_mean = mean_match_score(mirrored, embeddings)
            if mirror_mean > primary_mean:
                chosen = mirrored
        embeddings.append(chosen)
        logger.info(
            "FACE_ENROLL employee_id=%s sample=%s/%s face_detected=YES "
            "embedding=YES dim=%s face_quality=%.3f",
            employee.id,
            index,
            len(payloads),
            len(chosen),
            observation.score,
        )

    # Drop the weakest outlier(s) so blink/blur frames don't poison the gallery,
    # while still keeping at least min_n samples.
    embeddings = _prune_weak_enrollment_samples(embeddings, min_n=min_n)

    # Enrollment samples must be the same person (reject mixed identities).
    consistency = gallery_pairwise_consistency(embeddings)
    min_consistency = settings.face_enrollment_consistency_min
    if consistency < min_consistency:
        logger.warning(
            "FACE_ENROLL employee_id=%s result=INCONSISTENT_SAMPLES "
            "consistency=%.4f min=%.4f",
            employee.id,
            consistency,
            min_consistency,
        )
        raise HTTPException(
            400,
            detail={
                "code": "inconsistent_samples",
                "message": (
                    "Enrollment photos do not look like the same person. "
                    "Retake all samples with only the employee facing the camera."
                ),
            },
        )

    db.query(EmployeeFaceEmbedding).filter(
        EmployeeFaceEmbedding.employee_id == employee.id
    ).delete(synchronize_session=False)

    now = datetime.now(timezone.utc)
    for index, vector in enumerate(embeddings, start=1):
        db.add(
            EmployeeFaceEmbedding(
                employee_id=employee.id,
                embedding=vector,
                model_version=MODEL_VERSION,
                sample_index=index,
                enrolled_by=enrolled_by,
                enrolled_at=now,
            )
        )

    employee.face_registration_status = "completed"
    employee.face_registered_at = now
    employee.face_registration_skipped_at = None
    db.commit()
    db.refresh(employee)

    logger.info(
        "FACE_ENROLL employee_id=%s result=STORED samples=%s model=%s "
        "consistency=%.4f embedding_saved=YES associated_account=ok",
        employee.id,
        len(embeddings),
        MODEL_VERSION,
        consistency,
    )

    return {
        "employee_id": str(employee.id),
        "face_registration_status": employee.face_registration_status,
        "sample_count": len(embeddings),
        "model_version": MODEL_VERSION,
        "message": f"Enrolled {len(embeddings)} face sample(s).",
        "face_registered_at": (
            employee.face_registered_at.isoformat()
            if employee.face_registered_at
            else None
        ),
        "threshold": settings.face_match_threshold,
    }


def face_status_for_employee(db: Session, employee: Employee) -> dict:
    samples = (
        db.query(EmployeeFaceEmbedding)
        .filter(EmployeeFaceEmbedding.employee_id == employee.id)
        .order_by(EmployeeFaceEmbedding.sample_index.asc())
        .all()
    )
    model_version = samples[0].model_version if samples else None
    # Outdated/incompatible embeddings must not count as completed enrollment.
    status = employee.face_registration_status
    if samples and model_version != MODEL_VERSION:
        status = "not_registered"
        logger.info(
            "FACE_STATUS employee_id=%s model_stored=%s model_current=%s "
            "requires_reregistration=YES",
            employee.id,
            model_version,
            MODEL_VERSION,
        )
    return {
        "employee_id": str(employee.id),
        "face_registration_status": status,
        "sample_count": len(samples),
        "model_version": model_version,
        "face_registered_at": (
            employee.face_registered_at.isoformat()
            if employee.face_registered_at and status == "completed"
            else None
        ),
        "threshold": settings.face_match_threshold,
    }
