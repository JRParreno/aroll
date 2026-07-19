from datetime import date

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
