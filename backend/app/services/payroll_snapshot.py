"""Immutable payslip snapshots written at payroll finalization.

Unfinalized payroll still uses live `_calculate_employee_payslip`. This module
serializes that existing result (after adjustments) into Payslip rows and
loads either the frozen snapshot or the live calculation on retrieval.
It does not recalculate payroll from current settings when a snapshot exists.
"""

from __future__ import annotations

import json
import uuid
from collections.abc import Callable, Sequence
from dataclasses import dataclass
from datetime import date, datetime
from decimal import Decimal
from typing import Any

from fastapi import HTTPException
from sqlalchemy.orm import Session

from app.models.attendance_policy import BusinessAttendancePolicy
from app.models.employee import Employee
from app.models.enums import PayrollRunStatus
from app.models.payroll import BusinessPayrollConfig, Payslip, PayrollRun
from app.models.rest_day_policy import BusinessRestDayPolicy
from app.services.holiday_pay import resolve_holiday_rules_mode
from app.services.pay_period import resolve_pay_period
from app.services.payroll_adjustments import (
    apply_adjustments_to_slip,
    list_active_adjustments,
    list_active_adjustments_for_employees,
)
from app.services.payroll_engine import hours_worked_from_slip

PAYSLIP_SNAPSHOT_VERSION = 1

PayslipCalculator = Callable[[Session, Employee, date, date], dict]


def _json_default(value: Any) -> Any:
    if isinstance(value, Decimal):
        return float(value)
    if isinstance(value, uuid.UUID):
        return str(value)
    if isinstance(value, (datetime, date)):
        return value.isoformat()
    raise TypeError(f"Object of type {type(value).__name__} is not JSON serializable")


def freeze_payslip_dict(slip: dict) -> dict:
    """JSON-safe copy of the live payslip, tagged with the snapshot version."""
    frozen = json.loads(json.dumps(slip, default=_json_default))
    frozen["snapshot_version"] = PAYSLIP_SNAPSHOT_VERSION
    return frozen


def payslip_summary_values(slip: dict) -> dict[str, float]:
    """Map existing payslip fields onto the typed Payslip columns."""
    overtime_hours = slip.get("overtime_hours")
    if overtime_hours is None:
        overtime_hours = 0.0
    deductions = slip.get("deductions")
    if deductions is None:
        deductions = 0.0
    gross = slip.get("gross_pay")
    if gross is None:
        gross = 0.0
    final_net = slip.get("final_net_pay")
    if final_net is None:
        final_net = slip.get("net_pay") or 0.0
    return {
        "regular_hours": hours_worked_from_slip(slip),
        "overtime_hours": round(float(overtime_hours), 2),
        "gross_pay": round(float(gross), 2),
        "total_deductions": round(float(deductions), 2),
        "net_pay": round(float(final_net), 2),
    }


def payslip_row_from_slip(
    *,
    payroll_run_id: uuid.UUID,
    employee_id: uuid.UUID | None,
    slip: dict,
) -> Payslip:
    summary = payslip_summary_values(slip)
    return Payslip(
        payroll_run_id=payroll_run_id,
        employee_id=employee_id,
        regular_hours=summary["regular_hours"],
        overtime_hours=summary["overtime_hours"],
        gross_pay=summary["gross_pay"],
        total_deductions=summary["total_deductions"],
        net_pay=summary["net_pay"],
        breakdown_json=freeze_payslip_dict(slip),
    )


def _optional_float(value: Any) -> float | None:
    if value is None:
        return None
    try:
        return float(value)
    except (TypeError, ValueError):
        return None


