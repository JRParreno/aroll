"""Daily-rate schedule helpers. Money rules live in payroll_engine tests."""

from datetime import date, datetime, time

from app.api.owner_reports import _scheduled_shift_minutes, _shift_end_at, _shift_start_at
from app.models.scheduling import Shift
from app.services.payroll_engine import early_departure_minutes, monetary_late_minutes


def _shift(start: time, end: time, break_minutes: int = 0) -> Shift:
    return Shift(
        name="Test",
        start_time=start,
        end_time=end,
        break_minutes=break_minutes,
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


def test_scheduled_shift_minutes_respects_paid_breaktime_flag():
    work_date = date(2026, 9, 17)
    shift = _shift(time(13, 0), time(16, 0), break_minutes=35)
    assert _scheduled_shift_minutes(work_date, shift) == 145
    assert (
        _scheduled_shift_minutes(work_date, shift, breaktime_is_paid=False) == 145
    )
    assert _scheduled_shift_minutes(work_date, shift, breaktime_is_paid=True) == 180
    assert _shift_end_at(work_date, shift) == datetime(2026, 9, 17, 16, 0)


def test_short_shift_late_and_undertime_are_independent():
    """8:42–10:48 on 8:00–16:00: late after grace is not undertime."""
    start = datetime(2026, 7, 28, 8, 0)
    end = datetime(2026, 7, 28, 16, 0)
    time_in = datetime(2026, 7, 28, 8, 42)
    time_out = datetime(2026, 7, 28, 10, 48)
    late = monetary_late_minutes(
        time_in=time_in, scheduled_start=start, grace_minutes=10
    )
    undertime = early_departure_minutes(time_out=time_out, scheduled_end=end)
    assert late == 32
    assert undertime == 5 * 60 + 12
    daily_rate = 800.0
    late_deduction = late * 1.0
    undertime_deduction = undertime * (daily_rate / 480.0)
    assert late_deduction == 32.0
    assert abs(undertime_deduction - 520.0) < 0.01
    assert abs((daily_rate - late_deduction - undertime_deduction) - 248.0) < 0.01


def test_full_shift_has_zero_undertime():
    end = datetime(2026, 7, 28, 16, 0)
    assert (
        early_departure_minutes(
            time_out=datetime(2026, 7, 28, 16, 0),
            scheduled_end=end,
        )
        == 0
    )


def test_late_and_undertime_minutes_are_not_a_merged_unpaid_bucket():
    start = datetime(2026, 7, 28, 8, 0)
    end = datetime(2026, 7, 28, 16, 0)
    time_in = datetime(2026, 7, 28, 8, 42)
    time_out = datetime(2026, 7, 28, 10, 48)
    late = monetary_late_minutes(
        time_in=time_in, scheduled_start=start, grace_minutes=10
    )
    undertime = early_departure_minutes(time_out=time_out, scheduled_end=end)
    worked = (time_out - time_in).total_seconds() / 60.0
    scheduled = 8 * 60.0
    unpaid_overlap = scheduled - worked
    assert late + undertime != unpaid_overlap
    assert late == 32
    assert undertime == 312
