"""Shared face sample enrollment for owner and employee self-enroll."""

from __future__ import annotations

import uuid
from datetime import datetime, timezone

from fastapi import HTTPException
from sqlalchemy.orm import Session

from app.core.config import settings
from app.models.employee import Employee
from app.models.face_embedding import EmployeeFaceEmbedding
from app.services.face_embedding import MODEL_VERSION, detect_and_embed


def enroll_face_sample_bytes(
    db: Session,
    employee: Employee,
    payloads: list[bytes],
    *,
    enrolled_by: uuid.UUID | None,
) -> dict:
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
    return {
        "employee_id": str(employee.id),
        "face_registration_status": employee.face_registration_status,
        "sample_count": len(samples),
        "model_version": model_version,
        "face_registered_at": (
            employee.face_registered_at.isoformat()
            if employee.face_registered_at
            else None
        ),
        "threshold": settings.face_match_threshold,
    }
