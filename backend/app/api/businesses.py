from typing import Annotated
import uuid

from fastapi import APIRouter, Depends, HTTPException
from fastapi.responses import FileResponse
from sqlalchemy.orm import Session

from app.core.deps import require_roles
from app.db.session import get_db
from app.models.attendance_policy import BusinessAttendancePolicy
from app.models.business import Business, BusinessLocation, BusinessRegistration
from app.models.enums import MissingClockOutPolicy, UserRole, Weekday
from app.models.payroll import BusinessPayrollConfig
from app.models.registration_document import RegistrationDocument
from app.models.rest_day_policy import BusinessRestDayPolicy
from app.models.user import User
from app.schemas.business import (
    AccountSettingsResponse,
    AccountSettingsUpdate,
    BusinessSettingsResponse,
    LocationResponse,
    LocationUpdate,
)
from app.schemas.owner_setup import (
    AttendancePolicyResponse,
    AttendancePolicyUpdate,
    PayrollConfigResponse,
    PayrollConfigUpdate,
    RestDayPolicyResponse,
    RestDayPolicyUpdate,
    SetupStatusResponse,
)
from app.services.setup_status import (
    SetupIncompleteError,
    complete_setup,
    get_setup_status,
)
from app.services.registration_documents import get_document_file_path
from app.services.registration_service import document_response

router = APIRouter(prefix="/businesses", tags=["businesses"])


def _attendance_policy_response(
    db: Session, business_id, policy: BusinessAttendancePolicy | None
) -> AttendancePolicyResponse:
    if policy is not None:
        return AttendancePolicyResponse(
            early_clock_in_minutes=policy.early_clock_in_minutes,
            on_time_grace_minutes=policy.on_time_grace_minutes,
            half_day_threshold_minutes=policy.half_day_threshold_minutes,
            absent_threshold_minutes=policy.absent_threshold_minutes,
            early_out_deduction_enabled=policy.early_out_deduction_enabled,
            early_out_deduction_per_minute=float(policy.early_out_deduction_per_minute),
            overtime_enabled=policy.overtime_enabled,
            overtime_minimum_minutes=policy.overtime_minimum_minutes,
            overtime_rate_per_minute=float(policy.overtime_rate_per_minute),
            missing_clock_out_policy=policy.missing_clock_out_policy.value,
            attendance_based_salary_enabled=policy.attendance_based_salary_enabled,
        )

    payroll_cfg = db.get(BusinessPayrollConfig, business_id)
    return AttendancePolicyResponse(
        early_clock_in_minutes=15,
        on_time_grace_minutes=10,
        half_day_threshold_minutes=120,
        absent_threshold_minutes=240,
        early_out_deduction_enabled=False,
        early_out_deduction_per_minute=2.0,
        overtime_enabled=payroll_cfg.overtime_enabled if payroll_cfg else True,
        overtime_minimum_minutes=30,
        overtime_rate_per_minute=float(payroll_cfg.overtime_per_minute)
        if payroll_cfg
        else 1.0,
        missing_clock_out_policy=MissingClockOutPolicy.auto_clock_out.value,
        attendance_based_salary_enabled=True,
    )


def _rest_day_policy_response(
    policy: BusinessRestDayPolicy | None,
) -> RestDayPolicyResponse:
    if policy is not None:
        return RestDayPolicyResponse(
            weekly_rest_day=policy.weekly_rest_day.value,
            work_on_rest_day_allowed=policy.work_on_rest_day_allowed,
            rest_day_premium_percent=float(policy.rest_day_premium_percent),
            use_custom_premium=policy.use_custom_premium,
            custom_premium_percent=float(policy.custom_premium_percent)
            if policy.custom_premium_percent is not None
            else None,
        )

    return RestDayPolicyResponse(
        weekly_rest_day=Weekday.sunday.value,
        work_on_rest_day_allowed=False,
        rest_day_premium_percent=30.0,
        use_custom_premium=False,
        custom_premium_percent=None,
    )


