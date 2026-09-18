"""Shared payroll math used by the payslip assembler.

`_calculate_employee_payslip` is the only assembler of a payslip dict.
These helpers keep payable minutes, OT qualification, OT premiums, and
hours-worked consistent across API, PDF, and tests.

Rules encoded here:
- Payable regular minutes are the overlap of the punch with the scheduled
  shift, capped at scheduled_paid_minutes.
- Early arrival before scheduled start is never payable regular time and
  never offsets early departure.
- Monetary late minutes = max(time_in − start − grace, 0). Unused grace
  is not undertime. Late pesos use owner late_deduction_per_minute.
- Undertime minutes = early departure vs scheduled end only.
- Late/OT balancing (optional) lets post-end minutes recover late-from-start
  before remaining minutes can qualify as OT. Early arrival is excluded.
  Recovered minutes also reduce remaining monetary late minutes (after
  grace) before late pesos are calculated. OT that does not qualify still
  offsets late.
- OT minimum is applied to remaining OT after balancing. It is a
  qualification threshold and is never subtracted from payable minutes.
- OT pay uses owner overtime_per_minute × (1 + premium%/100).
- OT premium is 0% on ordinary days and rest days. The only extra premium
  is a holiday's own ot_premium_percent. NULL/unconfigured holiday OT
  premium is 0%. Business ordinary/rest-day OT percent fields are legacy
  and are not read.
- scheduled_paid_minutes is the canonical paid entitlement for a shift.
  Unpaid break minutes reduce it; paid breaktime does not. OT still starts
  at the original scheduled shift end.
- Open punches (time_in set, time_out missing) are pending or incomplete
  and must not produce payable payroll amounts.
- A calendar work date stays pending while any scheduled assignment that
  day is still unresolved (upcoming, in progress, or open punch inside
  the incomplete window). Daily-rate credit and day totals wait.
"""

from __future__ import annotations

from datetime import date, datetime, timedelta
from typing import Any, Sequence

_TERMINAL_ASSIGNMENT_STATUSES = frozenset({"absent", "incomplete", "on_leave"})


def scheduled_paid_minutes(
    *,
    span_minutes: float,
    break_minutes: Any = 0,
    breaktime_is_paid: bool = False,
) -> float:
    """Canonical scheduled paid working minutes for a shift.

    Paid breaktime keeps the full span. Unpaid breaktime subtracts break
    minutes, never below zero. OT still uses the original scheduled end.
    """
    span = max(float(span_minutes or 0), 0.0)
    if breaktime_is_paid:
        return span
    try:
        unpaid_break = max(int(break_minutes or 0), 0)
    except (TypeError, ValueError):
        unpaid_break = 0
    return max(span - unpaid_break, 0.0)


def scheduled_working_minutes(*, span_minutes: float, break_minutes: Any = 0) -> float:
    """Unpaid-break path. Prefer `scheduled_paid_minutes` when the flag is known."""
    return scheduled_paid_minutes(
        span_minutes=span_minutes,
        break_minutes=break_minutes,
        breaktime_is_paid=False,
    )


def in_shift_payable_minutes(
    *,
    time_in: datetime,
    time_out: datetime,
    scheduled_start: datetime,
    scheduled_end: datetime,
    scheduled_working: float,
) -> float:
    """Minutes of punch overlapping [scheduled_start, scheduled_end], capped."""
    overlap_start = max(time_in, scheduled_start)
    overlap_end = min(time_out, scheduled_end)
    overlap = max((overlap_end - overlap_start).total_seconds() / 60.0, 0.0)
    return min(overlap, max(float(scheduled_working or 0), 0.0))


def qualifying_overtime_minutes(
    *,
    time_in: datetime,
    time_out: datetime,
    scheduled_start: datetime,
    scheduled_end: datetime,
    ot_minimum: float,
    late_ot_balancing: bool,
) -> tuple[float, float]:
    """Return (payable_ot_minutes, recovered_late_minutes).

    Recovered minutes are post-end time used to offset late-from-start when
    Late/OT Balancing is enabled. They are not payable OT. The same recovered
    minutes reduce remaining monetary late (after grace) in the assembler.
    """
    raw_ot = max((time_out - scheduled_end).total_seconds() / 60.0, 0.0)
    recovered = 0.0
    remaining = raw_ot
    if late_ot_balancing:
        late_from_start = max(
            (time_in - scheduled_start).total_seconds() / 60.0,
            0.0,
        )
        recovered = min(raw_ot, late_from_start)
        remaining = max(raw_ot - recovered, 0.0)
    minimum = max(float(ot_minimum or 0), 0.0)
    # Balance first, then qualify remaining minutes. Do not subtract the
    # threshold and do not restore raw OT after balancing.
    if remaining >= minimum:
        return remaining, recovered
    return 0.0, recovered


def _holiday_specific_ot_premium(holiday: Any) -> float | None:
    """Configured holiday OT premium, or None when the holiday has no value."""
    if holiday is None:
        return None
    value = getattr(holiday, "ot_premium_percent", None)
    if value is None:
        return None
    try:
        return float(value)
    except (TypeError, ValueError):
        return None


