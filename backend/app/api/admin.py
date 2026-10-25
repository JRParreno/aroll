import secrets
import uuid
from calendar import month_abbr
from datetime import date, datetime, time, timedelta, timezone
from typing import Annotated
from app.core.timezone import get_manila_tz, manila_now

from fastapi import APIRouter, Depends, File, HTTPException, Query, UploadFile
from fastapi.responses import FileResponse
from sqlalchemy import extract, func, or_
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
    RegistrationApprovalEmailResponse,
    RegistrationApproveResponse,
    RegistrationReject,
    RegistrationRejectResponse,
    RegistrationResponse,
)
from app.schemas.legal_consent import (
    PlatformLegalSettingsResponse,
    PlatformLegalSettingsUpdate,
)
from app.schemas.consent_catalog import (
    ConsentCatalogResponse,
    ConsentDocumentCreate,
    ConsentDocumentPayload,
    ConsentDocumentReorder,
    ConsentDocumentUpdate,
)
from app.services.activity_logger import create_log
from app.services.approval_email import (
    EMAIL_FAILED,
    EMAIL_NOT_SENT,
    EMAIL_SENT,
    ApprovalEmailConfigError,
    send_approved_registration_email,
    send_rejection_message,
)
from app.services.consent_catalog import (
    SCOPE_PLATFORM,
    catalog_item_payload,
    create_document,
    delete_document,
    get_document,
    legal_ui_catalog_payloads,
    list_catalog_documents,
    reorder_documents,
    save_document_file,
    update_document,
)
from app.services.legal_consent import (
    apply_platform_legal_update,
    ensure_platform_legal_defaults,
    platform_legal_payload,
)
from app.services.registration_documents import get_document_file_path
from app.services.registration_rejection import (
    format_rejection_reasons,
    validate_rejection_reasons,
)
from app.services.registration_service import document_response, registration_response


router = APIRouter(prefix="/admin", tags=["admin"])


def _gen_business_code() -> str:
    return f"MB-{secrets.token_hex(3).upper()[:6]}"


def _registration_response(reg: BusinessRegistration) -> RegistrationResponse:
    return registration_response(reg)


def _business_list_response(
    db: Session,
    business: Business,
    registration: BusinessRegistration | None = None,
) -> BusinessListResponse:
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
    if registration is None and business.registration_id:
        registration = db.get(BusinessRegistration, business.registration_id)
    approved_at = None
    owner_email = None
    approval_email_status = None
    registration_id = None
    if registration is not None:
        registration_id = str(registration.id)
        owner_email = registration.owner_email
        if registration.application_status == ApplicationStatus.approved:
            approved_at = registration.reviewed_at
        approval_email_status = registration.approval_email_status
    return BusinessListResponse(
        id=str(business.id),
        business_code=business.business_code,
        name=business.name,
        status=business.status.value,
        timezone=business.timezone,
        created_at=business.created_at,
        employee_count=employee_count,
        location_count=location_count,
        is_demo=bool(business.is_demo),
        is_internal_test=bool(business.is_internal_test),
        registration_id=registration_id,
        owner_email=owner_email,
        approved_at=approved_at,
        approval_email_status=approval_email_status,
    )