def build_calculation_config_json(db: Session, business_id: uuid.UUID) -> dict:
    """Audit-only business flags at finalize time. Not used to recalculate."""
    config = db.get(BusinessPayrollConfig, business_id)
    att_policy = db.get(BusinessAttendancePolicy, business_id)
    rest_policy = db.get(BusinessRestDayPolicy, business_id)
    holiday_mode = resolve_holiday_rules_mode(config)
    return {
        "snapshot_version": PAYSLIP_SNAPSHOT_VERSION,
        "enable_late_overtime_balancing": bool(
            config is not None
            and getattr(config, "enable_late_overtime_balancing", False)
        ),
        "breaktime_is_paid": bool(
            att_policy is not None
            and getattr(att_policy, "breaktime_is_paid", False)
        ),
        "overtime_enabled": bool(
            (config is None or bool(getattr(config, "overtime_enabled", True)))
            and (
                att_policy is None
                or bool(getattr(att_policy, "overtime_enabled", True))
            )
        ),
        "overtime_per_minute": _optional_float(
            getattr(config, "overtime_per_minute", None) if config is not None else None
        ),
        "overtime_minimum_minutes": getattr(
            att_policy, "overtime_minimum_minutes", None
        )
        if att_policy is not None
        else None,
        "late_deduction_enabled": (
            True
            if config is None
            else bool(getattr(config, "late_deduction_enabled", True))
        ),
        "late_deduction_per_minute": _optional_float(
            getattr(config, "late_deduction_per_minute", None)
            if config is not None
            else None
        ),
        "on_time_grace_minutes": getattr(
            att_policy, "on_time_grace_minutes", None
        )
        if att_policy is not None
        else None,
        "holiday_rules_mode": holiday_mode.value,
        "rest_day_premium_percent": _optional_float(
            getattr(rest_policy, "rest_day_premium_percent", None)
            if rest_policy is not None
            else None
        )
        or 0.0,
    }


def create_finalized_payslip_snapshots(
    db: Session,
    *,
    run: PayrollRun,
    employees: Sequence[Employee],
    period_start: date,
    period_end: date,
    calculate_payslip: PayslipCalculator,
) -> list[Payslip]:
    """Insert one Payslip per employee from the live post-adjustment result."""
    adjustment_map = list_active_adjustments_for_employees(
        db,
        business_id=run.business_id,
        employee_ids=[employee.id for employee in employees],
        period_start=period_start,
        period_end=period_end,
    )
    rows: list[Payslip] = []
    for employee in employees:
        slip = apply_adjustments_to_slip(
            calculate_payslip(db, employee, period_start, period_end),
            adjustment_map.get(employee.id, []),
        )
        row = payslip_row_from_slip(
            payroll_run_id=run.id,
            employee_id=employee.id,
            slip=slip,
        )
        db.add(row)
        rows.append(row)
    return rows


@dataclass(frozen=True)
class PayslipLoad:
    """One employee payslip for a pay period.

    ``slip`` is None when a Phase 1 snapshot period exists but this employee
    has no Payslip row. Callers must not live-calculate in that case.
    """

    slip: dict | None
    period_start: date
    period_end: date
    from_snapshot: bool
    payroll_run: PayrollRun | None


@dataclass(frozen=True)
class PeriodPayrollLoad:
    """Owner payroll-report payload source for one period."""

    period_start: date
    period_end: date
    from_snapshot: bool
    payroll_run: PayrollRun | None
    entries: list[tuple[Employee | None, dict]]


def _copy_slip(data: dict) -> dict:
    return json.loads(json.dumps(data, default=_json_default))


def snapshot_payslip_dict(row: Payslip) -> dict | None:
    """Return a frozen API payslip from breakdown_json, or None if unusable."""
    data = row.breakdown_json
    if not isinstance(data, dict) or not data:
        return None
    slip = _copy_slip(data)
    slip["adjustments_editable"] = False
    return slip


def find_snapshot_run(
    db: Session,
    *,
    business_id: uuid.UUID,
    as_of: date,
) -> PayrollRun | None:
    """Finalized Phase 1 run whose stored period contains as_of.

    Date containment is applied in Python so current pay-period config is not
    used to locate historical snapshots.
    """
    runs = (
        db.query(PayrollRun)
        .filter(
            PayrollRun.business_id == business_id,
            PayrollRun.status == PayrollRunStatus.finalized,
            PayrollRun.snapshot_version == PAYSLIP_SNAPSHOT_VERSION,
        )
        .order_by(PayrollRun.created_at.desc())
        .all()
    )
    for run in runs:
        if run.period_start <= as_of <= run.period_end:
            return run
    return None


