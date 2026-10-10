"""Employee and owner APIs for attendance correction requests."""

from __future__ import annotations

import uuid
from typing import Annotated

from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy.orm import Session

from app.core.deps import get_current_user, require_roles
from app.db.session import get_db
from app.models.business import Business
from app.models.employee import Employee
from app.models.enums import AttendanceCorrectionStatus, EmployeeStatus, UserRole
from app.models.user import User
from app.schemas.attendance_correction import (
    AttendanceCorrectionCreateRequest,
    AttendanceCorrectionRejectRequest,
    AttendanceCorrectionResponse,
    OwnerCompleteAttendanceRequest,
    OwnerResolveDailyWorkdayRequest,
    OwnerResolveHistoricalRateRequest,
)
from app.services.attendance_correction import (
    approve_correction,
    create_correction_request,
    list_employee_corrections,
    list_owner_corrections,
    reject_correction,
)
from app.services.employee_pay import (
    apply_owner_completion_pay,
    apply_owner_daily_workday_rate,
    attendance_has_completion_pay,
    attendance_requires_historical_rate,
    find_conflicting_daily_work_dates,
)
from app.services.missing_clock_out import complete_incomplete_attendance

employee_router = APIRouter(prefix="/employee", tags=["employee-mobile"])
owner_router = APIRouter(prefix="/owner", tags=["owner-attendance-corrections"])


def _current_employee(db: Session, user: User) -> tuple[Employee, Business]:
    if user.role != UserRole.employee:
        raise HTTPException(403, "Only employees can access this endpoint")
    if user.business_id is None:
        raise HTTPException(400, "No business context")
    employee = (
        db.query(Employee)
        .filter(
            Employee.user_id == user.id,
            Employee.business_id == user.business_id,
        )
        .first()
    )
    if employee is None:
        raise HTTPException(404, "Employee not found")
    if employee.status == EmployeeStatus.inactive or not employee.is_active:
        raise HTTPException(403, "Employee account is inactive")
    business = db.get(Business, user.business_id)
    if business is None:
        raise HTTPException(404, "Business not found")
    return employee, business


@employee_router.post(
    "/attendance-corrections",
    response_model=AttendanceCorrectionResponse,
    status_code=201,
)
def employee_create_attendance_correction(
    body: AttendanceCorrectionCreateRequest,
    db: Annotated[Session, Depends(get_db)],
    user: Annotated[User, Depends(get_current_user)],
):
    employee, business = _current_employee(db, user)
    return create_correction_request(
        db,
        employee=employee,
        business=business,
        shift_assignment_id=body.shift_assignment_id,
        requested_time_in=body.requested_time_in,
        requested_time_out=body.requested_time_out,
        reason=body.reason,
    )


@employee_router.get(
    "/attendance-corrections",
    response_model=list[AttendanceCorrectionResponse],
)
def employee_list_attendance_corrections(
    db: Annotated[Session, Depends(get_db)],
    user: Annotated[User, Depends(get_current_user)],
):
    employee, _business = _current_employee(db, user)
    return list_employee_corrections(db, employee=employee)


@owner_router.get(
    "/attendance-corrections",
    response_model=list[AttendanceCorrectionResponse],
)
def owner_list_attendance_corrections(
    db: Annotated[Session, Depends(get_db)],
    user: Annotated[User, Depends(require_roles(UserRole.owner, UserRole.manager))],
    status: Annotated[str | None, Query()] = "pending",
):
    if user.business_id is None:
        raise HTTPException(400, "No business context")
    status_filter: AttendanceCorrectionStatus | None
    if status in (None, "", "all"):
        status_filter = None
    else:
        try:
            status_filter = AttendanceCorrectionStatus(status)
        except ValueError as exc:
            raise HTTPException(400, "Invalid status filter.") from exc
    return list_owner_corrections(
        db,
        business_id=user.business_id,
        status=status_filter,
    )


