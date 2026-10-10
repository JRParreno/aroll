"""Shift time-span overlap for schedule conflict checks.

Overnight convention matches attendance / payroll / clock:
if ``end_time <= start_time``, the end falls on the next calendar day.
"""

from __future__ import annotations

from datetime import date, datetime, time, timedelta
from typing import Any


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


def shifts_times_overlap(first: Any, second: Any) -> bool:
    """Return True when two shifts overlap on the same work_date.

    Boundary convention matches the previous wall-clock check: adjacent
    endpoints (end == other start) are not an overlap (strict ``<``).
    """
    a0, a1 = _shift_window(first.start_time, first.end_time)
    b0, b1 = _shift_window(second.start_time, second.end_time)
    return a0 < b1 and b0 < a1
