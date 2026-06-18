import secrets
import uuid
from calendar import month_abbr
from datetime import datetime, timedelta, timezone
from typing import Annotated
from app.core.timezone import manila_now

from fastapi import APIRouter, Depends, HTTPException
from fastapi.responses import FileResponse
from sqlalchemy import extract, func
from sqlalchemy.orm import Session

from app.core.deps import require_roles
from app.core.security import hash_password
from app.db.session import get_db
from app.models.activity_log import ActivityLog
from app.models.attendance import AttendanceRecord
from app.models.business import Business, BusinessLocation, BusinessRegistration
from app.models.employee import Employee
from app.models.enums import (
    ApplicationStatus,
    AttendanceStatus,
    BusinessStatus,
    RegistrationStatus,
    UserRole,
)
from app.models.registration_document import RegistrationDocument
from app.models.payroll import BusinessPayrollConfig
from app.models.user import User
from app.schemas.admin_business import (
    BusinessDetailResponse,
    BusinessListResponse,
    BusinessLocationResponse,
    BusinessOwnerResponse,
)
from app.schemas.admin_dashboard import (
    AttendanceSummary,
    DashboardStatsResponse,
    MonthlyRegistrationPoint,
    RecentActivityItem,
)
from app.schemas.registration import (
    RegistrationApproveResponse,
    RegistrationReject,
    RegistrationResponse,
)
from app.services.activity_logger import create_log
from app.services.registration_documents import get_document_file_path
from app.services.registration_service import document_response, registration_response


router = APIRouter(prefix="/admin", tags=["admin"])


def _gen_business_code() -> str:
    return f"MB-{secrets.token_hex(3).upper()[:6]}"


def _registration_response(reg: BusinessRegistration) -> RegistrationResponse:
    return registration_response(reg)


def _business_list_response(db: Session, business: Business) -> BusinessListResponse:
    employee_count = (
        db.query(Employee)
        .filter(Employee.business_id == business.id, Employee.is_active.is_(True))
        .count()
    )
    location_count = (
        db.query(BusinessLocation)
        .filter(BusinessLocation.business_id == business.id)
        .count()
    )
    return BusinessListResponse(
        id=str(business.id),
        business_code=business.business_code,
        name=business.name,
        status=business.status.value,
        timezone=business.timezone,
        created_at=business.created_at,
        employee_count=employee_count,
        location_count=location_count,
    )


def _business_detail_response(db: Session, business: Business) -> BusinessDetailResponse:
    employee_count = (
        db.query(Employee)
        .filter(Employee.business_id == business.id, Employee.is_active.is_(True))
        .count()
    )
    locations = (
        db.query(BusinessLocation)
        .filter(BusinessLocation.business_id == business.id)
        .order_by(BusinessLocation.is_primary.desc())
        .all()
    )

    owner: BusinessOwnerResponse | None = None
    registration_id: str | None = None
    registration_submitted_at = None
    registration_documents = []
    if business.registration_id:
        reg = db.get(BusinessRegistration, business.registration_id)
        if reg:
            owner = BusinessOwnerResponse(
                name=reg.owner_name,
                email=reg.owner_email,
                phone=reg.owner_phone,
            )
            registration_id = str(reg.id)
            registration_submitted_at = reg.submitted_at
            registration_documents = [
                document_response(doc) for doc in reg.documents
            ]

    return BusinessDetailResponse(
        id=str(business.id),
        business_code=business.business_code,
        name=business.name,
        status=business.status.value,
        timezone=business.timezone,
        created_at=business.created_at,
        employee_count=employee_count,
        owner=owner,
        registration_id=registration_id,
        registration_submitted_at=registration_submitted_at,
        registration_documents=registration_documents,
        locations=[
            BusinessLocationResponse(
                id=str(loc.id),
                label=loc.label,
                address=loc.address,
                latitude=float(loc.latitude) if loc.latitude is not None else None,
                longitude=float(loc.longitude) if loc.longitude is not None else None,
                geofence_radius_m=loc.geofence_radius_m,
                is_primary=loc.is_primary,
            )
            for loc in locations
        ],
    )


@router.get("/registrations", response_model=list[RegistrationResponse])
def list_registrations(
    db: Annotated[Session, Depends(get_db)],
    _: Annotated[User, Depends(require_roles(UserRole.platform_admin))],
    status_filter: str | None = None,
):
    q = db.query(BusinessRegistration).filter(
        BusinessRegistration.application_status != ApplicationStatus.draft
    )

    if status_filter and status_filter != "all":
        q = q.filter(
            BusinessRegistration.application_status
            == ApplicationStatus(status_filter)
        )

    rows = q.order_by(BusinessRegistration.submitted_at.desc().nullslast()).all()
    return [_registration_response(r) for r in rows]


@router.get("/registrations/{registration_id}", response_model=RegistrationResponse)
def get_registration(
    registration_id: uuid.UUID,
    db: Annotated[Session, Depends(get_db)],
    _: Annotated[User, Depends(require_roles(UserRole.platform_admin))],
):
    reg = db.get(BusinessRegistration, registration_id)
    if reg is None:
        raise HTTPException(404, "Registration not found")
    return _registration_response(reg)