@owner_router.post(
    "/attendance-corrections/{request_id}/approve",
    response_model=AttendanceCorrectionResponse,
)
def owner_approve_attendance_correction(
    request_id: uuid.UUID,
    db: Annotated[Session, Depends(get_db)],
    user: Annotated[User, Depends(require_roles(UserRole.owner, UserRole.manager))],
):
    if user.business_id is None:
        raise HTTPException(400, "No business context")
    business = db.get(Business, user.business_id)
    if business is None:
        raise HTTPException(404, "Business not found")
    return approve_correction(
        db,
        request_id=request_id,
        reviewer=user,
        business=business,
    )


@owner_router.post(
    "/attendance-corrections/{request_id}/reject",
    response_model=AttendanceCorrectionResponse,
)
def owner_reject_attendance_correction(
    request_id: uuid.UUID,
    body: AttendanceCorrectionRejectRequest,
    db: Annotated[Session, Depends(get_db)],
    user: Annotated[User, Depends(require_roles(UserRole.owner, UserRole.manager))],
):
    if user.business_id is None:
        raise HTTPException(400, "No business context")
    return reject_correction(
        db,
        request_id=request_id,
        reviewer=user,
        business_id=user.business_id,
        review_note=body.review_note,
    )


@owner_router.post("/attendance-records/{record_id}/complete")
def owner_complete_attendance(
    record_id: uuid.UUID,
    body: OwnerCompleteAttendanceRequest,
    db: Annotated[Session, Depends(get_db)],
    user: Annotated[User, Depends(require_roles(UserRole.owner, UserRole.manager))],
):
    """Manually complete an Incomplete Attendance record with a clock-out time."""
    if user.business_id is None:
        raise HTTPException(400, "No business context")
    business = db.get(Business, user.business_id)
    if business is None:
        raise HTTPException(404, "Business not found")
    record = complete_incomplete_attendance(
        db,
        record_id=record_id,
        reviewer=user,
        business=business,
        time_out=body.time_out,
        reason=body.reason,
    )
    return {
        "id": str(record.id),
        "employee_id": str(record.employee_id),
        "status": record.status.value,
        "time_in": record.time_in.isoformat() if record.time_in else None,
        "time_out": record.time_out.isoformat() if record.time_out else None,
        "ot_approval_status": (
            record.ot_approval_status.value
            if getattr(record, "ot_approval_status", None) is not None
            else None
        ),
    }


@owner_router.post("/attendance-records/{record_id}/historical-rate")
def owner_resolve_historical_rate(
    record_id: uuid.UUID,
    body: OwnerResolveHistoricalRateRequest,
    db: Annotated[Session, Depends(get_db)],
    user: Annotated[User, Depends(require_roles(UserRole.owner, UserRole.manager))],
):
    """Owner sets the historical completion rate for a legacy NULL-stamp close.

    Does not copy current Employee or Position rates. Only the supplied values
    are stamped. Existing stamps are never overwritten.
    """
    from app.models.attendance import AttendanceRecord

    if user.business_id is None:
        raise HTTPException(400, "No business context")
    record = (
        db.query(AttendanceRecord)
        .filter(
            AttendanceRecord.id == record_id,
            AttendanceRecord.business_id == user.business_id,
        )
        .first()
    )
    if record is None:
        raise HTTPException(404, "Attendance record not found")
    if not attendance_requires_historical_rate(record):
        if attendance_has_completion_pay(record):
            raise HTTPException(
                400,
                "This attendance already has a historical completion rate.",
            )
        raise HTTPException(
            400,
            "Only a completed attendance with a missing historical rate "
            "can be resolved.",
        )
    try:
        apply_owner_completion_pay(
            record,
            pay_basis=body.pay_basis,
            daily_rate=body.daily_rate,
            hourly_rate=body.hourly_rate,
            monthly_salary=body.monthly_salary,
        )
    except ValueError as exc:
        raise HTTPException(400, str(exc)) from exc
    db.add(record)
    db.commit()
    db.refresh(record)
    return {
        "id": str(record.id),
        "employee_id": str(record.employee_id),
        "status": record.status.value,
        "pay_basis_at_completion": (
            record.pay_basis_at_completion.value
            if record.pay_basis_at_completion is not None
            else None
        ),
        "daily_rate_at_completion": (
            float(record.daily_rate_at_completion)
            if record.daily_rate_at_completion is not None
            else None
        ),
        "hourly_rate_at_completion": (
            float(record.hourly_rate_at_completion)
            if record.hourly_rate_at_completion is not None
            else None
        ),
        "monthly_salary_at_completion": (
            float(record.monthly_salary_at_completion)
            if record.monthly_salary_at_completion is not None
            else None
        ),
        "historical_rate_required": False,
    }