def _approval_range_utc(
    approved_from: date | None, approved_to: date | None
) -> tuple[datetime | None, datetime | None]:
    tz = get_manila_tz()
    start = None
    end = None
    if approved_from is not None:
        start = datetime.combine(approved_from, time.min, tzinfo=tz).astimezone(
            timezone.utc
        )
    if approved_to is not None:
        end = datetime.combine(
            approved_to + timedelta(days=1), time.min, tzinfo=tz
        ).astimezone(timezone.utc)
    return start, end


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
        is_demo=bool(business.is_demo),
        is_internal_test=bool(business.is_internal_test),
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
    approved_from: date | None = Query(None),
    approved_to: date | None = Query(None),
    email_status: str | None = Query(None),
):
    if approved_from and approved_to and approved_to < approved_from:
        raise HTTPException(400, "End date cannot be earlier than start date")

    allowed_email = {None, "pending", "sent", "failed", "not_sent"}
    if email_status not in allowed_email:
        raise HTTPException(400, "Invalid email status filter")

    start, end = _approval_range_utc(approved_from, approved_to)
    needs_registration = bool(start or end or email_status)
    q = db.query(Business, BusinessRegistration).outerjoin(
        BusinessRegistration,
        Business.registration_id == BusinessRegistration.id,
    )
    if needs_registration:
        q = q.filter(Business.registration_id.isnot(None))
    if start is not None or end is not None:
        q = q.filter(
            BusinessRegistration.application_status == ApplicationStatus.approved,
            BusinessRegistration.reviewed_at.isnot(None),
        )
        if start is not None:
            q = q.filter(BusinessRegistration.reviewed_at >= start)
        if end is not None:
            q = q.filter(BusinessRegistration.reviewed_at < end)
    if email_status == "pending":
        q = q.filter(
            or_(
                BusinessRegistration.approval_email_status.is_(None),
                BusinessRegistration.approval_email_status != EMAIL_SENT,
            )
        )
    elif email_status == "sent":
        q = q.filter(BusinessRegistration.approval_email_status == EMAIL_SENT)
    elif email_status == "failed":
        q = q.filter(BusinessRegistration.approval_email_status == EMAIL_FAILED)
    elif email_status == "not_sent":
        q = q.filter(
            or_(
                BusinessRegistration.approval_email_status.is_(None),
                BusinessRegistration.approval_email_status == EMAIL_NOT_SENT,
            )
        )

    if start is not None or end is not None:
        q = q.order_by(
            BusinessRegistration.reviewed_at.desc().nullslast(),
            Business.created_at.desc(),
        )
    else:
        q = q.order_by(Business.created_at.desc())

    rows = q.all()
    return [_business_list_response(db, business, registration) for business, registration in rows]


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
    if not (reg.approval_email_status or "").strip():
        reg.approval_email_status = EMAIL_NOT_SENT

    db.commit()

    # Approval is already committed. A log failure must not fail this response
    # or cause a retry that looks like an unapproved registration.
    try:
        create_log(
            db=db,
            user_id=admin.id,
            action="APPROVE_REGISTRATION",
            description=f"Approved registration for {reg.business_name}",
        )
    except Exception:
        pass

    return RegistrationApproveResponse(
        business_id=str(business.id),
        business_code=business.business_code,
        owner_email=reg.owner_email,
    )


@router.post(
    "/registrations/{registration_id}/send-approval-email",
    response_model=RegistrationApprovalEmailResponse,
)
def send_registration_approval_email(
    registration_id: uuid.UUID,
    db: Annotated[Session, Depends(get_db)],
    admin: Annotated[User, Depends(require_roles(UserRole.platform_admin))],
):
    result = send_approved_registration_email(
        db, registration_id, admin_id=admin.id
    )
    return RegistrationApprovalEmailResponse(**result)


@router.post(
    "/registrations/{registration_id}/reject",
    response_model=RegistrationRejectResponse,
)
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

    reason_ids = validate_rejection_reasons(body.reasons, body.other_explanation)
    explanation = (body.other_explanation or "").strip() or None

    reg.status = RegistrationStatus.rejected
    reg.application_status = ApplicationStatus.rejected
    reg.rejection_reason = format_rejection_reasons(reason_ids, explanation)
    reg.reviewed_by = admin.id
    reg.reviewed_at = datetime.now(timezone.utc)

    db.commit()

    try:
        create_log(
            db=db,
            user_id=admin.id,
            action="REJECT_REGISTRATION",
            description=f"Rejected registration for {reg.business_name}",
        )
    except Exception:
        pass

    email_status = EMAIL_NOT_SENT
    email_error = None
    recipient = None
    try:
        recipient = send_rejection_message(reg)
        email_status = EMAIL_SENT
    except ApprovalEmailConfigError:
        email_status = EMAIL_NOT_SENT
        email_error = (
            "Email delivery is not configured. Set SMTP_HOST, SMTP_FROM_EMAIL, "
            "and SMTP credentials."
        )
    except Exception:
        email_status = EMAIL_FAILED
        email_error = "The email provider could not accept the message."

    return RegistrationRejectResponse(
        status="rejected",
        email_status=email_status,
        email_error=email_error,
        recipient=recipient,
    )

@router.get("/activity-logs")
def get_activity_logs(
    db: Session = Depends(get_db),
    _: User = Depends(require_roles(UserRole.platform_admin)),
):
    logs = (
        db.query(ActivityLog, User)
        .join(User, ActivityLog.user_id == User.id)
        .filter(User.role == UserRole.platform_admin)
        .order_by(ActivityLog.created_at.desc())
        .limit(50)
        .all()
    )

    return [
        {
            "id": str(log.id),
            "user_id": str(log.user_id) if log.user_id else None,
            "actor_email": user.email,
            "actor_role": user.role.value,
            "action": log.action,
            "description": log.description,
            "created_at": log.created_at,
        }
        for log, user in logs
    ]


