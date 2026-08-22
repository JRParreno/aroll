"""Daily-rate payroll: pay only for hours worked against the assigned shift."""

from datetime import date, datetime, time

from app.api.owner_reports import _scheduled_shift_minutes, _shift_end_at, _shift_start_at
from app.models.scheduling import Shift


def _shift(start: time, end: time) -> Shift:
    return Shift(
        name="Test",
        start_time=start,
        end_time=end,
    )


def test_scheduled_shift_minutes_standard_eight_hour_day():
    work_date = date(2026, 7, 28)
    shift = _shift(time(8, 0), time(16, 0))
    assert _scheduled_shift_minutes(work_date, shift) == 8 * 60


def test_scheduled_shift_minutes_overnight():
    work_date = date(2026, 7, 28)
    shift = _shift(time(22, 0), time(6, 0))
    assert _scheduled_shift_minutes(work_date, shift) == 8 * 60
    assert _shift_end_at(work_date, shift) == datetime(2026, 7, 29, 6, 0)
    assert _shift_start_at(work_date, shift) == datetime(2026, 7, 28, 22, 0)


def test_example_short_shift_net_equals_hours_worked():
    """8:00–16:00 shift, in 8:42 out 10:48, daily rate 800 → net 210."""
    daily_rate = 800.0
    scheduled_minutes = 8 * 60.0
    hourly_rate = daily_rate / (scheduled_minutes / 60.0)
    assert hourly_rate == 100.0

    time_in = datetime(2026, 7, 28, 8, 42)
    time_out = datetime(2026, 7, 28, 10, 48)
    worked_minutes = (time_out - time_in).total_seconds() / 60.0
    assert worked_minutes == 2 * 60 + 6

    unpaid_minutes = scheduled_minutes - worked_minutes
    assert unpaid_minutes == 5 * 60 + 54

    minute_rate = daily_rate / scheduled_minutes
    shortfall = unpaid_minutes * minute_rate
    net = daily_rate - shortfall
    assert round(net, 2) == 210.0
    assert round(worked_minutes * minute_rate, 2) == 210.0


def test_full_shift_has_zero_undertime_shortfall():
    daily_rate = 800.0
    scheduled_minutes = 8 * 60.0
    time_in = datetime(2026, 7, 28, 8, 0)
    time_out = datetime(2026, 7, 28, 16, 0)
    worked_minutes = (time_out - time_in).total_seconds() / 60.0
    unpaid = max(scheduled_minutes - worked_minutes, 0.0)
    assert unpaid == 0.0
    assert daily_rate - unpaid * (daily_rate / scheduled_minutes) == daily_rate


def test_late_plus_undertime_equals_unpaid_without_grace():
    scheduled_start = datetime(2026, 7, 28, 8, 0)
    scheduled_end = datetime(2026, 7, 28, 16, 0)
    time_in = datetime(2026, 7, 28, 8, 42)
    time_out = datetime(2026, 7, 28, 10, 48)

    late = (time_in - scheduled_start).total_seconds() / 60.0
    undertime = (scheduled_end - time_out).total_seconds() / 60.0
    worked = (time_out - time_in).total_seconds() / 60.0
    scheduled = (scheduled_end - scheduled_start).total_seconds() / 60.0

    assert late == 42
    assert undertime == 5 * 60 + 12
    assert abs((late + undertime) - (scheduled - worked)) < 1e-9
    assert late + undertime == 5 * 60 + 54
