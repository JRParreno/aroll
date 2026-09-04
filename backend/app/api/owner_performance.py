from collections import defaultdict
from datetime import date, datetime, time, timedelta
from typing import Annotated

from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy.orm import Session

from app.core.deps import require_roles
from app.core.timezone import business_now, business_today, to_business_naive
from app.db.session import get_db
from app.models.attendance import AttendanceRecord
from app.models.attendance_policy import BusinessAttendancePolicy
from app.models.employee import Employee
from app.models.enums import AttendanceStatus, EmployeeStatus, UserRole
from app.models.scheduling import Shift, ShiftAssignment
from app.models.user import User
from app.models.business import Business
from app.schemas.owner_performance import (
    EmployeePerformanceItem,
    OwnerPerformanceResponse,
    OwnerPerformanceSummary,
    OwnerPerformanceTrendItem,
)
from app.services.missing_clock_out import ensure_incomplete_for_business

router = APIRouter(prefix="/owner/performance", tags=["owner-performance"])


def _percent(numerator: int | float, denominator: int | float) -> float:
    if denominator <= 0:
        return 0.0
    return round((numerator / denominator) * 100, 1)


def _combine(work_date: date, value: time) -> datetime:
    return datetime.combine(work_date, value)


def _shift_end_at(work_date: date, shift: Shift) -> datetime:
    end_at = _combine(work_date, shift.end_time)
    if shift.end_time <= shift.start_time:
        end_at += timedelta(days=1)
    return end_at


def _unpunched_noshow_due(
    *,
    now_local: datetime,
    work_date: date,
    shift: Shift,
    cutoff_minutes: int,
) -> bool:
    """True when an unpunched shift should count as a no-show Absent.

    Payroll Absent Cutoff (``absent_threshold_minutes``) is minutes after
    scheduled start. This is separate from worked-minutes absent, which only
    applies after a Time In exists.
    """
    scheduled_start = _combine(work_date, shift.start_time)
    deadline = scheduled_start + timedelta(minutes=max(int(cutoff_minutes), 0))
    return now_local.replace(tzinfo=None) > deadline