def overtime_premium_percent(
    config: Any,
    holiday: Any,
    is_rest_day: bool,
) -> float:
    """Select OT premium.

    Holiday OT uses that holiday's `ot_premium_percent` (including 0%).
    NULL/unconfigured holiday OT premium is 0%. Ordinary days and rest
    days always use 0%. Legacy business ordinary/rest-day OT percent
    fields must not be read. `config` and `is_rest_day` stay in the
    signature for the payslip assembler; they do not choose a premium.
    """
    _ = (config, is_rest_day)
    holiday_specific = _holiday_specific_ot_premium(holiday)
    if holiday_specific is not None:
        return holiday_specific
    return 0.0


def monetary_late_minutes(
    *,
    time_in: datetime,
    scheduled_start: datetime,
    grace_minutes: float,
) -> float:
    """Minutes after scheduled start that exceed grace. Unused grace is 0 late."""
    raw = (time_in - scheduled_start).total_seconds() / 60.0
    return max(raw - max(float(grace_minutes or 0), 0.0), 0.0)


def remaining_monetary_late_minutes(
    *,
    monetary_late: float,
    recovered_late_minutes: float,
    late_ot_balancing: bool,
) -> float:
    """Late minutes charged after optional OT balancing.

    Grace is already applied in `monetary_late`. Balancing then subtracts
    recovered OT minutes. When balancing is off, monetary late is unchanged.
    """
    late = max(float(monetary_late or 0), 0.0)
    if not late_ot_balancing:
        return late
    recovered = max(float(recovered_late_minutes or 0), 0.0)
    return max(late - recovered, 0.0)


def early_departure_minutes(
    *,
    time_out: datetime,
    scheduled_end: datetime,
) -> float:
    """Minutes the punch ended before scheduled end. Early arrival is ignored."""
    return max((scheduled_end - time_out).total_seconds() / 60.0, 0.0)


def overtime_pay_amount(
    overtime_minutes: float,
    ot_rate_per_minute: float,
    premium_percent: float,
) -> float:
    """Owner OT ₱/minute × (1 + premium/100) × qualifying minutes."""
    minutes = max(float(overtime_minutes or 0), 0.0)
    rate = max(float(ot_rate_per_minute or 0), 0.0)
    premium = max(float(premium_percent or 0), 0.0)
    return minutes * rate * (1.0 + premium / 100.0)


def hours_worked_from_payable_minutes(payable_minutes: float) -> float:
    """Hours Worked = payable in-shift minutes / 60. Never days × 8."""
    return round(max(float(payable_minutes or 0), 0.0) / 60.0, 2)


def hours_worked_from_slip(slip: dict) -> float:
    """Pass through engine hours_worked; never recompute as days × 8."""
    if slip.get("hours_worked") is not None:
        return round(float(slip["hours_worked"]), 2)
    return 0.0


def _attendance_status_value(record: Any) -> str:
    status = getattr(record, "status", None)
    if status is None:
        return ""
    return str(getattr(status, "value", status))


def is_scheduled_assignment_resolved(
    *,
    now_local: datetime,
    today: date,
    work_date: date,
    scheduled_end: datetime,
    grace_minutes: float,
    records: Sequence[Any],
) -> bool:
    """Whether a scheduled assignment is done for calendar-day payroll.

    Resolved: completed punches, absent, incomplete, on_leave, or no
    attendance after the existing no-show deadline (scheduled end + grace).
    Future work dates with no attendance are not held pending.
    Unresolved: open punch still inside the incomplete window, or no
    attendance yet while the no-show deadline has not passed.
    """
    has_open_punch = False
    has_terminal_or_complete = False
    for record in records:
        status_value = _attendance_status_value(record)
        time_in = getattr(record, "time_in", None)
        time_out = getattr(record, "time_out", None)
        if status_value in _TERMINAL_ASSIGNMENT_STATUSES:
            has_terminal_or_complete = True
            continue
        if time_in is not None and time_out is None:
            has_open_punch = True
            continue
        if time_in is not None and time_out is not None:
            has_terminal_or_complete = True
    if has_open_punch:
        return False
    if has_terminal_or_complete:
        return True
    if work_date > today:
        return True
    deadline = scheduled_end + timedelta(minutes=max(float(grace_minutes or 0), 0.0))
    now = now_local.replace(tzinfo=None) if now_local.tzinfo else now_local
    end = deadline.replace(tzinfo=None) if deadline.tzinfo else deadline
    return now > end


def scheduled_shift_end_at(work_date: date, shift: Any) -> datetime:
    """Scheduled shift end on the assignment work date, including overnight."""
    end_at = datetime.combine(work_date, shift.end_time)
    if shift.end_time <= shift.start_time:
        end_at += timedelta(days=1)
    return end_at


def collect_unresolved_scheduled_assignments(
    scheduled_assignments: Sequence[tuple[Any, Any]],
    records_by_assignment_id: dict[Any, Sequence[Any]],
    *,
    now_local: datetime,
    today: date,
    grace_minutes: float,
) -> tuple[set[date], set[Any]]:
    """Calendar-day pending sets using is_scheduled_assignment_resolved."""
    pending_work_dates: set[date] = set()
    unresolved_ids: set[Any] = set()
    for assignment, shift in scheduled_assignments:
        if is_scheduled_assignment_resolved(
            now_local=now_local,
            today=today,
            work_date=assignment.work_date,
            scheduled_end=scheduled_shift_end_at(assignment.work_date, shift),
            grace_minutes=grace_minutes,
            records=records_by_assignment_id.get(assignment.id, []),
        ):
            continue
        pending_work_dates.add(assignment.work_date)
        unresolved_ids.add(assignment.id)
    return pending_work_dates, unresolved_ids
