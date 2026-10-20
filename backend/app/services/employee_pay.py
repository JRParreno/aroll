"""Resolve employee-specific pay with Position rate fallback.

Phase 2: payroll reads daily pay from Employee first. Position.daily_rate is
legacy fallback / default template only.

Phase 3: hourly employees use Employee.hourly_rate via PayrollPayContext
(minute_rate + scheduled_day_value). Position.hourly_rate is the hourly
template / fallback. Daily formulas stay identical.
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

    Hourly payroll rate preference:
    1. Employee.hourly_rate when set and > 0
    2. Position.hourly_rate when employee rate missing
    3. None (callers treat as 0.0 for payslip math)

    Monthly is returned from the employee only (no Position fallback).
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
    employee_hourly = _positive(_as_float(getattr(employee, "hourly_rate", None)))
    position_daily = None
    position_hourly = None
    if position is not None:
        position_daily = _positive(_as_float(getattr(position, "daily_rate", None)))
        position_hourly = _positive(
            _as_float(getattr(position, "hourly_rate", None))
        )

    used_fallback = False
    if employee_daily is not None:
        daily_rate = employee_daily
    elif position_daily is not None:
        daily_rate = position_daily
        used_fallback = True
    else:
        daily_rate = None

    if employee_hourly is not None:
        hourly_rate = employee_hourly
    elif position_hourly is not None:
        hourly_rate = position_hourly
        used_fallback = True
    else:
        hourly_rate = None

    return ResolvedEmployeePay(
        pay_basis=pay_basis,
        daily_rate=daily_rate,
        hourly_rate=hourly_rate,
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
      minute_rate = daily_rate / scheduled_minutes  (undertime only)
      scheduled_day_value = daily_rate

    HOURLY:
      minute_rate = hourly_rate / 60  (undertime only)
      scheduled_day_value = hourly_rate × scheduled_hours

    Late pesos use the owner late rate. Overtime uses hourly_rate.
    Undertime uses minute_rate.

    Monthly has no conversion divisor. It uses the daily-rate path when a
    daily_rate exists; otherwise regular pay is 0. Do not invent a monthly
    divisor.
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


# Payslip day ``payroll_status`` when a closed attendance has no completion stamp
# or when same-date Daily completion stamps disagree.
HISTORICAL_RATE_REQUIRED = "historical_rate_required"


def attendance_has_completion_pay(record: Any) -> bool:
    """True when a completion pay stamp was captured on the attendance row."""
    basis = getattr(record, "pay_basis_at_completion", None)
    if basis is None:
        return False
    if isinstance(basis, PayBasis):
        return True
    try:
        PayBasis(str(basis))
        return True
    except ValueError:
        return False


def attendance_is_closed_punch(record: Any) -> bool:
    """True when the attendance has both punches and is not still open."""
    from app.models.enums import AttendanceStatus

    if getattr(record, "time_in", None) is None:
        return False
    if getattr(record, "time_out", None) is None:
        return False
    status = getattr(record, "status", None)
    status_value = getattr(status, "value", status)
    if status_value in (
        AttendanceStatus.in_progress.value,
        AttendanceStatus.incomplete.value,
        None,
    ):
        return False
    return True


def attendance_requires_historical_rate(record: Any) -> bool:
    """Closed attendance with no completion stamp — rate is unknown, not live."""
    if attendance_has_completion_pay(record):
        return False
    return attendance_is_closed_punch(record)


def _stamp_pay_basis(record: Any) -> PayBasis | None:
    if not attendance_has_completion_pay(record):
        return None
    raw = getattr(record, "pay_basis_at_completion", None)
    if isinstance(raw, PayBasis):
        return raw
    try:
        return PayBasis(str(raw))
    except ValueError:
        return None


def _stamp_daily_rate_amount(record: Any) -> float | None:
    """Positive Daily completion amount, or None."""
    if _stamp_pay_basis(record) != PayBasis.daily:
        return None
    amount = _positive(_as_float(getattr(record, "daily_rate_at_completion", None)))
    return amount


def find_conflicting_daily_work_dates(
    rows: list[tuple[Any, Any, Any]],
) -> set:
    """Work dates where 2+ completed Daily stamps disagree on the Daily amount.

    Hourly stamps are ignored. Mixed Daily+Hourly on one date is not a conflict.
    Order of ``rows`` must not matter — only the set of stamped Daily amounts.
    """
    from datetime import date as date_cls

    from app.models.enums import AttendanceStatus

    rates_by_date: dict[date_cls, set[float]] = {}
    skip_statuses = (
        AttendanceStatus.absent,
        AttendanceStatus.incomplete,
        AttendanceStatus.on_leave,
    )
    skip_values = {"absent", "incomplete", "on_leave"}

    for record, assignment, _shift in rows:
        if assignment is None:
            continue
        work_date = getattr(assignment, "work_date", None)
        if work_date is None:
            continue
        if not attendance_is_closed_punch(record):
            continue
        status = getattr(record, "status", None)
        status_value = getattr(status, "value", status)
        if status in skip_statuses or status_value in skip_values:
            continue
        amount = _stamp_daily_rate_amount(record)
        if amount is None:
            continue
        rates_by_date.setdefault(work_date, set()).add(round(float(amount), 2))

    return {work_date for work_date, rates in rates_by_date.items() if len(rates) > 1}


def unique_daily_rate_for_work_date(
    rows: list[tuple[Any, Any, Any]],
    work_date,
) -> float | None:
    """Single agreed Daily stamp amount for a work_date, or None if none/conflict."""
    amounts: set[float] = set()
    from app.models.enums import AttendanceStatus

    for record, assignment, _shift in rows:
        if assignment is None or getattr(assignment, "work_date", None) != work_date:
            continue
        if not attendance_is_closed_punch(record):
            continue
        status = getattr(record, "status", None)
        if status in (
            AttendanceStatus.absent,
            AttendanceStatus.incomplete,
            AttendanceStatus.on_leave,
        ):
            continue
        amount = _stamp_daily_rate_amount(record)
        if amount is None:
            continue
        amounts.add(round(float(amount), 2))
    if len(amounts) == 1:
        return next(iter(amounts))
    return None


def load_daily_workday_entitlements_for_employee(
    db: Any,
    *,
    business_id: Any,
    employee_id: Any,
    period_start: Any,
    period_end: Any,
) -> dict:
    """Map work_date → Owner-selected Daily entitlement for one employee."""
    from datetime import date as date_cls

    from app.models.daily_workday_rate_resolution import DailyWorkdayRateResolution

    rows = (
        db.query(DailyWorkdayRateResolution)
        .filter(
            DailyWorkdayRateResolution.business_id == business_id,
            DailyWorkdayRateResolution.employee_id == employee_id,
            DailyWorkdayRateResolution.work_date >= period_start,
            DailyWorkdayRateResolution.work_date <= period_end,
        )
        .all()
    )
    out: dict[date_cls, float] = {}
    for row in rows or []:
        work_date = getattr(row, "work_date", None)
        amount = _positive(_as_float(getattr(row, "daily_rate", None)))
        if work_date is None or amount is None:
            continue
        out[work_date] = float(amount)
    return out


def load_daily_workday_entitlements_for_business(
    db: Any,
    *,
    business_id: Any,
    period_start: Any,
    period_end: Any,
) -> dict:
    """Map (employee_id, work_date) → Owner-selected Daily entitlement."""
    from datetime import date as date_cls

    from app.models.daily_workday_rate_resolution import DailyWorkdayRateResolution

    rows = (
        db.query(DailyWorkdayRateResolution)
        .filter(
            DailyWorkdayRateResolution.business_id == business_id,
            DailyWorkdayRateResolution.work_date >= period_start,
            DailyWorkdayRateResolution.work_date <= period_end,
        )
        .all()
    )
    out: dict[tuple[Any, date_cls], float] = {}
    for row in rows or []:
        employee_id = getattr(row, "employee_id", None)
        work_date = getattr(row, "work_date", None)
        amount = _positive(_as_float(getattr(row, "daily_rate", None)))
        if employee_id is None or work_date is None or amount is None:
            continue
        out[(employee_id, work_date)] = float(amount)
    return out


def apply_owner_daily_workday_rate(
    db: Any,
    *,
    business_id: Any,
    employee_id: Any,
    work_date: Any,
    daily_rate: float,
    resolved_by: Any | None = None,
) -> float:
    """Persist Owner Daily workday entitlement for a conflicting work_date.

    Never mutates AttendanceRecord ``*_at_completion`` historical stamps.
    Upserts one row keyed by business + employee + work_date.
    """
    from datetime import datetime, timezone

    from app.models.daily_workday_rate_resolution import DailyWorkdayRateResolution
    from app.schemas.employee import _validate_pay_fields

    rate = _positive(_as_float(daily_rate))
    if rate is None:
        raise ValueError("daily_rate must be a positive amount.")
    _validate_pay_fields(
        pay_basis=PayBasis.daily,
        daily_rate=rate,
        hourly_rate=None,
        monthly_salary=None,
    )

    existing = (
        db.query(DailyWorkdayRateResolution)
        .filter(
            DailyWorkdayRateResolution.business_id == business_id,
            DailyWorkdayRateResolution.employee_id == employee_id,
            DailyWorkdayRateResolution.work_date == work_date,
        )
        .first()
    )
    now = datetime.now(timezone.utc)
    if existing is None:
        db.add(
            DailyWorkdayRateResolution(
                business_id=business_id,
                employee_id=employee_id,
                work_date=work_date,
                daily_rate=float(rate),
                resolved_by=resolved_by,
            )
        )
    else:
        existing.daily_rate = float(rate)
        existing.resolved_by = resolved_by
        existing.updated_at = now
        db.add(existing)
    return float(rate)


def resolve_attendance_pay(
    record: Any,
    employee: Any,
    *,
    position: Position | None = None,
) -> ResolvedEmployeePay | None:
    """Rate authority for one attendance day.

    - Completion stamp (when present) wins over the current Employee stamp.
    - Closed attendance with no stamp returns ``None`` (historical rate required).
      Callers must not fall back to current Employee pay for that day.
    - Open / incomplete punches are not priced here; callers should not invoke
      this helper for open rows. If invoked without a stamp on a non-closed row,
      current Employee pay is returned for backward compatibility.
    """
    if attendance_has_completion_pay(record):
        raw_basis = getattr(record, "pay_basis_at_completion", None)
        if isinstance(raw_basis, PayBasis):
            pay_basis = raw_basis
        else:
            try:
                pay_basis = PayBasis(str(raw_basis))
            except ValueError:
                pay_basis = PayBasis.daily

        return ResolvedEmployeePay(
            pay_basis=pay_basis,
            daily_rate=_positive(
                _as_float(getattr(record, "daily_rate_at_completion", None))
            ),
            hourly_rate=_positive(
                _as_float(getattr(record, "hourly_rate_at_completion", None))
            ),
            monthly_salary=_positive(
                _as_float(getattr(record, "monthly_salary_at_completion", None))
            ),
            used_position_fallback=False,
        )

    if attendance_requires_historical_rate(record):
        return None

    return resolve_employee_pay(employee, position=position)


def apply_owner_completion_pay(
    record: Any,
    *,
    pay_basis: PayBasis,
    daily_rate: float | None,
    hourly_rate: float | None,
    monthly_salary: float | None,
) -> None:
    """Owner-supplied historical completion stamp for a legacy NULL-stamp close.

    Never overwrites an existing stamp. Never copies current Employee/Position.
    """
    from app.schemas.employee import _validate_pay_fields

    if attendance_has_completion_pay(record):
        raise ValueError("This attendance already has a historical completion rate.")
    if not attendance_is_closed_punch(record):
        raise ValueError(
            "Only a completed attendance can receive a historical completion rate."
        )

    _validate_pay_fields(
        pay_basis=pay_basis,
        daily_rate=daily_rate,
        hourly_rate=hourly_rate,
        monthly_salary=monthly_salary,
    )

    record.pay_basis_at_completion = pay_basis
    if pay_basis == PayBasis.daily:
        record.daily_rate_at_completion = float(daily_rate) if daily_rate else None
        record.hourly_rate_at_completion = None
        record.monthly_salary_at_completion = None
    elif pay_basis == PayBasis.hourly:
        record.daily_rate_at_completion = None
        record.hourly_rate_at_completion = (
            float(hourly_rate) if hourly_rate else None
        )
        record.monthly_salary_at_completion = None
    else:
        record.daily_rate_at_completion = None
        record.hourly_rate_at_completion = None
        record.monthly_salary_at_completion = (
            float(monthly_salary) if monthly_salary else None
        )

    from sqlalchemy.orm.attributes import flag_modified

    flag_modified(record, "pay_basis_at_completion")
    flag_modified(record, "daily_rate_at_completion")
    flag_modified(record, "hourly_rate_at_completion")
    flag_modified(record, "monthly_salary_at_completion")


def stamp_attendance_completion_pay(
    record: Any,
    employee: Any,
    *,
    position: Position | None = None,
) -> bool:
    """Copy current Employee stamped rates onto the attendance once at close.

    Never overwrites an existing stamp (corrections keep the original rate).
    No-op when the punch is still open / incomplete. Returns True when stamped.
    """
    from app.models.enums import AttendanceStatus

    if attendance_has_completion_pay(record):
        return False
    if getattr(record, "time_in", None) is None:
        return False
    if getattr(record, "time_out", None) is None:
        return False
    status = getattr(record, "status", None)
    status_value = getattr(status, "value", status)
    if status_value in (
        AttendanceStatus.in_progress.value,
        AttendanceStatus.incomplete.value,
        None,
    ):
        return False

    resolved = resolve_employee_pay(employee, position=position)
    record.pay_basis_at_completion = resolved.pay_basis
    record.daily_rate_at_completion = resolved.daily_rate
    record.hourly_rate_at_completion = resolved.hourly_rate
    record.monthly_salary_at_completion = resolved.monthly_salary
    # Ensure SQLAlchemy persists Numeric/Enum stamps on already-loaded rows.
    from sqlalchemy.orm.attributes import flag_modified

    flag_modified(record, "pay_basis_at_completion")
    flag_modified(record, "daily_rate_at_completion")
    flag_modified(record, "hourly_rate_at_completion")
    flag_modified(record, "monthly_salary_at_completion")
    return True
