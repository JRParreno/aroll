from typing import Annotated

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session

from app.core.deps import require_roles
from app.db.session import get_db
from app.models.attendance_policy import BusinessAttendancePolicy
from app.models.business import Business, BusinessLocation
from app.models.enums import UserRole
from app.models.payroll import BusinessPayrollConfig
from app.models.rest_day_policy import BusinessRestDayPolicy
from app.models.user import User
from app.schemas.business import LocationUpdate
from app.schemas.owner_setup import (
    AttendancePolicyResponse,
    AttendancePolicyUpdate,
    PayrollConfigResponse,
    PayrollConfigUpdate,
    RestDayPolicyResponse,
    RestDayPolicyUpdate,
    SetupStatusResponse,
)
from app.services.setup_status import complete_setup, get_setup_status

router = APIRouter(prefix="/businesses", tags=["businesses"])


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
    complete_setup(db, business)
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
    return {"status": "ok"}


@router.get("/me/attendance-policy", response_model=AttendancePolicyResponse)
def get_attendance_policy(
    db: Annotated[Session, Depends(get_db)],
    user: Annotated[User, Depends(require_roles(UserRole.owner, UserRole.manager))],
):
    if user.business_id is None:
        raise HTTPException(400, "No business context")
    policy = db.get(BusinessAttendancePolicy, user.business_id)
    if policy is None:
        policy = BusinessAttendancePolicy(business_id=user.business_id)
        db.add(policy)
        db.commit()
        db.refresh(policy)
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
    for field, value in body.model_dump().items():
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
    if policy is None:
        policy = BusinessRestDayPolicy(business_id=user.business_id)
        db.add(policy)
        db.commit()
        db.refresh(policy)
    return RestDayPolicyResponse(
        weekly_rest_day=policy.weekly_rest_day.value,
        work_on_rest_day_allowed=policy.work_on_rest_day_allowed,
        rest_day_premium_percent=float(policy.rest_day_premium_percent),
        use_custom_premium=policy.use_custom_premium,
        custom_premium_percent=float(policy.custom_premium_percent)
        if policy.custom_premium_percent is not None
        else None,
    )


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
