"""Owner face enrollment and sample verify endpoints."""

from __future__ import annotations

import uuid
from datetime import datetime, timezone
from typing import Annotated

from fastapi import APIRouter, Depends, File, Form, HTTPException, UploadFile
from sqlalchemy.orm import Session

from app.core.config import settings
from app.core.deps import require_roles
from app.db.session import get_db
from app.models.employee import Employee
from app.models.enums import UserRole
from app.models.face_embedding import EmployeeFaceEmbedding
from app.models.user import User
from app.schemas.face import FaceEnrollResponse, FaceStatusResponse, FaceVerifyResponse
from app.services.face_embedding import (
    MODEL_VERSION,
    best_match_score,
    detect_and_embed,
    match_passed,
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
    """Sample verify: compare one live image against an employee's enrolled samples."""
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
    score = best_match_score(probe, gallery)
    passed = match_passed(score)
    threshold = settings.face_match_threshold

    return FaceVerifyResponse(
        employee_id=str(emp.id),
        match_score=round(score, 4),
        passed=passed,
        threshold=threshold,
        model_version=MODEL_VERSION,
        message=(
            "Face match passed."
            if passed
            else f"Face match failed (score {score:.3f} < {threshold:.3f})."
        ),
    )