@router.get("/registrations/{registration_id}/documents/{document_id}/file")
def download_registration_document(
    registration_id: uuid.UUID,
    document_id: uuid.UUID,
    db: Annotated[Session, Depends(get_db)],
    _: Annotated[User, Depends(require_roles(UserRole.platform_admin))],
):
    document = db.get(RegistrationDocument, document_id)
    if document is None or document.registration_id != registration_id:
        raise HTTPException(404, "Document not found")
    file_path = get_document_file_path(document)
    if not file_path.exists():
        raise HTTPException(404, "File not found on server")
    return FileResponse(
        path=file_path,
        media_type=document.content_type,
        filename=document.original_filename,
    )


@router.get("/dashboard-stats", response_model=DashboardStatsResponse)
def dashboard_stats(
    db: Session = Depends(get_db),
    _: User = Depends(require_roles(UserRole.platform_admin)),
):
    total_businesses = db.query(Business).count()

    pending_requests = db.query(BusinessRegistration).filter(
        BusinessRegistration.application_status == ApplicationStatus.pending
    ).count()

    active_businesses = (
        db.query(Business)
        .join(
            BusinessRegistration,
            Business.registration_id == BusinessRegistration.id,
        )
        .filter(
            BusinessRegistration.status == RegistrationStatus.approved,
            Business.status == BusinessStatus.active,
        )
        .count()
    )

    total_employees = (
        db.query(Employee).filter(Employee.is_active.is_(True)).count()
    )

    now = manila_now()
    year = now.year

    monthly_rows = (
        db.query(
            extract("month", BusinessRegistration.submitted_at).label("month"),
            func.count(BusinessRegistration.id).label("count"),
        )
        .filter(extract("year", BusinessRegistration.submitted_at) == year)
        .group_by(extract("month", BusinessRegistration.submitted_at))
        .all()
    )
    monthly_map = {int(row.month): int(row.count) for row in monthly_rows}
    monthly_registrations = [
        MonthlyRegistrationPoint(
            month=month_abbr[m][:3],
            count=monthly_map.get(m, 0),
        )
        for m in range(1, 13)
    ]

    today_start = now.replace(hour=0, minute=0, second=0, microsecond=0)
    today_end = today_start + timedelta(days=1)

    attendance_rows = (
        db.query(AttendanceRecord.status, func.count(AttendanceRecord.id))
        .filter(
            AttendanceRecord.created_at >= today_start.astimezone(timezone.utc),
            AttendanceRecord.created_at < today_end.astimezone(timezone.utc),
        )
        .group_by(AttendanceRecord.status)
        .all()
    )
    status_counts = {row[0]: int(row[1]) for row in attendance_rows}

    present = status_counts.get(AttendanceStatus.complete, 0) + status_counts.get(
        AttendanceStatus.in_progress, 0
    )
    absent = status_counts.get(AttendanceStatus.absent, 0)
    late = status_counts.get(AttendanceStatus.late, 0)
    attendance_total = present + absent + late
    present_rate = round((present / attendance_total) * 100, 1) if attendance_total else 0.0

    recent_logs = (
        db.query(ActivityLog)
        .order_by(ActivityLog.created_at.desc())
        .limit(5)
        .all()
    )

    return DashboardStatsResponse(
        total_businesses=total_businesses,
        active_businesses=active_businesses,
        pending_requests=pending_requests,
        total_employees=total_employees,
        monthly_registrations=monthly_registrations,
        attendance_summary=AttendanceSummary(
            present=present,
            absent=absent,
            late=late,
            present_rate=present_rate,
            has_data=attendance_total > 0,
        ),
        recent_activities=[
            RecentActivityItem(
                id=str(log.id),
                description=log.description,
                created_at=log.created_at,
            )
            for log in recent_logs
        ],
    )

@router.get("/businesses", response_model=list[BusinessListResponse])
def list_businesses(
    db: Session = Depends(get_db),
    _: User = Depends(require_roles(UserRole.platform_admin)),
):
    businesses = db.query(Business).order_by(Business.created_at.desc()).all()
    return [_business_list_response(db, b) for b in businesses]


@router.get("/businesses/{business_id}", response_model=BusinessDetailResponse)
def get_business(
    business_id: uuid.UUID,
    db: Annotated[Session, Depends(get_db)],
    _: Annotated[User, Depends(require_roles(UserRole.platform_admin))],
):
    business = db.get(Business, business_id)
    if business is None:
        raise HTTPException(404, "Business not found")
    return _business_detail_response(db, business)

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

    if reg.application_status != ApplicationStatus.pending:
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
        status=BusinessStatus.inactive,
    )
    db.add(business)
    db.flush()

    # Create owner account
    owner = User(
        business_id=business.id,
        email=reg.owner_email.lower(),
        password_hash=hash_password(code),
        role=UserRole.owner,
        must_change_password=True,
    )
    db.add(owner)

    # Create payroll config
    db.add(BusinessPayrollConfig(business_id=business.id))

    # Update registration status
    reg.status = RegistrationStatus.approved
    reg.application_status = ApplicationStatus.approved
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

    if reg.application_status != ApplicationStatus.pending:
        raise HTTPException(400, "Registration is not pending")

    reg.status = RegistrationStatus.rejected
    reg.application_status = ApplicationStatus.rejected
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
