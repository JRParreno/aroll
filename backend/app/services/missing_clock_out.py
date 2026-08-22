"""Lazy detection of forgotten clock-outs (Incomplete Attendance).

No schedulers/cron. Callers invoke these helpers when attendance is read or
when an employee attempts to clock out after the maximum overtime window.

Incomplete deadline = scheduled shift end + maximum_overtime_minutes.
Late grace (on_time_grace_minutes) is not used here — it remains for late
clock-in status and for no-show timing in payroll/attendance reports.
"""

from __future__ import annotations

import uuid
from datetime import datetime, timedelta, timezone

from fastapi import HTTPException
from sqlalchemy.orm import Session

from app.core.timezone import business_now, get_business_tz
from app.models.attendance import AttendanceRecord
from app.models.attendance_policy import BusinessAttendancePolicy
from app.models.business import Business
from app.models.employee import Employee
from app.models.enums import AttendanceStatus
from app.models.scheduling import Shift, ShiftAssignment
from app.models.user import User
from app.services.attendance_correction import _recompute_status
from app.services.activity_logger import create_log

INCOMPLETE_CLOCK_OUT_MESSAGE = (
    "Your shift has already ended and your attendance has been marked as "
    "incomplete because you forgot to time out. Please submit an attendance "
    "correction request or contact your manager."
)

# Cap how far after scheduled end an owner-entered clock-out may be.
_MAX_HOURS_AFTER_SHIFT_END = 12
# Cap total worked span for manual completion (guards absurd values).
_MAX_WORKED_HOURS = 16


def _scheduled_end(work_date, shift: Shift) -> datetime:
    end_at = datetime.combine(work_date, shift.end_time)
    if shift.end_time <= shift.start_time:
        end_at += timedelta(days=1)
    return end_at


def _scheduled_start(work_date, shift: Shift) -> datetime:
    return datetime.combine(work_date, shift.start_time)


def _attendance_policy(db: Session, business_id: uuid.UUID) -> BusinessAttendancePolicy:
    policy = db.get(BusinessAttendancePolicy, business_id)
    if policy is None:
        return BusinessAttendancePolicy(business_id=business_id)
    return policy


def _to_business_naive(value: datetime, tz_name: str | None) -> datetime:
    tz = get_business_tz(tz_name)
    if value.tzinfo is None:
        return value
    return value.astimezone(tz).replace(tzinfo=None)


def is_past_clock_out_deadline(
    *,
    now_local: datetime,
    work_date,
    shift: Shift,
    grace_minutes: int,
) -> bool:
    """True when now is past scheduled end + the provided minute window.

    Callers choose the window:
    - Incomplete detection → maximum_overtime_minutes
    - No-show / absence timing → on_time_grace_minutes (unchanged)
    """
    deadline = _scheduled_end(work_date, shift) + timedelta(minutes=max(grace_minutes, 0))
    return now_local.replace(tzinfo=None) > deadline


def _incomplete_window_minutes(policy: BusinessAttendancePolicy) -> int:
    return max(int(getattr(policy, "maximum_overtime_minutes", 180) or 0), 0)


def _load_assignment_shift(
    db: Session, record: AttendanceRecord
) -> tuple[ShiftAssignment, Shift] | None:
    if record.shift_assignment_id is None:
        return None
    row = (
        db.query(ShiftAssignment, Shift)
        .join(Shift, ShiftAssignment.shift_id == Shift.id)
        .filter(ShiftAssignment.id == record.shift_assignment_id)
        .first()
    )
    return row


def mark_record_incomplete_if_needed(
    db: Session,
    record: AttendanceRecord,
    *,
    business_timezone: str | None,
    policy: BusinessAttendancePolicy | None = None,
    commit: bool = False,
) -> bool:
    """Mark a single open punch incomplete past shift end + max OT window.

    Returns True when the record was updated.
    """
    if record.time_out is not None:
        return False
    if record.time_in is None:
        return False
    if record.status == AttendanceStatus.incomplete:
        return False
    if record.status == AttendanceStatus.on_leave:
        return False
    if record.status not in (
        AttendanceStatus.in_progress,
        AttendanceStatus.late,
    ):
        return False

    bundle = _load_assignment_shift(db, record)
    if bundle is None:
        return False
    assignment, shift = bundle

    if policy is None:
        policy = _attendance_policy(db, record.business_id)

    now_local = business_now(business_timezone).replace(tzinfo=None)
    if not is_past_clock_out_deadline(
        now_local=now_local,
        work_date=assignment.work_date,
        shift=shift,
        grace_minutes=_incomplete_window_minutes(policy),
    ):
        return False

    record.status = AttendanceStatus.incomplete
    if commit:
        db.commit()
        db.refresh(record)
    return True