@owner_router.post("/daily-workday-historical-rate")
def owner_resolve_daily_workday_rate(
    body: OwnerResolveDailyWorkdayRequest,
    db: Annotated[Session, Depends(get_db)],
    user: Annotated[User, Depends(require_roles(UserRole.owner, UserRole.manager))],
):
    """Owner picks one Daily rate for a work_date with conflicting Daily stamps.

    Persists a separate Daily workday entitlement. Does NOT overwrite any
    AttendanceRecord ``*_at_completion`` historical stamps. Hourly stamps on
    the same date are unchanged.
    """
    from app.models.attendance import AttendanceRecord
    from app.models.scheduling import Shift, ShiftAssignment
    from app.services.payroll_snapshot import find_snapshot_run

    if user.business_id is None:
        raise HTTPException(400, "No business context")
    employee = (
        db.query(Employee)
        .filter(
            Employee.id == body.employee_id,
            Employee.business_id == user.business_id,
        )
        .first()
    )
    if employee is None:
        raise HTTPException(404, "Employee not found")

    existing_run = find_snapshot_run(
        db,
        business_id=user.business_id,
        as_of=body.work_date,
    )
    if existing_run is not None:
        raise HTTPException(
            400,
            "Cannot change historical rates for a finalized payroll period.",
        )

    rows = (
        db.query(AttendanceRecord, ShiftAssignment, Shift)
        .outerjoin(
            ShiftAssignment,
            AttendanceRecord.shift_assignment_id == ShiftAssignment.id,
        )
        .outerjoin(Shift, ShiftAssignment.shift_id == Shift.id)
        .filter(
            AttendanceRecord.business_id == user.business_id,
            AttendanceRecord.employee_id == employee.id,
            ShiftAssignment.work_date == body.work_date,
        )
        .all()
    )
    conflicts = find_conflicting_daily_work_dates(rows)
    if body.work_date not in conflicts:
        raise HTTPException(
            400,
            "This work date does not have a conflicting Daily historical rate.",
        )

    try:
        entitlement = apply_owner_daily_workday_rate(
            db,
            business_id=user.business_id,
            employee_id=employee.id,
            work_date=body.work_date,
            daily_rate=body.daily_rate,
            resolved_by=user.id,
        )
    except ValueError as exc:
        raise HTTPException(400, str(exc)) from exc
    db.commit()
    return {
        "employee_id": str(employee.id),
        "work_date": body.work_date.isoformat(),
        "daily_rate": float(entitlement),
        "historical_rate_required": False,
        "stamps_unchanged": True,
    }


