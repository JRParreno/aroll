import secrets
import uuid
from datetime import datetime, timezone
from typing import Annotated

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session

from app.core.deps import require_roles
from app.core.security import hash_password
from app.db.session import get_db
from app.models.business import Business, BusinessRegistration
from app.models.enums import BusinessStatus, RegistrationStatus, UserRole
from app.models.payroll import BusinessPayrollConfig
from app.models.user import User
from app.schemas.registration import ( RegistrationApproveResponse, RegistrationReject, RegistrationResponse,)
from app.services.activity_logger import create_log
from app.models.activity_log import ActivityLog


router = APIRouter(prefix="/admin", tags=["admin"])


def _gen_business_code() -> str:
    return f"MB-{secrets.token_hex(3).upper()[:6]}"


@router.get("/registrations", response_model=list[RegistrationResponse])
def list_registrations(
    db: Annotated[Session, Depends(get_db)],
    _: Annotated[User, Depends(require_roles(UserRole.platform_admin))],
    status_filter: str | None = None
):
    q = db.query(BusinessRegistration)

    if status_filter and status_filter != "all":
        q = q.filter(
            BusinessRegistration.status == RegistrationStatus(status_filter)
    )
    rows = q.order_by(BusinessRegistration.submitted_at.desc()).all()
    return [
        RegistrationResponse(
            id=str(r.id),
            business_name=r.business_name,
            owner_name=r.owner_name,
            owner_email=r.owner_email,
            status=r.status.value,
            submitted_at=r.submitted_at,
        )
        for r in rows
    ]

@router.get("/dashboard-stats")
def dashboard_stats(
    db: Session = Depends(get_db),
    _: User = Depends(require_roles(UserRole.platform_admin)),
):
    total_businesses = db.query(Business).count()

    pending_requests = db.query(BusinessRegistration).filter(
        BusinessRegistration.status == RegistrationStatus.pending
    ).count()

    active_businesses = db.query(Business).filter(
        Business.status == BusinessStatus.active
    ).count()

    return {
        "total_businesses": total_businesses,
        "pending_requests": pending_requests,
        "active_businesses": active_businesses,
    }

@router.get("/businesses")
def list_businesses(
    db: Session = Depends(get_db),
    _: User = Depends(require_roles(UserRole.platform_admin)),
):
    return db.query(Business).all()

@router.post(
    "/registrations/{registration_id}/approve",
    response_model=RegistrationApproveResponse,
)
def approve_registration(
    registration_id: uuid.UUID,
    db: Annotated[Session, Depends(get_db)],
    admin: Annotated[User, Depends(require_roles(UserRole.platform_admin))],
):
    reg = db.get(BusinessRegistration, registration_id)
    if reg is None:
        raise HTTPException(404, "Registration not found")

    if reg.status != RegistrationStatus.pending:
        raise HTTPException(400, "Registration is not pending")

    # Generate unique business code
    code = _gen_business_code()
    while db.query(Business).filter(Business.business_code == code).first():
        code = _gen_business_code()

    # Create business
    business = Business(
        registration_id=reg.id,
        business_code=code,
        name=reg.business_name,
        status=BusinessStatus.active,
    )
    db.add(business)
    db.flush()

    # Create owner account
    owner = User(
        business_id=business.id,
        email=reg.owner_email.lower(),
        password_hash=hash_password("changeme123"),
        role=UserRole.owner,
        must_change_password=True,
    )
    db.add(owner)

    # Create payroll config
    db.add(BusinessPayrollConfig(business_id=business.id))

    # Update registration status
    reg.status = RegistrationStatus.approved
    reg.reviewed_by = admin.id
    reg.reviewed_at = datetime.now(timezone.utc)

    db.commit()

    # ✅ ACTIVITY LOG (CORRECT PLACE)
    create_log(
        db=db,
        user_id=admin.id,
        action="APPROVE_REGISTRATION",
        description=f"Approved registration for {reg.business_name}",
    )

    return RegistrationApproveResponse(
        business_id=str(business.id),
        business_code=business.business_code,
        owner_email=reg.owner_email,
    )


@router.post("/registrations/{registration_id}/reject")
def reject_registration(
    registration_id: uuid.UUID,
    body: RegistrationReject,
    db: Annotated[Session, Depends(get_db)],
    admin: Annotated[User, Depends(require_roles(UserRole.platform_admin))],
):
    reg = db.get(BusinessRegistration, registration_id)
    if reg is None:
        raise HTTPException(404, "Registration not found")

    if reg.status != RegistrationStatus.pending:
        raise HTTPException(400, "Registration is not pending")

    reg.status = RegistrationStatus.rejected
    reg.rejection_reason = body.rejection_reason
    reg.reviewed_by = admin.id
    reg.reviewed_at = datetime.now(timezone.utc)

    db.commit()

    create_log(
        db=db,
        user_id=admin.id,
        action="REJECT_REGISTRATION",
        description=f"Rejected registration for {reg.business_name}",
    )

    return {"status": "rejected"}

@router.get("/activity-logs")
def get_activity_logs(
    db: Session = Depends(get_db),
    _: User = Depends(require_roles(UserRole.platform_admin)),
):
    logs = (
        db.query(ActivityLog)
        .order_by(ActivityLog.created_at.desc())
        .limit(50)
        .all()
    )

    return [
        {
            "id": str(log.id),
            "user_id": str(log.user_id) if log.user_id else None,
            "action": log.action,
            "description": log.description,
            "created_at": log.created_at,
        }
        for log in logs
    ]
