"""Overtime approval: worked OT vs payable OT.

Does not alter attendance punches. When
BusinessPayrollConfig.overtime_approval_required is false, payroll pays
qualifying OT automatically (existing behavior). When true, qualifying OT
is stored as pending/approved/rejected on AttendanceRecord and only approved
OT contributes to overtime_pay.
"""

from __future__ import annotations

from datetime import date, datetime, time, timezone
from typing import Any
from uuid import UUID

from fastapi import HTTPException
from sqlalchemy.orm import Session

from app.models.attendance import AttendanceRecord
from app.models.attendance_policy import BusinessAttendancePolicy
from app.models.enums import OvertimeApprovalStatus
from app.models.payroll import BusinessPayrollConfig
from app.models.scheduling import Shift, ShiftAssignment
from app.services.payroll_engine import (
    qualifying_overtime_minutes,
    scheduled_shift_end_at,
)


def overtime_approval_required(config: BusinessPayrollConfig | None) -> bool:
    if config is None:
        return False
    return bool(getattr(config, "overtime_approval_required", False))


def payable_ot_minutes(
    *,
    worked_ot_minutes: float,
    approval_required: bool,
    ot_approval_status: OvertimeApprovalStatus | str | None,
) -> float:
    """Gate qualifying OT minutes into payable minutes."""
    worked = max(float(worked_ot_minutes or 0.0), 0.0)
    if worked <= 0:
        return 0.0
    if not approval_required:
        return worked
    status = ot_approval_status
    if hasattr(status, "value"):
        status = status.value  # type: ignore[union-attr]
    if status == OvertimeApprovalStatus.approved.value:
        return worked
    return 0.0


def _to_business_naive(dt: datetime, tz_name: str) -> datetime:
    from zoneinfo import ZoneInfo

    if dt.tzinfo is None:
        return dt
    return dt.astimezone(ZoneInfo(tz_name)).replace(tzinfo=None)


def _shift_start_at(work_date: date, shift: Shift) -> datetime:
    start: time = shift.start_time
    return datetime.combine(work_date, start)


def compute_qualifying_ot_for_record(
    *,
    record: AttendanceRecord,
    assignment: ShiftAssignment,
    shift: Shift,
    att_policy: BusinessAttendancePolicy | None,
    payroll_config: BusinessPayrollConfig | None,
    business_timezone: str = "Asia/Manila",
) -> tuple[float, float]:
    """Return (qualifying_ot_minutes, recovered_late_minutes)."""
    if record.time_in is None or record.time_out is None:
        return 0.0, 0.0
    scheduled_start = _shift_start_at(assignment.work_date, shift)
    scheduled_end = scheduled_shift_end_at(assignment.work_date, shift)
    time_in_local = _to_business_naive(record.time_in, business_timezone)
    time_out_local = _to_business_naive(record.time_out, business_timezone)
    ot_minimum = float(
        getattr(att_policy, "overtime_minimum_minutes", 30) if att_policy else 30
    )
    balancing = bool(
        getattr(payroll_config, "enable_late_overtime_balancing", False)
        if payroll_config
        else False
    )
    return qualifying_overtime_minutes(
        time_in=time_in_local,
        time_out=time_out_local,
        scheduled_start=scheduled_start,
        scheduled_end=scheduled_end,
        ot_minimum=ot_minimum,
        late_ot_balancing=balancing,
    )


