"""Block payroll finalization when incomplete attendance remains in the period."""

from __future__ import annotations

import uuid
from datetime import date, datetime, timedelta

from sqlalchemy import and_, or_
from sqlalchemy.orm import Session

from app.core.timezone import business_now, business_today
from app.models.attendance import AttendanceRecord
from app.models.attendance_policy import BusinessAttendancePolicy
from app.models.employee import Employee
from app.models.enums import AttendanceStatus
from app.models.scheduling import Shift, ShiftAssignment
from app.services.missing_clock_out import ensure_incomplete_for_business
from app.services.payroll_engine import collect_unresolved_scheduled_assignments


def count_incomplete_attendance_in_period(
    db: Session,
    *,
    business_id: uuid.UUID,
    period_start: date,
    period_end: date,
    business_timezone: str | None = None,
) -> int:
    """Count incomplete attendance rows overlapping the pay period."""
    ensure_incomplete_for_business(
        db,
        business_id=business_id,
        business_timezone=business_timezone,
    )
    return (
        db.query(AttendanceRecord)
        .outerjoin(
            ShiftAssignment,
            AttendanceRecord.shift_assignment_id == ShiftAssignment.id,
        )
        .filter(
            AttendanceRecord.business_id == business_id,
            AttendanceRecord.status == AttendanceStatus.incomplete,
            or_(
                and_(
                    ShiftAssignment.id.is_not(None),
                    ShiftAssignment.work_date >= period_start,
                    ShiftAssignment.work_date <= period_end,
                ),
                and_(
                    AttendanceRecord.shift_assignment_id.is_(None),
                    AttendanceRecord.created_at >= period_start,
                    AttendanceRecord.created_at
                    < period_end + timedelta(days=1),
                ),
            ),
        )
        .count()
    )


def count_unresolved_historical_rate_in_period(
    db: Session,
    *,
    business_id: uuid.UUID,
    period_start: date,
    period_end: date,
    business_timezone: str | None = None,
) -> int:
    """Count closed attendances that cannot be safely priced historically.

    Includes:
    - closed rows with no completion-rate stamp
    - completed Daily rows on a work_date where Daily stamps conflict
    """
    from app.models.enums import PayBasis
    from app.services.employee_pay import (
        attendance_requires_historical_rate,
        find_conflicting_daily_work_dates,
        load_daily_workday_entitlements_for_business,
        _stamp_pay_basis,
    )

    ensure_incomplete_for_business(
        db,
        business_id=business_id,
        business_timezone=business_timezone,
    )
    joined = (
        db.query(AttendanceRecord, ShiftAssignment, Shift)
        .outerjoin(
            ShiftAssignment,
            AttendanceRecord.shift_assignment_id == ShiftAssignment.id,
        )
        .outerjoin(Shift, ShiftAssignment.shift_id == Shift.id)
        .filter(
            AttendanceRecord.business_id == business_id,
            AttendanceRecord.time_in.is_not(None),
            AttendanceRecord.time_out.is_not(None),
            AttendanceRecord.status.notin_(
                (
                    AttendanceStatus.in_progress,
                    AttendanceStatus.incomplete,
                )
            ),
            or_(
                and_(
                    ShiftAssignment.id.is_not(None),
                    ShiftAssignment.work_date >= period_start,
                    ShiftAssignment.work_date <= period_end,
                ),
                and_(
                    AttendanceRecord.shift_assignment_id.is_(None),
                    AttendanceRecord.created_at >= period_start,
                    AttendanceRecord.created_at
                    < period_end + timedelta(days=1),
                ),
            ),
        )
        .all()
    )
    entitlements = load_daily_workday_entitlements_for_business(
        db,
        business_id=business_id,
        period_start=period_start,
        period_end=period_end,
    )
    conflict_dates_by_employee: dict = {}
    # Group rows by employee for conflict detection.
    by_employee: dict = {}
    for record, assignment, shift in joined:
        by_employee.setdefault(record.employee_id, []).append(
            (record, assignment, shift)
        )
    for employee_id, emp_rows in by_employee.items():
        conflict_dates_by_employee[employee_id] = find_conflicting_daily_work_dates(
            emp_rows
        )

    count = 0
    for record, assignment, _shift in joined:
        if attendance_requires_historical_rate(record):
            count += 1
            continue
        work_date = assignment.work_date if assignment is not None else None
        if work_date is None:
            continue
        if (
            work_date in conflict_dates_by_employee.get(record.employee_id, set())
            and _stamp_pay_basis(record) == PayBasis.daily
            and (record.employee_id, work_date) not in entitlements
        ):
            count += 1
    return count


def count_unresolved_scheduled_assignments_in_period(
    db: Session,
    *,
    business_id: uuid.UUID,
    period_start: date,
    period_end: date,
    business_timezone: str | None = None,
    now_local: datetime | None = None,
    today: date | None = None,
) -> int:
    """Count scheduled assignments still unresolved in the pay period.

    Uses the same `is_scheduled_assignment_resolved` rules as live payroll.
    Future work dates with no attendance are not counted.
    """
    ensure_incomplete_for_business(
        db,
        business_id=business_id,
        business_timezone=business_timezone,
    )
    today = today or business_today(business_timezone)
    now = now_local or business_now(business_timezone)
    now = now.replace(tzinfo=None) if now.tzinfo else now

    policy = db.get(BusinessAttendancePolicy, business_id)
    grace_minutes = 10.0
    if policy is not None:
        grace_minutes = float(getattr(policy, "on_time_grace_minutes", 10) or 0)

    scheduled = (
        db.query(ShiftAssignment, Shift)
        .join(Shift, ShiftAssignment.shift_id == Shift.id)
        .join(Employee, ShiftAssignment.employee_id == Employee.id)
        .filter(
            Employee.business_id == business_id,
            Employee.is_active.is_(True),
            ShiftAssignment.work_date >= period_start,
            ShiftAssignment.work_date <= period_end,
        )
        .all()
    )
    if not scheduled:
        return 0

    assignment_ids = [assignment.id for assignment, _shift in scheduled]
    records = (
        db.query(AttendanceRecord)
        .filter(
            AttendanceRecord.business_id == business_id,
            AttendanceRecord.shift_assignment_id.in_(assignment_ids),
        )
        .all()
    )
    records_by_assignment_id: dict = {}
    for record in records:
        records_by_assignment_id.setdefault(
            record.shift_assignment_id, []
        ).append(record)

    _pending_dates, unresolved_ids = collect_unresolved_scheduled_assignments(
        scheduled,
        records_by_assignment_id,
        now_local=now,
        today=today,
        grace_minutes=grace_minutes,
    )
    return len(unresolved_ids)