def find_finalized_run_for_period(
    db: Session,
    *,
    business_id: uuid.UUID,
    period_start: date,
    period_end: date,
) -> PayrollRun | None:
    return (
        db.query(PayrollRun)
        .filter(
            PayrollRun.business_id == business_id,
            PayrollRun.period_start == period_start,
            PayrollRun.period_end == period_end,
            PayrollRun.status == PayrollRunStatus.finalized,
        )
        .order_by(PayrollRun.created_at.desc())
        .first()
    )


def mark_payroll_run_unfinalized(run: PayrollRun) -> PayrollRun:
    """Reopen a finalized run without deleting its historical payslip rows.

    ``cancelled`` is the existing schema status that is not treated as the
    active snapshot. Payslip.breakdown_json stays attached to this run.
    """
    run.status = PayrollRunStatus.cancelled
    return run


def unfinalize_period_for_as_of(
    db: Session,
    *,
    business_id: uuid.UUID,
    as_of: date,
) -> tuple[PayrollRun, date, date]:
    """Cancel the active finalized run currently shown for ``as_of``.

    Uses the same period resolution as owner/employee payroll reads so the
    snapshot being viewed is the one that is reopened.
    """
    period_start, period_end, run, _snapshot_mode = resolve_view_period(
        db,
        business_id=business_id,
        as_of=as_of,
    )
    if run is None or run.status != PayrollRunStatus.finalized:
        raise HTTPException(
            status_code=400,
            detail={
                "code": "payroll_not_finalized",
                "message": "This payroll period is not finalized.",
                "period_start": period_start.isoformat(),
                "period_end": period_end.isoformat(),
            },
        )
    siblings = (
        db.query(PayrollRun)
        .filter(
            PayrollRun.business_id == business_id,
            PayrollRun.period_start == period_start,
            PayrollRun.period_end == period_end,
            PayrollRun.status == PayrollRunStatus.finalized,
        )
        .all()
    )
    for sibling in siblings:
        mark_payroll_run_unfinalized(sibling)
    if run.status == PayrollRunStatus.finalized:
        mark_payroll_run_unfinalized(run)
    return run, period_start, period_end


def payslips_for_run(db: Session, run: PayrollRun) -> list[Payslip]:
    return (
        db.query(Payslip)
        .filter(Payslip.payroll_run_id == run.id)
        .all()
    )


def resolve_view_period(
    db: Session,
    *,
    business_id: uuid.UUID,
    as_of: date | None = None,
) -> tuple[date, date, PayrollRun | None, bool]:
    """Resolve the period to display for as_of.

    Snapshot runs win by date containment. Otherwise use live pay-period
    config (and any exact-match legacy finalized run).
    """
    as_of = as_of or date.today()
    snapshot_run = find_snapshot_run(db, business_id=business_id, as_of=as_of)
    if snapshot_run is not None:
        return (
            snapshot_run.period_start,
            snapshot_run.period_end,
            snapshot_run,
            True,
        )
    config = db.get(BusinessPayrollConfig, business_id)
    period_start, period_end = resolve_pay_period(config, today=as_of)
    legacy = find_finalized_run_for_period(
        db,
        business_id=business_id,
        period_start=period_start,
        period_end=period_end,
    )
    return period_start, period_end, legacy, False


def _match_payslip_by_employee_id(
    rows: Sequence[Payslip],
    employee_id: uuid.UUID,
) -> Payslip | None:
    emp_key = str(employee_id)
    for row in rows:
        if row.employee_id == employee_id:
            return row
        payload = row.breakdown_json if isinstance(row.breakdown_json, dict) else {}
        if str(payload.get("employee_id") or "") == emp_key:
            return row
    return None


def require_loaded_slip(loaded: PayslipLoad) -> dict:
    """Return the payslip dict, or 404 when a snapshot period has no row."""
    if loaded.slip is None:
        raise HTTPException(
            status_code=404,
            detail={
                "code": "payslip_snapshot_unavailable",
                "message": (
                    "No finalized payslip snapshot exists for this employee "
                    "in the selected period."
                ),
                "period_start": loaded.period_start.isoformat(),
                "period_end": loaded.period_end.isoformat(),
            },
        )
    return loaded.slip


def _live_employee_payslip(
    db: Session,
    employee: Employee,
    period_start: date,
    period_end: date,
    calculate_payslip: PayslipCalculator,
) -> dict:
    return apply_adjustments_to_slip(
        calculate_payslip(db, employee, period_start, period_end),
        list_active_adjustments(
            db,
            business_id=employee.business_id,
            employee_id=employee.id,
            period_start=period_start,
            period_end=period_end,
        ),
    )


