"""Holiday policy resolution for payroll (amounts are calculated by payroll)."""

from __future__ import annotations

from dataclasses import dataclass

from app.models.enums import HolidayRulesMode, HolidayType
from app.models.holiday import Holiday
from app.models.payroll import BusinessPayrollConfig


@dataclass(frozen=True)
class HolidayPolicy:
    """Policy knobs for one holiday date. No money math here."""

    worked_multiplier: float
    pay_if_not_worked: bool
    suppress_absence: bool


def resolve_holiday_rules_mode(
    config: BusinessPayrollConfig | None,
) -> HolidayRulesMode:
    if config is None or getattr(config, "holiday_rules_mode", None) is None:
        return HolidayRulesMode.philippine_labor
    return config.holiday_rules_mode


def resolve_holiday_policy(
    *,
    holiday: Holiday | None,
    mode: HolidayRulesMode,
) -> HolidayPolicy | None:
    """Return how a holiday should be treated; payroll applies the amounts."""
    if holiday is None:
        return None

    multiplier = float(holiday.pay_multiplier)
    if multiplier <= 0:
        multiplier = 1.0

    if mode == HolidayRulesMode.custom_company:
        pay_if_not_worked = bool(holiday.is_paid)
        return HolidayPolicy(
            worked_multiplier=multiplier,
            pay_if_not_worked=pay_if_not_worked,
            suppress_absence=pay_if_not_worked,
        )

    # philippine_labor (default)
    if holiday.holiday_type == HolidayType.regular:
        return HolidayPolicy(
            worked_multiplier=multiplier,
            pay_if_not_worked=True,
            suppress_absence=True,
        )
    if holiday.holiday_type == HolidayType.special_non_working:
        return HolidayPolicy(
            worked_multiplier=multiplier,
            pay_if_not_worked=False,
            suppress_absence=False,
        )

    # company holiday — field-driven
    pay_if_not_worked = bool(holiday.is_paid)
    return HolidayPolicy(
        worked_multiplier=multiplier,
        pay_if_not_worked=pay_if_not_worked,
        suppress_absence=pay_if_not_worked,
    )
