"""Resolve the current pay period from BusinessPayrollConfig."""

from __future__ import annotations

import calendar
from datetime import date, timedelta

from app.models.enums import PayPeriodType, Weekday
from app.models.payroll import BusinessPayrollConfig

_WEEKDAY_INDEX = {
    Weekday.monday: 0,
    Weekday.tuesday: 1,
    Weekday.wednesday: 2,
    Weekday.thursday: 3,
    Weekday.friday: 4,
    Weekday.saturday: 5,
    Weekday.sunday: 6,
}


def _clamp_day(year: int, month: int, day: int) -> date:
    last = calendar.monthrange(year, month)[1]
    return date(year, month, min(max(day, 1), last))


def _previous_weekday_on_or_before(today: date, weekday: Weekday) -> date:
    target = _WEEKDAY_INDEX[weekday]
    delta = (today.weekday() - target) % 7
    return today - timedelta(days=delta)


def resolve_pay_period(
    config: BusinessPayrollConfig | None,
    *,
    today: date | None = None,
) -> tuple[date, date]:
    """Return inclusive (period_start, period_end) for the current cycle."""
    today = today or date.today()
    if config is None:
        return today - timedelta(days=13), today

    period_type = config.pay_period_type

    if period_type == PayPeriodType.weekly:
        weekday = config.weekly_payday_weekday or Weekday.friday
        period_end = _previous_weekday_on_or_before(today, weekday)
        if period_end < today and (today - period_end).days >= 7:
            period_end = period_end + timedelta(days=7)
        # Current week ending on the next/this payday weekday
        days_until = (_WEEKDAY_INDEX[weekday] - today.weekday()) % 7
        period_end = today + timedelta(days=days_until)
        period_start = period_end - timedelta(days=6)
        return period_start, period_end

    if period_type == PayPeriodType.bi_weekly:
        if config.next_payday_date is not None:
            period_end = config.next_payday_date
            while period_end < today:
                period_end = period_end + timedelta(days=14)
            while period_end - timedelta(days=14) >= today:
                period_end = period_end - timedelta(days=14)
            # Active cycle ends on next payday
            if period_end < today:
                period_end = period_end + timedelta(days=14)
            period_start = period_end - timedelta(days=13)
            return period_start, period_end
        return today - timedelta(days=13), today

    if period_type == PayPeriodType.semi_monthly:
        d1 = config.semi_monthly_payday_1 or 15
        d2 = config.semi_monthly_payday_2 or 28
        first = _clamp_day(today.year, today.month, d1)
        second = _clamp_day(today.year, today.month, d2)
        if today.day <= first.day:
            period_end = first
            # Previous cycle ended on prior month's second payday
            if today.month == 1:
                prev_year, prev_month = today.year - 1, 12
            else:
                prev_year, prev_month = today.year, today.month - 1
            prev_second = _clamp_day(prev_year, prev_month, d2)
            period_start = prev_second + timedelta(days=1)
            return period_start, period_end
        if today.day <= second.day:
            period_end = second
            period_start = first + timedelta(days=1)
            return period_start, period_end
        # After second payday → next month first half
        if today.month == 12:
            next_year, next_month = today.year + 1, 1
        else:
            next_year, next_month = today.year, today.month + 1
        period_end = _clamp_day(next_year, next_month, d1)
        period_start = second + timedelta(days=1)
        return period_start, period_end

    # monthly
    day = config.monthly_payday_day or 30
    this_payday = _clamp_day(today.year, today.month, day)
    if today <= this_payday:
        period_end = this_payday
        if today.month == 1:
            prev_year, prev_month = today.year - 1, 12
        else:
            prev_year, prev_month = today.year, today.month - 1
        prev_payday = _clamp_day(prev_year, prev_month, day)
        period_start = prev_payday + timedelta(days=1)
        return period_start, period_end

    if today.month == 12:
        next_year, next_month = today.year + 1, 1
    else:
        next_year, next_month = today.year, today.month + 1
    period_end = _clamp_day(next_year, next_month, day)
    period_start = this_payday + timedelta(days=1)
    return period_start, period_end