def load_period_payslip_for_employee_id(
    db: Session,
    *,
    business_id: uuid.UUID,
    employee_id: uuid.UUID,
    as_of: date | None = None,
    calculate_payslip: PayslipCalculator,
    employee: Employee | None = None,
) -> PayslipLoad:
    """Load a payslip scoped to ``business_id``.

    Phase 1 snapshot periods never fall back to live calculation when the
    employee has no Payslip row. Live calculation requires a live Employee.
    """
    period_start, period_end, run, snapshot_mode = resolve_view_period(
        db,
        business_id=business_id,
        as_of=as_of,
    )
    if snapshot_mode and run is not None:
        row = _match_payslip_by_employee_id(payslips_for_run(db, run), employee_id)
        frozen = snapshot_payslip_dict(row) if row is not None else None
        return PayslipLoad(
            slip=frozen,
            period_start=period_start,
            period_end=period_end,
            from_snapshot=True,
            payroll_run=run,
        )
    if employee is None:
        return PayslipLoad(
            slip=None,
            period_start=period_start,
            period_end=period_end,
            from_snapshot=False,
            payroll_run=run,
        )
    slip = _live_employee_payslip(
        db, employee, period_start, period_end, calculate_payslip
    )
    return PayslipLoad(
        slip=slip,
        period_start=period_start,
        period_end=period_end,
        from_snapshot=False,
        payroll_run=run,
    )


def load_period_payslip(
    db: Session,
    employee: Employee,
    *,
    as_of: date | None = None,
    calculate_payslip: PayslipCalculator,
) -> PayslipLoad:
    """Return the snapshot payslip when one exists; otherwise live calculation."""
    return load_period_payslip_for_employee_id(
        db,
        business_id=employee.business_id,
        employee_id=employee.id,
        as_of=as_of,
        calculate_payslip=calculate_payslip,
        employee=employee,
    )


def _employee_uuid(value: Any) -> uuid.UUID | None:
    if isinstance(value, uuid.UUID):
        return value
    try:
        return uuid.UUID(str(value))
    except (TypeError, ValueError, AttributeError):
        return None


def load_period_payroll(
    db: Session,
    *,
    business_id: uuid.UUID,
    as_of: date | None = None,
    calculate_payslip: PayslipCalculator,
) -> PeriodPayrollLoad:
    """Owner report source: snapshot rows or live active-employee calculation."""
    period_start, period_end, run, snapshot_mode = resolve_view_period(
        db,
        business_id=business_id,
        as_of=as_of,
    )
    if snapshot_mode and run is not None:
        entries: list[tuple[Employee | None, dict]] = []
        for row in payslips_for_run(db, run):
            slip = snapshot_payslip_dict(row)
            if slip is None:
                continue
            employee = None
            emp_id = row.employee_id or _employee_uuid(slip.get("employee_id"))
            if emp_id is not None:
                employee = db.get(Employee, emp_id)
            entries.append((employee, slip))
        entries.sort(
            key=lambda item: str(
                item[1].get("employee_name") or ""
            ).lower()
        )
        return PeriodPayrollLoad(
            period_start=period_start,
            period_end=period_end,
            from_snapshot=True,
            payroll_run=run,
            entries=entries,
        )

    employees = (
        db.query(Employee)
        .filter(Employee.business_id == business_id, Employee.is_active.is_(True))
        .order_by(Employee.full_name)
        .all()
    )
    adjustment_map = list_active_adjustments_for_employees(
        db,
        business_id=business_id,
        employee_ids=[employee.id for employee in employees],
        period_start=period_start,
        period_end=period_end,
    )
    live_entries: list[tuple[Employee | None, dict]] = []
    for employee in employees:
        slip = apply_adjustments_to_slip(
            calculate_payslip(db, employee, period_start, period_end),
            adjustment_map.get(employee.id, []),
        )
        live_entries.append((employee, slip))
    return PeriodPayrollLoad(
        period_start=period_start,
        period_end=period_end,
        from_snapshot=False,
        payroll_run=run,
        entries=live_entries,
    )