def sync_ot_approval_after_close(
    db: Session,
    record: AttendanceRecord,
    *,
    assignment: ShiftAssignment | None,
    shift: Shift | None,
    business_timezone: str = "Asia/Manila",
    force_rereview: bool = False,
) -> None:
    """Set/clear ot_approval_status after a closed punch. Does not commit."""
    config = db.get(BusinessPayrollConfig, record.business_id)
    if not overtime_approval_required(config):
        record.ot_approval_status = None
        record.ot_reviewed_by = None
        record.ot_reviewed_at = None
        return
    if (
        assignment is None
        or shift is None
        or record.time_in is None
        or record.time_out is None
    ):
        record.ot_approval_status = None
        record.ot_reviewed_by = None
        record.ot_reviewed_at = None
        return
    if config is not None and not bool(getattr(config, "overtime_enabled", True)):
        record.ot_approval_status = None
        record.ot_reviewed_by = None
        record.ot_reviewed_at = None
        return
    att_policy = db.get(BusinessAttendancePolicy, record.business_id)
    if att_policy is not None and not bool(
        getattr(att_policy, "overtime_enabled", True)
    ):
        record.ot_approval_status = None
        record.ot_reviewed_by = None
        record.ot_reviewed_at = None
        return

    ot_mins, _recovered = compute_qualifying_ot_for_record(
        record=record,
        assignment=assignment,
        shift=shift,
        att_policy=att_policy,
        payroll_config=config,
        business_timezone=business_timezone,
    )
    if ot_mins <= 0:
        record.ot_approval_status = None
        record.ot_reviewed_by = None
        record.ot_reviewed_at = None
        return

    if (
        not force_rereview
        and record.ot_approval_status
        in (
            OvertimeApprovalStatus.approved,
            OvertimeApprovalStatus.rejected,
        )
    ):
        return
    record.ot_approval_status = OvertimeApprovalStatus.pending
    record.ot_reviewed_by = None
    record.ot_reviewed_at = None


def _raise_if_attendance_period_finalized(
    db: Session,
    record: AttendanceRecord,
) -> None:
    """Block OT approve/reject once the punch's pay period is finalized.

    Finalized snapshots stay immutable; Owners must unfinalize to change
    payable OT. Does not alter attendance Time In / Time Out.
    """
    from app.models.scheduling import ShiftAssignment
    from app.services.payroll_adjustments import raise_if_work_date_period_finalized

    assignment = None
    if record.shift_assignment_id is not None:
        assignment = db.get(ShiftAssignment, record.shift_assignment_id)
    work_date = assignment.work_date if assignment is not None else None
    if work_date is None and record.time_in is not None:
        # UTC date fallback only when assignment missing; prefer assignment.work_date.
        work_date = record.time_in.date()
    raise_if_work_date_period_finalized(
        db,
        business_id=record.business_id,
        work_date=work_date,
        message=(
            "This payroll period is already finalized. "
            "Overtime cannot be approved or rejected until payroll is unfinalized."
        ),
    )


def review_ot_approval(
    db: Session,
    record: AttendanceRecord,
    *,
    reviewer_id: UUID,
    approve: bool,
) -> AttendanceRecord:
    if record.ot_approval_status is None:
        raise HTTPException(
            400,
            detail={
                "code": "no_ot_approval",
                "message": "This attendance record has no overtime awaiting review.",
            },
        )
    _raise_if_attendance_period_finalized(db, record)
    record.ot_approval_status = (
        OvertimeApprovalStatus.approved if approve else OvertimeApprovalStatus.rejected
    )
    record.ot_reviewed_by = reviewer_id
    record.ot_reviewed_at = datetime.now(timezone.utc)
    db.add(record)
    db.commit()
    db.refresh(record)
    try:
        from app.services.activity_notifications import notify_overtime_reviewed

        notify_overtime_reviewed(db, record, approved=approve)
    except Exception:
        pass
    return record


def ot_detail_dict(
    *,
    scheduled_start: datetime | None,
    scheduled_end: datetime | None,
    time_in: datetime | None,
    time_out: datetime | None,
    worked_ot_minutes: float,
    recovered_late_minutes: float,
    payable_ot_minutes_value: float,
    ot_rate: float,
    holiday_ot_premium_percent: float,
    overtime_pay: float,
    ot_approval_status: str | None,
    approval_required: bool,
) -> dict[str, Any]:
    """Transparent OT breakdown for payslip attendance rows."""
    return {
        "scheduled_start": scheduled_start.isoformat() if scheduled_start else None,
        "scheduled_end": scheduled_end.isoformat() if scheduled_end else None,
        "time_in": time_in.isoformat() if time_in else None,
        "time_out": time_out.isoformat() if time_out else None,
        "worked_ot_minutes": round(float(worked_ot_minutes), 2),
        "time_recovered_minutes": round(float(recovered_late_minutes), 2),
        "payable_ot_minutes": round(float(payable_ot_minutes_value), 2),
        "ot_rate_per_minute": round(float(ot_rate), 2),
        "holiday_ot_premium_percent": round(float(holiday_ot_premium_percent), 2),
        "overtime_pay": round(float(overtime_pay), 2),
        "ot_approval_status": ot_approval_status,
        "ot_approval_required": bool(approval_required),
    }
