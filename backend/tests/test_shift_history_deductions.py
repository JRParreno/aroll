"""Shift History day-deduction aggregation must not double-count undertime."""

from app.api.owner_reports import _shift_history_day_deductions


def test_undertime_and_matching_shortfall_counted_once():
    """CASE 1: shortfall mirrors undertime → count once (Nicole-style)."""
    assert (
        _shift_history_day_deductions(
            late_deduction=0.0,
            undertime_deduction=38.02,
            shortfall_deduction=38.02,
        )
        == 38.02
    )


def test_separate_shortfall_without_undertime_still_counted():
    """CASE 2: shortfall only → still included."""
    assert (
        _shift_history_day_deductions(
            late_deduction=0.0,
            undertime_deduction=0.0,
            shortfall_deduction=12.5,
        )
        == 12.5
    )


def test_no_undertime_or_shortfall_unchanged():
    """CASE 3: neither undertime nor shortfall → late only / zero."""
    assert (
        _shift_history_day_deductions(
            late_deduction=0.0,
            undertime_deduction=0.0,
            shortfall_deduction=0.0,
        )
        == 0.0
    )
    assert (
        _shift_history_day_deductions(
            late_deduction=2.81,
            undertime_deduction=0.0,
            shortfall_deduction=0.0,
        )
        == 2.81
    )


def test_multiple_legitimate_deduction_types_once_each():
    """CASE 4: late + undertime (with matching shortfall alias) each once."""
    assert (
        _shift_history_day_deductions(
            late_deduction=2.81,
            undertime_deduction=38.02,
            shortfall_deduction=38.02,
        )
        == 40.83
    )


def test_genuinely_different_shortfall_still_added():
    """If shortfall differs from undertime, keep both (separate amounts)."""
    assert (
        _shift_history_day_deductions(
            late_deduction=1.0,
            undertime_deduction=10.0,
            shortfall_deduction=5.0,
        )
        == 16.0
    )
