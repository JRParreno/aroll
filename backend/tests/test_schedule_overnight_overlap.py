"""Overnight-aware schedule conflict overlap (same work_date)."""

from datetime import time
from types import SimpleNamespace

from app.services.schedule_overlap import shifts_times_overlap


def _shift(start: time, end: time) -> SimpleNamespace:
    return SimpleNamespace(start_time=start, end_time=end)


def test_normal_overlapping_shifts():
    assert shifts_times_overlap(
        _shift(time(8, 0), time(17, 0)),
        _shift(time(9, 0), time(18, 0)),
    )


def test_normal_non_overlapping_shifts():
    assert not shifts_times_overlap(
        _shift(time(8, 0), time(17, 0)),
        _shift(time(18, 0), time(22, 0)),
    )


def test_normal_adjacent_boundary_is_not_overlap():
    """Preserve strict < semantics: end == other start is not overlap."""
    assert not shifts_times_overlap(
        _shift(time(8, 0), time(17, 0)),
        _shift(time(17, 0), time(22, 0)),
    )


def test_overnight_overlapping_shifts():
    assert shifts_times_overlap(
        _shift(time(22, 0), time(6, 0)),
        _shift(time(23, 0), time(7, 0)),
    )


def test_overnight_non_overlapping_with_daytime_before():
    # Overnight Mon 22:00→Tue 06:00 vs Mon 14:00–21:00 — no absolute overlap.
    assert not shifts_times_overlap(
        _shift(time(22, 0), time(6, 0)),
        _shift(time(14, 0), time(21, 0)),
    )


def test_overnight_vs_morning_same_work_date_no_physical_overlap():
    # Mon 22:00→Tue 06:00 vs Mon 05:00–10:00 (same work_date label).
    # Next-day overnight end does not collide with morning of work_date.
    assert not shifts_times_overlap(
        _shift(time(22, 0), time(6, 0)),
        _shift(time(5, 0), time(10, 0)),
    )


def test_overnight_vs_day_starting_at_overnight_end_boundary():
    # 22:00–06:00 (+1 day) vs 06:00–14:00: touch at 06:00 → not overlap.
    assert not shifts_times_overlap(
        _shift(time(22, 0), time(6, 0)),
        _shift(time(6, 0), time(14, 0)),
    )


def test_overnight_vs_full_day_touching_both_ends_no_overlap():
    # 22:00–06:00 vs 06:00–22:00: endpoints touch overnight end and start.
    assert not shifts_times_overlap(
        _shift(time(22, 0), time(6, 0)),
        _shift(time(6, 0), time(22, 0)),
    )


def test_day_vs_overnight_overlapping_evening():
    # 18:00–23:00 overlaps overnight 22:00–06:00 on the evening portion.
    assert shifts_times_overlap(
        _shift(time(18, 0), time(23, 0)),
        _shift(time(22, 0), time(6, 0)),
    )


def test_day_vs_overnight_non_overlapping():
    assert not shifts_times_overlap(
        _shift(time(8, 0), time(17, 0)),
        _shift(time(22, 0), time(6, 0)),
    )


def test_identical_overnight_windows_overlap():
    assert shifts_times_overlap(
        _shift(time(22, 0), time(6, 0)),
        _shift(time(22, 0), time(6, 0)),
    )


def test_schedules_module_wrapper_matches_shared_helper():
    from app.api.schedules import _times_overlap

    a = _shift(time(22, 0), time(6, 0))
    b = _shift(time(23, 0), time(7, 0))
    assert _times_overlap(a, b) is shifts_times_overlap(a, b)


def test_schedule_reuse_wrapper_matches_shared_helper():
    from app.services.schedule_reuse import _times_overlap

    a = _shift(time(22, 0), time(6, 0))
    b = _shift(time(18, 0), time(23, 0))
    assert _times_overlap(a, b) is shifts_times_overlap(a, b)