@router.get("/me/setup-status", response_model=SetupStatusResponse)
def setup_status(
    db: Annotated[Session, Depends(get_db)],
    user: Annotated[User, Depends(require_roles(UserRole.owner, UserRole.manager))],
):
    if user.business_id is None:
        raise HTTPException(400, "No business context")
    business = db.get(Business, user.business_id)
    if business is None:
        raise HTTPException(404, "Business not found")
    return get_setup_status(db, business)


@router.post("/me/complete-setup")
def mark_setup_complete(
    db: Annotated[Session, Depends(get_db)],
    user: Annotated[User, Depends(require_roles(UserRole.owner))],
):
    if user.business_id is None:
        raise HTTPException(400, "No business context")
    business = db.get(Business, user.business_id)
    if business is None:
        raise HTTPException(404, "Business not found")
    try:
        complete_setup(db, business)
    except SetupIncompleteError as exc:
        raise HTTPException(
            status_code=400,
            detail={"message": "Setup incomplete", "missing_items": exc.missing_items},
        ) from exc
    return {"status": "ok"}


@router.get("/me/payroll-config", response_model=PayrollConfigResponse)
def get_payroll_config(
    db: Annotated[Session, Depends(get_db)],
    user: Annotated[User, Depends(require_roles(UserRole.owner, UserRole.manager))],
):
    if user.business_id is None:
        raise HTTPException(400, "No business context")
    cfg = db.get(BusinessPayrollConfig, user.business_id)
    if cfg is None:
        cfg = BusinessPayrollConfig(business_id=user.business_id)
        db.add(cfg)
        db.commit()
        db.refresh(cfg)
    return PayrollConfigResponse(
        pay_period_type=cfg.pay_period_type.value,
        next_payday_date=cfg.next_payday_date,
        auto_reset_payroll_cycle=cfg.auto_reset_payroll_cycle,
        late_deduction_enabled=cfg.late_deduction_enabled,
        late_deduction_per_minute=float(cfg.late_deduction_per_minute),
        overtime_enabled=cfg.overtime_enabled,
        overtime_per_minute=float(cfg.overtime_per_minute),
    )


@router.put("/me/payroll-config")
def update_payroll_config(
    body: PayrollConfigUpdate,
    db: Annotated[Session, Depends(get_db)],
    user: Annotated[User, Depends(require_roles(UserRole.owner, UserRole.manager))],
):
    if user.business_id is None:
        raise HTTPException(400, "No business context")

    cfg = db.get(BusinessPayrollConfig, user.business_id)
    if cfg is None:
        cfg = BusinessPayrollConfig(business_id=user.business_id)
        db.add(cfg)
    cfg.pay_period_type = body.pay_period_type
    cfg.next_payday_date = body.next_payday_date
    cfg.auto_reset_payroll_cycle = body.auto_reset_payroll_cycle
    cfg.late_deduction_enabled = body.late_deduction_enabled
    cfg.late_deduction_per_minute = body.late_deduction_per_minute
    cfg.overtime_enabled = body.overtime_enabled
    cfg.overtime_per_minute = body.overtime_per_minute
    db.commit()

    policy = db.get(BusinessAttendancePolicy, user.business_id)
    if policy is not None:
        policy.overtime_rate_per_minute = body.overtime_per_minute
        policy.overtime_enabled = body.overtime_enabled
        db.commit()

    return {"status": "ok"}


@router.get("/me/attendance-policy", response_model=AttendancePolicyResponse)
def get_attendance_policy(
    db: Annotated[Session, Depends(get_db)],
    user: Annotated[User, Depends(require_roles(UserRole.owner, UserRole.manager))],
):
    if user.business_id is None:
        raise HTTPException(400, "No business context")
    policy = db.get(BusinessAttendancePolicy, user.business_id)
    return _attendance_policy_response(db, user.business_id, policy)