def ensure_incomplete_for_employee(
    db: Session,
    employee: Employee,
    *,
    business_timezone: str | None,
) -> int:
    """Lazy-mark all of an employee's open past-deadline punches incomplete."""
    policy = _attendance_policy(db, employee.business_id)
    rows = (
        db.query(AttendanceRecord)
        .filter(
            AttendanceRecord.business_id == employee.business_id,
            AttendanceRecord.employee_id == employee.id,
            AttendanceRecord.time_out.is_(None),
            AttendanceRecord.time_in.is_not(None),
            AttendanceRecord.status.in_(
                (AttendanceStatus.in_progress, AttendanceStatus.late)
            ),
        )
        .all()
    )
    changed_records: list[AttendanceRecord] = []
    for record in rows:
        if mark_record_incomplete_if_needed(
            db,
            record,
            business_timezone=business_timezone,
            policy=policy,
            commit=False,
        ):
            changed_records.append(record)
    if changed_records:
        db.commit()
        from app.services.incomplete_attendance_notify import (
            notify_incomplete_attendance,
        )

        for record in changed_records:
            db.refresh(record)
            notify_incomplete_attendance(db, record=record, employee=employee)
    return len(changed_records)


def ensure_incomplete_for_business(
    db: Session,
    *,
    business_id: uuid.UUID,
    business_timezone: str | None,
    employee_id: uuid.UUID | None = None,
) -> int:
    """Lazy-mark open past-deadline punches for a business (optional employee)."""
    policy = _attendance_policy(db, business_id)
    query = db.query(AttendanceRecord).filter(
        AttendanceRecord.business_id == business_id,
        AttendanceRecord.time_out.is_(None),
        AttendanceRecord.time_in.is_not(None),
        AttendanceRecord.status.in_(
            (AttendanceStatus.in_progress, AttendanceStatus.late)
        ),
    )
    if employee_id is not None:
        query = query.filter(AttendanceRecord.employee_id == employee_id)
    rows = query.limit(1000).all()
    changed_records: list[AttendanceRecord] = []
    for record in rows:
        if mark_record_incomplete_if_needed(
            db,
            record,
            business_timezone=business_timezone,
            policy=policy,
            commit=False,
        ):
            changed_records.append(record)
    if changed_records:
        db.commit()
        from app.services.incomplete_attendance_notify import (
            notify_incomplete_attendance,
        )

        for record in changed_records:
            db.refresh(record)
            notify_incomplete_attendance(db, record=record)
    return len(changed_records)


def raise_if_incomplete_clock_out(
    db: Session,
    record: AttendanceRecord,
    *,
    business_timezone: str | None,
) -> None:
    """Block clock-out once the maximum overtime window has ended."""
    if record.time_out is not None:
        return

    policy = _attendance_policy(db, record.business_id)
    if record.status == AttendanceStatus.incomplete:
        raise HTTPException(
            status_code=400,
            detail={
                "code": "incomplete_attendance",
                "message": INCOMPLETE_CLOCK_OUT_MESSAGE,
            },
        )

    bundle = _load_assignment_shift(db, record)
    if bundle is None:
        return
    assignment, shift = bundle
    now_local = business_now(business_timezone).replace(tzinfo=None)
    if not is_past_clock_out_deadline(
        now_local=now_local,
        work_date=assignment.work_date,
        shift=shift,
        grace_minutes=_incomplete_window_minutes(policy),
    ):
        return

    record.status = AttendanceStatus.incomplete
    db.commit()
    db.refresh(record)
    try:
        from app.services.incomplete_attendance_notify import (
            notify_incomplete_attendance,
        )

        notify_incomplete_attendance(db, record=record)
    except Exception:
        pass
    raise HTTPException(
        status_code=400,
        detail={
            "code": "incomplete_attendance",
            "message": INCOMPLETE_CLOCK_OUT_MESSAGE,
        },
    )


