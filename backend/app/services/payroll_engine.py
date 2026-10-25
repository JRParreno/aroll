"""Shared payroll math used by the payslip assembler.

`_calculate_employee_payslip` is the only assembler of a payslip dict.
These helpers keep payable minutes, OT qualification, OT premiums, and
hours-worked consistent across API, PDF, and tests.

Rules encoded here:
- Payable regular minutes are the overlap of the punch with the scheduled
  shift, capped at scheduled_paid_minutes.
- Early arrival before scheduled start is never payable regular time and
  never offsets early departure.
- Monetary late minutes = max(time_in − start − grace, 0). The grace
  clock-minute is inclusive, so a punch during that minute is 0 late.
  Unused grace is not undertime. Late pesos use owner late_deduction_per_minute.
- Undertime minutes = early departure vs scheduled end only.
- Late/OT balancing (optional) lets post-end minutes recover late-from-start
  before remaining minutes can qualify as OT. Early arrival is excluded.
  Recovered minutes also reduce remaining monetary late minutes (after
  grace) before late pesos are calculated. OT that does not qualify still
  offsets late.
- OT minimum is applied to remaining OT after balancing. It is a
  qualification threshold and is never subtracted from payable minutes.
- Which minutes qualify as overtime is the scheduled shift end, then the
  business OT minimum and optional late balancing. A shift shorter than
  eight hours still qualifies past its own scheduled end. Eight hours is
  not an overtime threshold.
- How those minutes are priced follows overtime_calculation_method.
  The default, flat_per_minute, uses the owner's overtime_per_minute.
  hourly_statutory prices the same minutes from the basic hourly rate
  and the day factor. The owner rate is not replaced unless that method
  is selected. A flat rate can be below the handbook minimum; that
  conflict is not silently corrected.
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

from app.models.enums import HolidayRulesMode, HolidayType

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
    """Minutes after scheduled start that exceed grace. Unused grace is 0 late.

    A punch in the grace-end clock minute (8:10:06 with a 10-minute grace
    from 8:00) has zero chargeable minutes. Once the next minute begins,
    the existing second-based remainder applies.
    """
    from app.services.attendance_clock import arrival_is_after_grace

    if not arrival_is_after_grace(
        arrived_at=time_in,
        scheduled_start=scheduled_start,
        grace_minutes=grace_minutes,
    ):
        return 0.0
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


FLAT_PER_MINUTE = "flat_per_minute"
HOURLY_STATUTORY = "hourly_statutory"


def resolve_overtime_calculation_method(config: Any) -> str:
    """Owner OT pricing method. Missing or unknown values stay flat.

    `holiday_rules_mode` is not this setting. Holiday classification and
    the overtime price are separate owner choices. Missing or invalid
    values stay on the saved peso-per-minute rate. The stored peso rate
    itself is not changed.
    """
    raw = getattr(config, "overtime_calculation_method", None) if config is not None else None
    value = _enum_value(raw)
    if value == HOURLY_STATUTORY:
        return HOURLY_STATUTORY
    return FLAT_PER_MINUTE


def overtime_pay_amount(
    overtime_minutes: float,
    ot_rate_per_minute: float,
    premium_percent: float,
) -> float:
    """Owner ₱/minute × (1 + premium/100) × qualifying minutes.

    This is the flat_per_minute payslip method. The premium argument is
    the holiday's own ot_premium_percent, or 0 on ordinary and rest days.
    """
    minutes = max(float(overtime_minutes or 0), 0.0)
    rate = max(float(ot_rate_per_minute or 0), 0.0)
    premium = max(float(premium_percent or 0), 0.0)
    return minutes * rate * (1.0 + premium / 100.0)


def _enum_value(value: Any) -> str:
    if value is None:
        return ""
    return str(getattr(value, "value", value))


def overtime_rate_factors(
    *,
    holiday: Any,
    is_rest_day: bool,
    rest_premium_percent: float,
    rules_mode: Any = None,
) -> tuple[float, float]:
    """Return (day_factor, overtime_factor) for one classified workday.

    OT hourly rate = basic hourly rate × day_factor × overtime_factor.
    The day factor is the multiple that already applies to an hour on
    that kind of day. The overtime factor is applied once to that rate.
    Holiday pay and rest-day premium for scheduled hours stay outside
    this amount, so those premiums are not added again here.

    Handbook on Workers' Statutory Monetary Benefits (2024 edition):
    ordinary OT is 125% of the basic hourly rate; OT on a rest day,
    special non-working day, or regular holiday is 130% of the hourly
    rate on that day. A special day on a rest day is 150% of basic for
    the day, then × 130%. A regular holiday on a rest day is the
    holiday rate × the rest-day rate, then × 130%.
    """
    rest_ratio = max(float(rest_premium_percent or 0.0), 0.0) / 100.0
    rest_factor = 1.0 + rest_ratio
    if holiday is None:
        if is_rest_day:
            return rest_factor, 1.30
        return 1.0, 1.25

    raw_multiplier = getattr(holiday, "pay_multiplier", 1.0)
    try:
        multiplier = float(raw_multiplier if raw_multiplier is not None else 1.0)
    except (TypeError, ValueError):
        multiplier = 1.0
    if multiplier <= 0:
        multiplier = 1.0

    holiday_type = _enum_value(getattr(holiday, "holiday_type", None))
    custom = _enum_value(rules_mode) == HolidayRulesMode.custom_company.value
    if (
        holiday_type == HolidayType.special_non_working.value
        and is_rest_day
        and not custom
    ):
        return 1.50, 1.30
    if is_rest_day and (
        holiday_type == HolidayType.regular.value
        or holiday_type == HolidayType.company.value
        or custom
    ):
        return multiplier * rest_factor, 1.30
    return multiplier, 1.30


def statutory_overtime_pay_amount(
    overtime_minutes: float,
    basic_hourly_rate: float,
    *,
    holiday: Any = None,
    is_rest_day: bool = False,
    rest_premium_percent: float = 0.0,
    rules_mode: Any = None,
) -> float:
    """Qualifying minutes priced at the basic hourly rate and day factors."""
    minutes = max(float(overtime_minutes or 0), 0.0)
    hourly = max(float(basic_hourly_rate or 0), 0.0)
    if minutes <= 0.0 or hourly <= 0.0:
        return 0.0
    day_factor, overtime_factor = overtime_rate_factors(
        holiday=holiday,
        is_rest_day=is_rest_day,
        rest_premium_percent=rest_premium_percent,
        rules_mode=rules_mode,
    )
    return (minutes / 60.0) * hourly * day_factor * overtime_factor


def scheduled_premium_amounts(
    earned: float,
    *,
    holiday: Any,
    is_rest_day: bool,
    rest_premium_percent: float,
    rules_mode: Any = None,
    worked_multiplier: float | None = None,
) -> tuple[float, float]:
    """Premiums above basic for scheduled hours: (holiday, rest).

    A rest day alone uses the saved percent of basic. A holiday that is
    not a rest day uses the saved multiplier minus the basic amount.
    Under Philippine labor rules, a regular holiday on a rest day pays the
    rest percent on the holiday rate, so a 2.00 multiplier and 30% rest
    premium total 260% of basic. A special non-working day on a rest day
    is 150% of basic once; the rest percent is not added again. Company
    holidays and custom rules stay additive.
    """
    base = max(float(earned or 0.0), 0.0)
    if base <= 0.0:
        return 0.0, 0.0
    rest_ratio = max(float(rest_premium_percent or 0.0), 0.0) / 100.0
    if holiday is None:
        if is_rest_day:
            return 0.0, base * rest_ratio
        return 0.0, 0.0

    raw_multiplier = (
        worked_multiplier
        if worked_multiplier is not None
        else getattr(holiday, "pay_multiplier", 1.0)
    )
    try:
        multiplier = float(raw_multiplier if raw_multiplier is not None else 1.0)
    except (TypeError, ValueError):
        multiplier = 1.0
    if multiplier <= 0.0:
        multiplier = 1.0
    holiday_premium = max(base * (multiplier - 1.0), 0.0)
    if not is_rest_day:
        return holiday_premium, 0.0

    holiday_type = _enum_value(getattr(holiday, "holiday_type", None))
    custom = _enum_value(rules_mode) == HolidayRulesMode.custom_company.value
    if holiday_type == HolidayType.special_non_working.value and not custom:
        return base * 0.50, 0.0
    if holiday_type == HolidayType.regular.value and not custom:
        return holiday_premium, base * multiplier * rest_ratio
    return holiday_premium, base * rest_ratio


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