@router.put("/me/attendance-policy")
def update_attendance_policy(
    body: AttendancePolicyUpdate,
    db: Annotated[Session, Depends(get_db)],
    user: Annotated[User, Depends(require_roles(UserRole.owner, UserRole.manager))],
):
    if user.business_id is None:
        raise HTTPException(400, "No business context")
    policy = db.get(BusinessAttendancePolicy, user.business_id)
    if policy is None:
        policy = BusinessAttendancePolicy(business_id=user.business_id)
        db.add(policy)
    payroll_cfg = db.get(BusinessPayrollConfig, user.business_id)
    payload = body.model_dump()
    if payroll_cfg is not None:
        payload["overtime_rate_per_minute"] = float(payroll_cfg.overtime_per_minute)
        payload["overtime_enabled"] = payroll_cfg.overtime_enabled
    for field, value in payload.items():
        setattr(policy, field, value)
    db.commit()
    return {"status": "ok"}


@router.get("/me/rest-day-policy", response_model=RestDayPolicyResponse)
def get_rest_day_policy(
    db: Annotated[Session, Depends(get_db)],
    user: Annotated[User, Depends(require_roles(UserRole.owner, UserRole.manager))],
):
    if user.business_id is None:
        raise HTTPException(400, "No business context")
    policy = db.get(BusinessRestDayPolicy, user.business_id)
    return _rest_day_policy_response(policy)


@router.put("/me/rest-day-policy")
def update_rest_day_policy(
    body: RestDayPolicyUpdate,
    db: Annotated[Session, Depends(get_db)],
    user: Annotated[User, Depends(require_roles(UserRole.owner, UserRole.manager))],
):
    if user.business_id is None:
        raise HTTPException(400, "No business context")
    policy = db.get(BusinessRestDayPolicy, user.business_id)
    if policy is None:
        policy = BusinessRestDayPolicy(business_id=user.business_id)
        db.add(policy)
    for field, value in body.model_dump().items():
        setattr(policy, field, value)
    db.commit()
    return {"status": "ok"}


@router.get("/me/location", response_model=LocationResponse)
def get_location(
    db: Annotated[Session, Depends(get_db)],
    user: Annotated[User, Depends(require_roles(UserRole.owner, UserRole.manager))],
):
    if user.business_id is None:
        raise HTTPException(400, "No business context")

    loc = (
        db.query(BusinessLocation)
        .filter(
            BusinessLocation.business_id == user.business_id,
            BusinessLocation.is_primary.is_(True),
        )
        .first()
    )
    if loc is None:
        return LocationResponse(
            label="Main",
            address="",
            latitude=None,
            longitude=None,
            geofence_radius_m=75,
        )
    return LocationResponse(
        label=loc.label,
        address=loc.address,
        latitude=float(loc.latitude) if loc.latitude is not None else None,
        longitude=float(loc.longitude) if loc.longitude is not None else None,
        geofence_radius_m=loc.geofence_radius_m,
    )


@router.put("/me/location")
def update_location(
    body: LocationUpdate,
    db: Annotated[Session, Depends(get_db)],
    user: Annotated[User, Depends(require_roles(UserRole.owner))],
):
    if user.business_id is None:
        raise HTTPException(400, "No business context")

    loc = (
        db.query(BusinessLocation)
        .filter(
            BusinessLocation.business_id == user.business_id,
            BusinessLocation.is_primary.is_(True),
        )
        .first()
    )
    if loc is None:
        loc = BusinessLocation(
            business_id=user.business_id,
            label=body.label,
            address=body.address,
            latitude=body.latitude,
            longitude=body.longitude,
            geofence_radius_m=body.geofence_radius_m,
            is_primary=True,
        )
        db.add(loc)
    else:
        loc.label = body.label
        loc.address = body.address
        loc.latitude = body.latitude
        loc.longitude = body.longitude
        loc.geofence_radius_m = body.geofence_radius_m
    db.commit()
    return {"status": "ok"}


def _account_settings_response(
    db: Session, user: User, business: Business
) -> AccountSettingsResponse:
    reg = (
        db.get(BusinessRegistration, business.registration_id)
        if business.registration_id
        else None
    )
    loc = (
        db.query(BusinessLocation)
        .filter(
            BusinessLocation.business_id == business.id,
            BusinessLocation.is_primary.is_(True),
        )
        .first()
    )
    address = loc.address if loc else (reg.proposed_address if reg else "")
    return AccountSettingsResponse(
        business_name=business.name,
        owner_name=reg.owner_name if reg else None,
        email=user.email,
        contact_phone=reg.owner_phone if reg else None,
        address=address or "",
        business_type=business.business_type,
    )


