"""Unit tests for forgotten clock-out lazy evaluation helpers."""

from datetime import date, datetime, time

from app.services.missing_clock_out import is_past_clock_out_deadline


class _FakeShift:
    def __init__(self, start: time, end: time):
        self.start_time = start
        self.end_time = end


def test_is_past_clock_out_deadline_uses_grace():
    """Helper is window-agnostic; no-show callers still pass late grace."""
    shift = _FakeShift(time(9, 0), time(17, 0))
    work_date = date(2026, 8, 1)
    # 17:05 with 10-minute grace is still inside the window.
    assert not is_past_clock_out_deadline(
        now_local=datetime(2026, 8, 1, 17, 5),
        work_date=work_date,
        shift=shift,  # type: ignore[arg-type]
        grace_minutes=10,
    )
    # 17:11 is past end + grace.
    assert is_past_clock_out_deadline(
        now_local=datetime(2026, 8, 1, 17, 11),
        work_date=work_date,
        shift=shift,  # type: ignore[arg-type]
        grace_minutes=10,
    )


def test_overnight_shift_deadline():
    shift = _FakeShift(time(22, 0), time(6, 0))
    work_date = date(2026, 8, 1)
    # Ends next day 06:00 + 10 grace => 06:10.
    assert not is_past_clock_out_deadline(
        now_local=datetime(2026, 8, 2, 6, 5),
        work_date=work_date,
        shift=shift,  # type: ignore[arg-type]
        grace_minutes=10,
    )
    assert is_past_clock_out_deadline(
        now_local=datetime(2026, 8, 2, 6, 11),
        work_date=work_date,
        shift=shift,  # type: ignore[arg-type]
        grace_minutes=10,
    )
