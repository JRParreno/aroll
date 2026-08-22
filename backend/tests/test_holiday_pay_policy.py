"""Holiday policy resolver — policy only, no payroll amounts."""

from types import SimpleNamespace

from app.models.enums import HolidayRulesMode, HolidayType
from app.services.holiday_pay import (
    resolve_holiday_policy,
    resolve_holiday_rules_mode,
)


def _holiday(
    *,
    holiday_type: HolidayType,
    is_paid: bool = True,
    pay_multiplier: float = 2.0,
):
    return SimpleNamespace(
        holiday_type=holiday_type,
        is_paid=is_paid,
        pay_multiplier=pay_multiplier,
    )


def test_default_mode_when_config_missing():
    assert resolve_holiday_rules_mode(None) == HolidayRulesMode.philippine_labor


def test_ph_regular_unworked_pays_and_suppresses_absence():
    policy = resolve_holiday_policy(
        holiday=_holiday(holiday_type=HolidayType.regular, pay_multiplier=2.0),
        mode=HolidayRulesMode.philippine_labor,
    )
    assert policy is not None
    assert policy.worked_multiplier == 2.0
    assert policy.pay_if_not_worked is True
    assert policy.suppress_absence is True


def test_ph_special_unworked_no_pay():
    policy = resolve_holiday_policy(
        holiday=_holiday(
            holiday_type=HolidayType.special_non_working,
            pay_multiplier=1.3,
        ),
        mode=HolidayRulesMode.philippine_labor,
    )
    assert policy is not None
    assert policy.worked_multiplier == 1.3
    assert policy.pay_if_not_worked is False
    assert policy.suppress_absence is False


def test_ph_company_uses_is_paid():
    paid = resolve_holiday_policy(
        holiday=_holiday(
            holiday_type=HolidayType.company,
            is_paid=True,
            pay_multiplier=1.5,
        ),
        mode=HolidayRulesMode.philippine_labor,
    )
    unpaid = resolve_holiday_policy(
        holiday=_holiday(
            holiday_type=HolidayType.company,
            is_paid=False,
            pay_multiplier=1.5,
        ),
        mode=HolidayRulesMode.philippine_labor,
    )
    assert paid is not None and paid.pay_if_not_worked is True
    assert unpaid is not None and unpaid.pay_if_not_worked is False


def test_custom_ignores_holiday_type_uses_is_paid():
    # Even regular type + unpaid → no unworked pay in custom mode
    policy = resolve_holiday_policy(
        holiday=_holiday(
            holiday_type=HolidayType.regular,
            is_paid=False,
            pay_multiplier=2.0,
        ),
        mode=HolidayRulesMode.custom_company,
    )
    assert policy is not None
    assert policy.worked_multiplier == 2.0
    assert policy.pay_if_not_worked is False
    assert policy.suppress_absence is False


def test_custom_paid_unworked():
    policy = resolve_holiday_policy(
        holiday=_holiday(
            holiday_type=HolidayType.special_non_working,
            is_paid=True,
            pay_multiplier=1.3,
        ),
        mode=HolidayRulesMode.custom_company,
    )
    assert policy is not None
    assert policy.pay_if_not_worked is True
    assert policy.suppress_absence is True


def test_none_holiday_returns_none():
    assert (
        resolve_holiday_policy(
            holiday=None, mode=HolidayRulesMode.philippine_labor
        )
        is None
    )
