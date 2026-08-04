"""Resolve employee-specific pay with Position.daily_rate fallback.

Phase 2: payroll reads daily pay from Employee first. Position.daily_rate is
legacy fallback / default template only.

Phase 3: hourly employees use Employee.hourly_rate via PayrollPayContext
(minute_rate + scheduled_day_value). Daily formulas stay identical.
"""

from __future__ import annotations

from dataclasses import dataclass
from typing import Any

from app.models.enums import PayBasis
from app.models.payroll import Position

DEFAULT_SCHEDULED_MINUTES = 8 * 60.0


@dataclass(frozen=True)
class ResolvedEmployeePay:
    pay_basis: PayBasis
    """Resolved daily rate for payroll formulas (employee → position fallback)."""
    daily_rate: float | None
    hourly_rate: float | None
    monthly_salary: float | None
    used_position_fallback: bool


@dataclass(frozen=True)
class PayrollPayContext:
    """Single source of payroll rates for a scheduled day length."""

    pay_basis: PayBasis
    daily_rate: float
    hourly_rate: float
    minute_rate: float
    scheduled_day_value: float
    scheduled_minutes: float
    used_position_fallback: bool


def _as_float(value: Any) -> float | None:
    if value is None:
        return None
    try:
        number = float(value)
    except (TypeError, ValueError):
        return None
    return number


def _positive(value: float | None) -> float | None:
    if value is None or value <= 0:
        return None
    return value


def resolve_employee_pay(
    employee: Any,
    *,
    position: Position | None = None,
) -> ResolvedEmployeePay:
    """Resolve pay fields for an employee.

    Daily payroll rate preference:
    1. Employee.daily_rate when set and > 0
    2. Position.daily_rate when employee rate missing
    3. None (callers treat as 0.0 for payslip math)

    Hourly / monthly are returned from the employee only (no Position fallback).
    """
    raw_basis = getattr(employee, "pay_basis", None) or PayBasis.daily
    if isinstance(raw_basis, PayBasis):
        pay_basis = raw_basis
    else:
        try:
            pay_basis = PayBasis(str(raw_basis))
        except ValueError:
            pay_basis = PayBasis.daily

    employee_daily = _positive(_as_float(getattr(employee, "daily_rate", None)))
    position_daily = None
    if position is not None:
        position_daily = _positive(_as_float(getattr(position, "daily_rate", None)))

    used_fallback = False
    if employee_daily is not None:
        daily_rate = employee_daily
    elif position_daily is not None:
        daily_rate = position_daily
        used_fallback = True
    else:
        daily_rate = None

    return ResolvedEmployeePay(
        pay_basis=pay_basis,
        daily_rate=daily_rate,
        hourly_rate=_positive(_as_float(getattr(employee, "hourly_rate", None))),
        monthly_salary=_positive(
            _as_float(getattr(employee, "monthly_salary", None))
        ),
        used_position_fallback=used_fallback,
    )


def payroll_daily_rate(resolved: ResolvedEmployeePay) -> float:
    """Legacy daily amount (employee → position). Not used for hourly earnings."""
    return float(resolved.daily_rate) if resolved.daily_rate is not None else 0.0


def resolve_employee_pay_context(
    employee: Any,
    scheduled_minutes: float,
    *,
    position: Position | None = None,
    resolved: ResolvedEmployeePay | None = None,
) -> PayrollPayContext:
    """Build the only payroll rate context used by payslip math.

    DAILY:
      minute_rate = daily_rate / scheduled_minutes
      scheduled_day_value = daily_rate

    HOURLY:
      minute_rate = hourly_rate / 60
      scheduled_day_value = hourly_rate × scheduled_hours

    Monthly still uses the daily-rate path until a later phase.
    """
    base = resolved or resolve_employee_pay(employee, position=position)
    sched = float(scheduled_minutes)
    if sched <= 0:
        sched = DEFAULT_SCHEDULED_MINUTES

    if base.pay_basis == PayBasis.hourly:
        hourly = float(base.hourly_rate) if base.hourly_rate is not None else 0.0
        minute_rate = hourly / 60.0
        scheduled_day_value = hourly * (sched / 60.0)
        return PayrollPayContext(
            pay_basis=PayBasis.hourly,
            daily_rate=payroll_daily_rate(base),
            hourly_rate=hourly,
            minute_rate=minute_rate,
            scheduled_day_value=scheduled_day_value,
            scheduled_minutes=sched,
            used_position_fallback=base.used_position_fallback,
        )

    daily = payroll_daily_rate(base)
    minute_rate = daily / sched if sched else 0.0
    derived_hourly = daily / (sched / 60.0) if sched else 0.0
    return PayrollPayContext(
        pay_basis=base.pay_basis,
        daily_rate=daily,
        hourly_rate=derived_hourly,
        minute_rate=minute_rate,
        scheduled_day_value=daily,
        scheduled_minutes=sched,
        used_position_fallback=base.used_position_fallback,
    )
