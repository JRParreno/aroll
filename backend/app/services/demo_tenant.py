"""Server-side DEMO01 attendance helpers.

Demo behavior is decided only from the authenticated business record
(`business.is_demo`). Clients cannot opt in.
"""

from __future__ import annotations

import logging

from fastapi import HTTPException
from sqlalchemy.orm import Session

from app.models.business import Business, BusinessLocation
from app.models.employee import Employee
from app.models.face_embedding import EmployeeFaceEmbedding

logger = logging.getLogger("aroll.demo")

DEMO_ENROLLMENT_LOCKED = {
    "code": "demo_enrollment_locked",
    "message": (
        "Live face enrollment is disabled for the research/demo tenant. "
        "Demo Café uses seeded synthetic face identities only."
    ),
}


def business_is_demo(business: Business | None) -> bool:
    """True only for a real True flag — MagicMocks used in unit tests stay False."""
    if business is None:
        return False
    return getattr(business, "is_demo", False) is True


def raise_if_demo_enrollment_locked(business: Business | None) -> None:
    if business_is_demo(business):
        logger.info(
            "Demo face enrollment blocked business_code=%s",
            getattr(business, "business_code", None),
        )
        raise HTTPException(status_code=403, detail=DEMO_ENROLLMENT_LOCKED)


def verify_demo_seeded_identity(
    db: Session,
    employee: Employee,
    business: Business,
) -> float:
    """Resolve the logged-in demo employee against seeded embeddings.

    Does not run YuNet/ArcFace on a live probe. Confirms the employee belongs
    to this demo business and already has a seeded gallery.
    """
    from app.services.face_embedding import MODEL_VERSION

    if not business_is_demo(business):
        raise HTTPException(400, "Demo identity resolution is only for demo tenants.")
    if employee.business_id != business.id:
        raise HTTPException(
            403,
            detail={
                "code": "demo_employee_mismatch",
                "message": "This employee does not belong to the demo business.",
            },
        )

    samples = (
        db.query(EmployeeFaceEmbedding)
        .filter(EmployeeFaceEmbedding.employee_id == employee.id)
        .order_by(EmployeeFaceEmbedding.sample_index.asc())
        .all()
    )
    if not samples:
        raise HTTPException(
            400,
            detail={
                "code": "not_enrolled",
                "message": "Demo face identity is missing. Re-seed DEMO01.",
            },
        )
    stored_version = samples[0].model_version or ""
    if stored_version != MODEL_VERSION:
        raise HTTPException(
            400,
            detail={
                "code": "face_enrollment_required",
                "message": "Demo face identities need to be re-seeded for the current model.",
            },
        )
    if any(len(list(row.embedding)) != 512 for row in samples):
        raise HTTPException(
            500,
            detail={
                "code": "embedding_error",
                "message": "Stored demo face data is invalid.",
            },
        )

    logger.info(
        "Demo attendance flow used for business %s employee_id=%s "
        "seeded_samples=%s (no live probe, no YuNet)",
        business.business_code,
        employee.id,
        len(samples),
    )
    # Identity is the seeded gallery, not a live cosine against a camera frame.
    return 1.0


def substitute_demo_worksite_coordinates(
    *,
    business: Business | None,
    location: BusinessLocation,
    latitude: float,
    longitude: float,
) -> tuple[float, float]:
    """For demo tenants, ignore client coordinates and use the seeded worksite."""
    if not business_is_demo(business):
        return latitude, longitude
    if location.latitude is None or location.longitude is None:
        raise HTTPException(
            400,
            "Business location coordinates are missing. Ask your employer to update the work site.",
        )
    demo_lat = float(location.latitude)
    demo_lng = float(location.longitude)
    logger.info(
        "Demo location substituted from business worksite business_code=%s "
        "client_coords_ignored=yes",
        getattr(business, "business_code", None),
    )
    return demo_lat, demo_lng


def load_business_for_employee(db: Session, employee: Employee) -> Business | None:
    if employee.business_id is None:
        return None
    return db.get(Business, employee.business_id)
