"""Attendance presence status from worked time vs scheduled shift duration.

Status determination uses percentage-of-shift thresholds from
BusinessAttendancePolicy so short and long shifts share one rule.

Payroll math continues to use fixed minute fields separately.
"""

from __future__ import annotations

from datetime import date, datetime, timedelta

from app.models.attendance_policy import BusinessAttendancePolicy
from app.models.enums import AttendanceStatus
from app.models.scheduling import Shift, ShiftAssignment
from app.services.attendance_clock import _clock_in_status, _scheduled_start


def scheduled_shift_minutes(*, work_date: date, shift: Shift) -> float:
    """Scheduled working minutes for a shift (supports overnight)."""
    start = datetime.combine(work_date, shift.start_time)
    end = datetime.combine(work_date, shift.end_time)
    if shift.end_time <= shift.start_time:
        end += timedelta(days=1)
    return max((end - start).total_seconds() / 60.0, 0.0)


def _clamp_percent(value: int | float | None, default: int) -> int:
    if value is None:
        return default
    try:
        return max(0, min(100, int(value)))
    except (TypeError, ValueError):
        return default


def absent_worked_minutes_bar(
    *,
    scheduled_minutes: float,
    policy: BusinessAttendancePolicy,
) -> float:
    """Minutes below which a closed attendance is marked absent.

    Prefer percent-of-scheduled-shift. Fall back to legacy fixed minutes when
    the schedule duration is unavailable.
    """
    if scheduled_minutes > 0:
        percent = _clamp_percent(
            getattr(policy, "absent_threshold_percent", None),
            25,
        )
        return scheduled_minutes * (percent / 100.0)

    half_day = int(getattr(policy, "half_day_threshold_minutes", 120) or 120)
    absent = int(getattr(policy, "absent_threshold_minutes", 240) or 240)
    return float(min(half_day, absent))


def resolve_closed_attendance_status(
    *,
    time_in: datetime,
    time_out: datetime | None,
    assignment: ShiftAssignment,
    shift: Shift,
    policy: BusinessAttendancePolicy,
    business_timezone: str | None,
    local_time_in: datetime | None = None,
) -> AttendanceStatus:
    """Resolve complete / late / absent / in_progress for a punch pair."""
    if local_time_in is None:
        from app.core.timezone import get_business_tz

        value = time_in
        if value.tzinfo is None:
            local_in = value
        else:
            local_in = value.astimezone(get_business_tz(business_timezone)).replace(
                tzinfo=None
            )
    else:
        local_in = local_time_in

    scheduled_start = _scheduled_start(assignment.work_date, shift)
    late_or_ok = _clock_in_status(
        now_local=local_in,
        scheduled_start=scheduled_start,
        grace_minutes=policy.on_time_grace_minutes,
    )

    if time_out is None:
        return (
            AttendanceStatus.late
            if late_or_ok == AttendanceStatus.late
            else AttendanceStatus.in_progress
        )

    worked_minutes = max((time_out - time_in).total_seconds() / 60.0, 0.0)
    scheduled_minutes = scheduled_shift_minutes(
        work_date=assignment.work_date,
        shift=shift,
    )
    absent_bar = absent_worked_minutes_bar(
        scheduled_minutes=scheduled_minutes,
        policy=policy,
    )
    if worked_minutes < absent_bar:
        return AttendanceStatus.absent
    if late_or_ok == AttendanceStatus.late:
        return AttendanceStatus.late
    return AttendanceStatus.complete