@router.get("", response_model=OwnerPerformanceResponse)
def get_owner_performance(
    db: Annotated[Session, Depends(get_db)],
    user: Annotated[User, Depends(require_roles(UserRole.owner, UserRole.manager))],
    days: Annotated[int, Query(ge=1, le=366)] = 30,
    year: Annotated[int | None, Query(ge=2000, le=2100)] = None,
    month: Annotated[int | None, Query(ge=1, le=12)] = None,
):
    """Owner attendance performance analytics.

    Prefer ``year`` + ``month`` for a calendar-month window.
    When omitted, fall back to a rolling ``days`` window (Owner Dashboard default).
    """
    if user.business_id is None:
        raise HTTPException(400, "No business context")

    business = db.get(Business, user.business_id)
    tz_name = getattr(business, "timezone", None) if business is not None else None
    ensure_incomplete_for_business(
        db,
        business_id=user.business_id,
        business_timezone=tz_name,
    )

    today = business_today(tz_name)
    if year is not None and month is not None:
        start_date = date(year, month, 1)
        if month == 12:
            month_end = date(year + 1, 1, 1) - timedelta(days=1)
        else:
            month_end = date(year, month + 1, 1) - timedelta(days=1)
        end_date = min(month_end, today)
        if start_date > today:
            # Future period — return empty analytics.
            end_date = start_date - timedelta(days=1)
    else:
        start_date = today - timedelta(days=days - 1)
        end_date = today

    policy = db.get(BusinessAttendancePolicy, user.business_id)
    grace_minutes = policy.on_time_grace_minutes if policy else 10
    overtime_minimum = policy.overtime_minimum_minutes if policy else 30
    raw_absent_cutoff = (
        getattr(policy, "absent_threshold_minutes", None) if policy is not None else None
    )
    # Model default when unset — never a chart-specific hardcoded cutoff.
    absent_cutoff_minutes = (
        int(raw_absent_cutoff) if raw_absent_cutoff is not None else 240
    )
    now_local = business_now(tz_name).replace(tzinfo=None)

    employees = (
        db.query(Employee)
        .filter(
            Employee.business_id == user.business_id,
            Employee.status != EmployeeStatus.inactive,
        )
        .order_by(Employee.full_name)
        .all()
    )

    if start_date > end_date:
        return OwnerPerformanceResponse(
            summary=OwnerPerformanceSummary(
                has_performance_data=False,
                assigned_shifts=0,
                attended_shifts=0,
                completed_shifts=0,
                on_time_clock_ins=0,
                late_clock_ins=0,
                absent_shifts=0,
                undertime_shifts=0,
                overtime_shifts=0,
                attendance_rate=0.0,
                punctuality_rate=0.0,
                total_overtime_hours=0.0,
            ),
            trend=[],
            employees=[],
        )

    assignments = (
        db.query(ShiftAssignment, Shift)
        .join(Shift, ShiftAssignment.shift_id == Shift.id)
        .filter(
            Shift.business_id == user.business_id,
            ShiftAssignment.work_date >= start_date,
            ShiftAssignment.work_date <= end_date,
        )
        .all()
    )

    assignment_ids = [assignment.id for assignment, _shift in assignments]
    attendance_rows = (
        db.query(AttendanceRecord)
        .filter(
            AttendanceRecord.business_id == user.business_id,
            AttendanceRecord.shift_assignment_id.in_(assignment_ids),
        )
        .all()
        if assignment_ids
        else []
    )
    attendance_by_assignment = {
        record.shift_assignment_id: record for record in attendance_rows
    }

    stats = defaultdict(
        lambda: {
            "assigned": 0,
            "attended": 0,
            "completed": 0,
            "on_time": 0,
            "late": 0,
            "absent": 0,
            "undertime": 0,
            "overtime_minutes": 0.0,
            "overtime_shifts": 0,
        }
    )
    trend = defaultdict(lambda: {"on_time": 0, "late": 0, "undertime": 0, "overtime": 0, "absent": 0})

    for assignment, shift in assignments:
        record = attendance_by_assignment.get(assignment.id)
        # Incomplete (forgotten clock-out) is excluded until corrected/finalized.
        if record is not None and record.status == AttendanceStatus.incomplete:
            continue
        # Approved leave is an authorized absence — excluded from scoring.
        if record is not None and record.status == AttendanceStatus.on_leave:
            continue

        has_time_in = record is not None and record.time_in is not None
        if not has_time_in:
            # Upcoming / still-within-cutoff shifts are not Absent and are
            # excluded from assigned so they do not depress attendance rate.
            if not _unpunched_noshow_due(
                now_local=now_local,
                work_date=assignment.work_date,
                shift=shift,
                cutoff_minutes=absent_cutoff_minutes,
            ):
                continue

        employee_stat = stats[assignment.employee_id]
        employee_stat["assigned"] += 1
        label = assignment.work_date.strftime("%b %d")

        if not has_time_in or record.status == AttendanceStatus.absent:
            employee_stat["absent"] += 1
            trend[label]["absent"] += 1
            continue

        employee_stat["attended"] += 1
        scheduled_start = _combine(assignment.work_date, shift.start_time)
        scheduled_end = _shift_end_at(assignment.work_date, shift)
        time_in_local = to_business_naive(record.time_in, tz_name)

        if time_in_local <= scheduled_start + timedelta(minutes=grace_minutes):
            employee_stat["on_time"] += 1
            trend[label]["on_time"] += 1
        else:
            employee_stat["late"] += 1
            trend[label]["late"] += 1

        if record.time_out is not None:
            employee_stat["completed"] += 1
            time_out = to_business_naive(record.time_out, tz_name)
            if time_out < scheduled_end:
                employee_stat["undertime"] += 1
                trend[label]["undertime"] += 1
            overtime_minutes = max((time_out - scheduled_end).total_seconds() / 60, 0)
            if overtime_minutes >= overtime_minimum:
                employee_stat["overtime_minutes"] += overtime_minutes
                employee_stat["overtime_shifts"] += 1
                trend[label]["overtime"] += 1

    employee_items: list[EmployeePerformanceItem] = []
    for employee in employees:
        item = stats[employee.id]
        assigned = int(item["assigned"])
        attended = int(item["attended"])
        completed = int(item["completed"])
        on_time = int(item["on_time"])
        late = int(item["late"])
        absent = int(item["absent"])
        undertime = int(item["undertime"])
        overtime_hours = round(float(item["overtime_minutes"]) / 60, 2)
        # Attendance Rate = completed scheduled shifts ÷ total scheduled shifts
        attendance_rate = _percent(completed, assigned)
        # Punctuality = on-time attendances ÷ total attendances (late is not punctual)
        punctuality_rate = _percent(on_time, attended)

        # Skip employees with no schedule in this period.
        if assigned == 0:
            continue

        employee_items.append(
            EmployeePerformanceItem(
                employee_id=str(employee.id),
                full_name=employee.full_name,
                position_title=employee.position_title,
                phone=employee.phone,
                profile_image_url=employee.profile_image_url,
                employment_type=employee.employment_type.value,
                assigned_shifts=assigned,
                attended_shifts=attended,
                completed_shifts=completed,
                on_time_clock_ins=on_time,
                late_clock_ins=late,
                absent_shifts=absent,
                undertime_shifts=undertime,
                overtime_hours=overtime_hours,
                attendance_rate=attendance_rate,
                punctuality_rate=punctuality_rate,
            )
        )

    employee_items.sort(key=lambda item: item.full_name.lower())

    total_assigned = sum(int(item["assigned"]) for item in stats.values())
    total_attended = sum(int(item["attended"]) for item in stats.values())
    total_completed = sum(int(item["completed"]) for item in stats.values())
    total_on_time = sum(int(item["on_time"]) for item in stats.values())
    total_late = sum(int(item["late"]) for item in stats.values())
    total_absent = sum(int(item["absent"]) for item in stats.values())
    total_undertime = sum(int(item["undertime"]) for item in stats.values())
    total_overtime_minutes = sum(float(item["overtime_minutes"]) for item in stats.values())
    total_overtime_shifts = sum(int(item["overtime_shifts"]) for item in stats.values())

    trend_items = [
        OwnerPerformanceTrendItem(
            label=label,
            on_time=values["on_time"],
            late=values["late"],
            undertime=values["undertime"],
            overtime=values["overtime"],
            absent=values["absent"],
        )
        for label, values in sorted(trend.items())
    ]

    has_data = total_assigned > 0 and (
        total_attended > 0 or total_absent > 0 or len(attendance_rows) > 0
    )

    return OwnerPerformanceResponse(
        summary=OwnerPerformanceSummary(
            has_performance_data=has_data,
            assigned_shifts=total_assigned,
            attended_shifts=total_attended,
            completed_shifts=total_completed,
            on_time_clock_ins=total_on_time,
            late_clock_ins=total_late,
            absent_shifts=total_absent,
            undertime_shifts=total_undertime,
            overtime_shifts=total_overtime_shifts,
            attendance_rate=_percent(total_completed, total_assigned),
            punctuality_rate=_percent(total_on_time, total_attended),
            total_overtime_hours=round(total_overtime_minutes / 60, 2),
        ),
        trend=trend_items,
        employees=employee_items,
    )