def list_incomplete_for_employee(
    db: Session,
    employee: Employee,
) -> list[AttendanceRecord]:
    return (
        db.query(AttendanceRecord)
        .filter(
            AttendanceRecord.business_id == employee.business_id,
            AttendanceRecord.employee_id == employee.id,
            AttendanceRecord.status == AttendanceStatus.incomplete,
            AttendanceRecord.time_out.is_(None),
        )
        .order_by(AttendanceRecord.created_at.desc())
        .all()
    )


def validate_manual_clock_out(
    *,
    time_in: datetime,
    time_out: datetime,
    assignment: ShiftAssignment,
    shift: Shift,
    business_timezone: str | None,
) -> None:
    if time_out <= time_in:
        raise HTTPException(400, "Clock-out time must be after the recorded clock-in.")

    now_utc = datetime.now(timezone.utc)
    out_utc = time_out if time_out.tzinfo else time_out.replace(tzinfo=timezone.utc)
    if out_utc > now_utc + timedelta(minutes=5):
        raise HTTPException(400, "Clock-out time cannot be in the future.")

    time_in_local = _to_business_naive(time_in, business_timezone)
    time_out_local = _to_business_naive(time_out, business_timezone)
    scheduled_end = _scheduled_end(assignment.work_date, shift)
    max_out = max(
        scheduled_end + timedelta(hours=_MAX_HOURS_AFTER_SHIFT_END),
        time_in_local + timedelta(hours=_MAX_WORKED_HOURS),
    )
    if time_out_local > max_out:
        raise HTTPException(
            400,
            "Clock-out time is outside a reasonable range for this shift. "
            "Please enter a time closer to the scheduled shift end.",
        )
    if time_out_local < time_in_local:
        raise HTTPException(400, "Clock-out time must be after the recorded clock-in.")


def complete_incomplete_attendance(
    db: Session,
    *,
    record_id: uuid.UUID,
    reviewer: User,
    business: Business,
    time_out: datetime,
    reason: str | None = None,
) -> AttendanceRecord:
    """Owner/manager completes an incomplete attendance with a manual clock-out."""
    record = (
        db.query(AttendanceRecord)
        .filter(
            AttendanceRecord.id == record_id,
            AttendanceRecord.business_id == business.id,
        )
        .first()
    )
    if record is None:
        raise HTTPException(404, "Attendance record not found.")
    if record.status != AttendanceStatus.incomplete:
        raise HTTPException(
            400,
            "Complete Attendance is only available for Incomplete Attendance records.",
        )
    if record.time_in is None:
        raise HTTPException(400, "Attendance record is missing a clock-in time.")

    bundle = _load_assignment_shift(db, record)
    if bundle is None:
        raise HTTPException(400, "Attendance record is not linked to a shift.")
    assignment, shift = bundle
    policy = _attendance_policy(db, business.id)

    validate_manual_clock_out(
        time_in=record.time_in,
        time_out=time_out,
        assignment=assignment,
        shift=shift,
        business_timezone=business.timezone,
    )

    original_status = record.status.value
    original_time_out = (
        record.time_out.isoformat() if record.time_out is not None else None
    )

    status = _recompute_status(
        time_in=record.time_in,
        time_out=time_out,
        assignment=assignment,
        shift=shift,
        policy=policy,
        business_timezone=business.timezone,
    )
    record.time_out = time_out
    record.status = status
    db.flush()

    employee = db.get(Employee, record.employee_id)
    employee_name = employee.full_name if employee else str(record.employee_id)
    reason_part = f" Reason: {reason.strip()}." if reason and reason.strip() else ""
    description = (
        f"Owner completed incomplete attendance for {employee_name}. "
        f"Previous status={original_status}, previous time_out={original_time_out}, "
        f"new time_out={time_out.isoformat()}, new status={status.value}.{reason_part}"
    )
    if len(description) > 500:
        description = description[:497] + "..."

    # Persist attendance first, then audit (create_log commits).
    db.commit()
    db.refresh(record)
    create_log(
        db,
        user_id=reviewer.id,
        action="attendance_completed_by_owner",
        description=description,
    )
    return record
