"""Shift time-span overlap and assignment window checks.

Overnight convention matches attendance / payroll / clock:
if ``end_time <= start_time``, the end falls on the next calendar day.
"""

from __future__ import annotations

from datetime import date, datetime, time, timedelta
from typing import Any

from fastapi import HTTPException

from app.core.timezone import business_now, get_business_tz

PAST_SHIFT_ASSIGNMENT_MESSAGE = (
    "This shift has already ended. Employees can only be assigned to shifts "
    "that are still ongoing or have not started yet."
)


def _shift_window(
    start: time,
    end: time,
    *,
    day: date = date(2000, 1, 1),
) -> tuple[datetime, datetime]:
    start_at = datetime.combine(day, start)
    end_at = datetime.combine(day, end)
    if end <= start:
        end_at += timedelta(days=1)
    return start_at, end_at


def _business_local_now(value: datetime, tz_name: str | None) -> datetime:
    """Naive business-local clock. A naive ``value`` is already local."""
    if value.tzinfo is None:
        return value
    return value.astimezone(get_business_tz(tz_name)).replace(tzinfo=None)


def shift_has_ended(
    work_date: date,
    shift: Any,
    *,
    tz_name: str | None,
    now: datetime | None = None,
) -> bool:
    """True when the scheduled end is at or before the business-local clock.

    A shift that has started is still assignable until that end. Comparison
    uses the business timezone, including an overnight end on the next day.
    """
    current = now if now is not None else business_now(tz_name)
    now_local = _business_local_now(current, tz_name)
    _start_at, end_at = _shift_window(shift.start_time, shift.end_time, day=work_date)
    return now_local >= end_at


def assert_shift_still_assignable(
    work_date: date,
    shift: Any,
    *,
    tz_name: str | None,
    now: datetime | None = None,
) -> None:
    if shift_has_ended(work_date, shift, tz_name=tz_name, now=now):
        raise HTTPException(400, PAST_SHIFT_ASSIGNMENT_MESSAGE)


def assert_shifts_still_assignable(
    slots: list[tuple[date, Any]],
    *,
    tz_name: str | None,
    now: datetime | None = None,
) -> None:
    """Reject the whole batch when any scheduled end is already past."""
    for work_date, shift in slots:
        if shift is None:
            continue
        assert_shift_still_assignable(work_date, shift, tz_name=tz_name, now=now)


def shifts_times_overlap(first: Any, second: Any) -> bool:
    """Return True when two shifts overlap on the same work_date.

    Boundary convention matches the previous wall-clock check: adjacent
    endpoints (end == other start) are not an overlap (strict ``<``).
    """
    a0, a1 = _shift_window(first.start_time, first.end_time)
    b0, b1 = _shift_window(second.start_time, second.end_time)
    return a0 < b1 and b0 < a1