@router.get("/legal", response_model=PlatformLegalSettingsResponse)
def get_platform_legal_defaults(
    db: Annotated[Session, Depends(get_db)],
    _: Annotated[User, Depends(require_roles(UserRole.platform_admin))],
):
    ensure_platform_legal_defaults(db)
    db.commit()
    return PlatformLegalSettingsResponse(**platform_legal_payload(db))


@router.put("/legal", response_model=PlatformLegalSettingsResponse)
def update_platform_legal_defaults(
    body: PlatformLegalSettingsUpdate,
    db: Annotated[Session, Depends(get_db)],
    admin: Annotated[User, Depends(require_roles(UserRole.platform_admin))],
):
    apply_platform_legal_update(db, body, updated_by=admin.id)
    db.commit()
    return PlatformLegalSettingsResponse(**platform_legal_payload(db))


def _assert_platform_document(document) -> None:
    if document.scope != SCOPE_PLATFORM:
        raise HTTPException(404, "Consent document not found")


@router.get("/consents", response_model=ConsentCatalogResponse)
def list_platform_consents(
    db: Annotated[Session, Depends(get_db)],
    _: Annotated[User, Depends(require_roles(UserRole.platform_admin))],
):
    ensure_platform_legal_defaults(db)
    db.commit()
    documents = list_catalog_documents(db, scope=SCOPE_PLATFORM, business_id=None)
    return ConsentCatalogResponse(
        use_custom_consents=False,
        can_edit=True,
        documents=[
            ConsentDocumentPayload(**item)
            for item in legal_ui_catalog_payloads(documents)
        ],
    )


@router.post("/consents", response_model=ConsentDocumentPayload)
def create_platform_consent(
    body: ConsentDocumentCreate,
    db: Annotated[Session, Depends(get_db)],
    admin: Annotated[User, Depends(require_roles(UserRole.platform_admin))],
):
    document = create_document(
        db,
        scope=SCOPE_PLATFORM,
        business_id=None,
        title=body.title,
        body_text=body.body_text,
        consent_type=body.consent_type,
        position=body.position,
        is_active=body.is_active,
        is_required=body.is_required,
        version=body.version,
        updated_by=admin.id,
    )
    db.commit()
    db.refresh(document)
    return ConsentDocumentPayload(**catalog_item_payload(document))


@router.patch("/consents/{document_id}", response_model=ConsentDocumentPayload)
def update_platform_consent(
    document_id: uuid.UUID,
    body: ConsentDocumentUpdate,
    db: Annotated[Session, Depends(get_db)],
    admin: Annotated[User, Depends(require_roles(UserRole.platform_admin))],
):
    document = get_document(db, document_id)
    _assert_platform_document(document)
    update_document(
        db,
        document,
        title=body.title,
        body_text=body.body_text,
        consent_type=body.consent_type,
        position=body.position,
        is_active=body.is_active,
        is_required=body.is_required,
        version=body.version,
        bump_version=body.body_text is not None,
        updated_by=admin.id,
    )
    db.commit()
    db.refresh(document)
    return ConsentDocumentPayload(**catalog_item_payload(document))


@router.delete("/consents/{document_id}")
def delete_platform_consent(
    document_id: uuid.UUID,
    db: Annotated[Session, Depends(get_db)],
    _: Annotated[User, Depends(require_roles(UserRole.platform_admin))],
):
    document = get_document(db, document_id)
    _assert_platform_document(document)
    delete_document(db, document)
    db.commit()
    return {"status": "ok"}


@router.post("/consents/reorder", response_model=ConsentCatalogResponse)
def reorder_platform_consents(
    body: ConsentDocumentReorder,
    db: Annotated[Session, Depends(get_db)],
    admin: Annotated[User, Depends(require_roles(UserRole.platform_admin))],
):
    documents = reorder_documents(
        db,
        scope=SCOPE_PLATFORM,
        business_id=None,
        ordered_ids=body.ordered_ids,
        updated_by=admin.id,
    )
    db.commit()
    return ConsentCatalogResponse(
        use_custom_consents=False,
        can_edit=True,
        documents=[
            ConsentDocumentPayload(**item)
            for item in legal_ui_catalog_payloads(documents)
        ],
    )


@router.post("/consents/{document_id}/file", response_model=ConsentDocumentPayload)
def upload_platform_consent_file(
    document_id: uuid.UUID,
    db: Annotated[Session, Depends(get_db)],
    admin: Annotated[User, Depends(require_roles(UserRole.platform_admin))],
    file: Annotated[UploadFile, File()],
):
    document = get_document(db, document_id)
    _assert_platform_document(document)
    save_document_file(db, document, file, updated_by=admin.id)
    db.commit()
    db.refresh(document)
    return ConsentDocumentPayload(**catalog_item_payload(document))
