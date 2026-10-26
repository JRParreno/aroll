from datetime import date, timedelta

from app.models.enums import PayPeriodType, Weekday
from app.models.payroll import BusinessPayrollConfig
from app.services.pay_period import resolve_pay_period


def test_weekly_period_ends_on_configured_weekday():
    config = BusinessPayrollConfig(
        business_id=None,  # type: ignore[arg-type]
        pay_period_type=PayPeriodType.weekly,
        weekly_payday_weekday=Weekday.friday,
    )
    # Wednesday 2026-07-15 → period ends Friday 2026-07-17
    start, end = resolve_pay_period(config, today=date(2026, 7, 15))
    assert end == date(2026, 7, 17)
    assert start == date(2026, 7, 11)


def test_monthly_period_uses_payday_day():
    config = BusinessPayrollConfig(
        business_id=None,  # type: ignore[arg-type]
        pay_period_type=PayPeriodType.monthly,
        monthly_payday_day=30,
    )
    start, end = resolve_pay_period(config, today=date(2026, 7, 19))
    assert end == date(2026, 7, 30)
    assert start == date(2026, 7, 1)


def _assert_adjacent(config: BusinessPayrollConfig, day: date) -> None:
    """Previous/next dates stay on the configured boundary and do not invent rows."""
    start, end = resolve_pay_period(config, today=day)
    previous = resolve_pay_period(config, today=start - timedelta(days=1))
    following = resolve_pay_period(config, today=end + timedelta(days=1))
    assert previous[1] == start - timedelta(days=1)
    assert following[0] == end + timedelta(days=1)
    assert resolve_pay_period(config, today=start) == (start, end)
    assert resolve_pay_period(config, today=end) == (start, end)
    assert resolve_pay_period(config, today=day) == (start, end)


def test_weekly_previous_and_next_follow_the_payday_weekday():
    config = BusinessPayrollConfig(
        business_id=None,  # type: ignore[arg-type]
        pay_period_type=PayPeriodType.weekly,
        weekly_payday_weekday=Weekday.friday,
    )
    _assert_adjacent(config, date(2026, 7, 15))


def test_semi_monthly_previous_and_next_cross_payday_boundaries():
    config = BusinessPayrollConfig(
        business_id=None,  # type: ignore[arg-type]
        pay_period_type=PayPeriodType.semi_monthly,
        semi_monthly_payday_1=15,
        semi_monthly_payday_2=28,
    )
    _assert_adjacent(config, date(2026, 7, 10))
    _assert_adjacent(config, date(2026, 7, 20))
    _assert_adjacent(config, date(2026, 7, 30))


def test_monthly_previous_and_next_cross_the_month():
    config = BusinessPayrollConfig(
        business_id=None,  # type: ignore[arg-type]
        pay_period_type=PayPeriodType.monthly,
        monthly_payday_day=30,
    )
    _assert_adjacent(config, date(2026, 7, 19))
    _assert_adjacent(config, date(2026, 1, 5))


def test_biweekly_previous_and_next_use_the_configured_anchor():
    config = BusinessPayrollConfig(
        business_id=None,  # type: ignore[arg-type]
        pay_period_type=PayPeriodType.bi_weekly,
        next_payday_date=date(2026, 7, 17),
    )
    _assert_adjacent(config, date(2026, 7, 15))
    _assert_adjacent(config, date(2026, 8, 1))