def _business_settings_response(
    db: Session, user: User, business: Business
) -> BusinessSettingsResponse:
    reg = (
        db.get(BusinessRegistration, business.registration_id)
        if business.registration_id
        else None
    )
    loc = (
        db.query(BusinessLocation)
        .filter(
            BusinessLocation.business_id == business.id,
            BusinessLocation.is_primary.is_(True),
        )
        .first()
    )
    address = loc.address if loc else (reg.proposed_address if reg else "")
    documents = (
        [document_response(doc) for doc in reg.documents] if reg is not None else []
    )
    return BusinessSettingsResponse(
        business_name=business.name,
        business_type=business.business_type,
        business_code=business.business_code,
        address=address or "",
        owner_name=reg.owner_name if reg else None,
        owner_email=user.email,
        owner_phone=reg.owner_phone if reg else None,
        registration_id=str(business.registration_id) if business.registration_id else None,
        application_status=reg.application_status.value if reg else None,
        registration_documents=documents,
    )


@router.get("/me/business-settings", response_model=BusinessSettingsResponse)
def get_business_settings(
    db: Annotated[Session, Depends(get_db)],
    user: Annotated[User, Depends(require_roles(UserRole.owner))],
):
    if user.business_id is None:
        raise HTTPException(400, "No business context")
    business = db.get(Business, user.business_id)
    if business is None:
        raise HTTPException(404, "Business not found")
    return _business_settings_response(db, user, business)


@router.get("/me/registration-documents/{document_id}/file")
def download_owner_registration_document(
    document_id: uuid.UUID,
    db: Annotated[Session, Depends(get_db)],
    user: Annotated[User, Depends(require_roles(UserRole.owner))],
):
    if user.business_id is None:
        raise HTTPException(400, "No business context")
    business = db.get(Business, user.business_id)
    if business is None or business.registration_id is None:
        raise HTTPException(404, "Business registration not found")

    document = db.get(RegistrationDocument, document_id)
    if document is None or document.registration_id != business.registration_id:
        raise HTTPException(404, "Document not found")

    file_path = get_document_file_path(document)
    if not file_path.exists():
        raise HTTPException(404, "File not found on server")
    return FileResponse(
        path=file_path,
        media_type=document.content_type,
        filename=document.original_filename,
    )


@router.get("/me/account-settings", response_model=AccountSettingsResponse)
def get_account_settings(
    db: Annotated[Session, Depends(get_db)],
    user: Annotated[User, Depends(require_roles(UserRole.owner))],
):
    if user.business_id is None:
        raise HTTPException(400, "No business context")
    business = db.get(Business, user.business_id)
    if business is None:
        raise HTTPException(404, "Business not found")
    return _account_settings_response(db, user, business)


@router.put("/me/account-settings")
def update_account_settings(
    body: AccountSettingsUpdate,
    db: Annotated[Session, Depends(get_db)],
    user: Annotated[User, Depends(require_roles(UserRole.owner))],
):
    if user.business_id is None:
        raise HTTPException(400, "No business context")
    business = db.get(Business, user.business_id)
    if business is None:
        raise HTTPException(404, "Business not found")

    business.name = body.business_name
    business.business_type = body.business_type

    if business.registration_id:
        reg = db.get(BusinessRegistration, business.registration_id)
        if reg:
            reg.owner_name = body.owner_name
            reg.owner_phone = body.contact_phone

    loc = (
        db.query(BusinessLocation)
        .filter(
            BusinessLocation.business_id == business.id,
            BusinessLocation.is_primary.is_(True),
        )
        .first()
    )
    if loc:
        loc.address = body.address
    elif business.registration_id:
        reg = db.get(BusinessRegistration, business.registration_id)
        if reg:
            reg.proposed_address = body.address

    db.commit()
    return {"status": "ok"}