@owner_router.get("/overtime-approvals")
def list_overtime_approvals(
    db: Annotated[Session, Depends(get_db)],
    user: Annotated[User, Depends(require_roles(UserRole.owner, UserRole.manager))],
    status: Annotated[
        str | None,
        Query(description="pending | approved | rejected"),
    ] = "pending",
):
    """List attendance punches with OT approval status for the business."""
    from app.models.attendance import AttendanceRecord
    from app.models.enums import OvertimeApprovalStatus
    from app.models.scheduling import Shift, ShiftAssignment

    if user.business_id is None:
        raise HTTPException(400, "No business context")
    query = (
        db.query(AttendanceRecord, Employee, ShiftAssignment, Shift)
        .join(Employee, AttendanceRecord.employee_id == Employee.id)
        .outerjoin(
            ShiftAssignment,
            AttendanceRecord.shift_assignment_id == ShiftAssignment.id,
        )
        .outerjoin(Shift, ShiftAssignment.shift_id == Shift.id)
        .filter(
            AttendanceRecord.business_id == user.business_id,
            AttendanceRecord.ot_approval_status.is_not(None),
        )
    )
    if status:
        try:
            status_enum = OvertimeApprovalStatus(status)
        except ValueError as exc:
            raise HTTPException(400, "Invalid OT approval status") from exc
        query = query.filter(AttendanceRecord.ot_approval_status == status_enum)
    rows = query.order_by(AttendanceRecord.created_at.desc()).limit(200).all()
    items = []
    for record, employee, assignment, shift in rows:
        worked_ot = 0.0
        if assignment is not None and shift is not None:
            from app.models.attendance_policy import BusinessAttendancePolicy
            from app.models.business import Business
            from app.models.payroll import BusinessPayrollConfig
            from app.services.ot_approval import compute_qualifying_ot_for_record

            payroll_config = db.get(BusinessPayrollConfig, user.business_id)
            att_policy = db.get(BusinessAttendancePolicy, user.business_id)
            business = db.get(Business, user.business_id)
            tz_name = (
                business.timezone
                if business is not None and getattr(business, "timezone", None)
                else "Asia/Manila"
            )
            worked_ot, _recovered = compute_qualifying_ot_for_record(
                record=record,
                assignment=assignment,
                shift=shift,
                att_policy=att_policy,
                payroll_config=payroll_config,
                business_timezone=tz_name,
            )
        items.append(
            {
                "attendance_record_id": str(record.id),
                "employee_id": str(employee.id),
                "employee_name": employee.full_name,
                "work_date": (
                    assignment.work_date.isoformat() if assignment else None
                ),
                "shift_name": shift.name if shift else None,
                "time_in": record.time_in.isoformat() if record.time_in else None,
                "time_out": record.time_out.isoformat() if record.time_out else None,
                "worked_ot_minutes": round(worked_ot, 2),
                "ot_approval_status": (
                    record.ot_approval_status.value
                    if record.ot_approval_status
                    else None
                ),
                "ot_reviewed_at": (
                    record.ot_reviewed_at.isoformat()
                    if record.ot_reviewed_at
                    else None
                ),
            }
        )
    return {"items": items}


@owner_router.post("/attendance-records/{record_id}/overtime/approve")
def owner_approve_overtime(
    record_id: uuid.UUID,
    db: Annotated[Session, Depends(get_db)],
    user: Annotated[User, Depends(require_roles(UserRole.owner, UserRole.manager))],
):
    from app.models.attendance import AttendanceRecord
    from app.services.ot_approval import review_ot_approval

    if user.business_id is None:
        raise HTTPException(400, "No business context")
    record = (
        db.query(AttendanceRecord)
        .filter(
            AttendanceRecord.id == record_id,
            AttendanceRecord.business_id == user.business_id,
        )
        .first()
    )
    if record is None:
        raise HTTPException(404, "Attendance record not found")
    record = review_ot_approval(db, record, reviewer_id=user.id, approve=True)
    return {
        "id": str(record.id),
        "ot_approval_status": record.ot_approval_status.value,
        "ot_reviewed_at": (
            record.ot_reviewed_at.isoformat() if record.ot_reviewed_at else None
        ),
    }


@owner_router.post("/attendance-records/{record_id}/overtime/reject")
def owner_reject_overtime(
    record_id: uuid.UUID,
    db: Annotated[Session, Depends(get_db)],
    user: Annotated[User, Depends(require_roles(UserRole.owner, UserRole.manager))],
):
    from app.models.attendance import AttendanceRecord
    from app.services.ot_approval import review_ot_approval

    if user.business_id is None:
        raise HTTPException(400, "No business context")
    record = (
        db.query(AttendanceRecord)
        .filter(
            AttendanceRecord.id == record_id,
            AttendanceRecord.business_id == user.business_id,
        )
        .first()
    )
    if record is None:
        raise HTTPException(404, "Attendance record not found")
    record = review_ot_approval(db, record, reviewer_id=user.id, approve=False)
    return {
        "id": str(record.id),
        "ot_approval_status": record.ot_approval_status.value,
        "ot_reviewed_at": (
            record.ot_reviewed_at.isoformat() if record.ot_reviewed_at else None
        ),
    }
