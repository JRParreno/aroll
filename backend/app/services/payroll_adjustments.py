"""Payroll adjustments applied after live payroll computation."""

from __future__ import annotations

import uuid
from datetime import date, datetime, timezone

from fastapi import HTTPException
from sqlalchemy.orm import Session

from app.models.payroll_adjustment import PayrollAdjustment

DEDUCTION_TYPES = {
    "broken_equipment": "Broken Equipment",
    "cash_shortage": "Cash Shortage",
    "uniform_damage": "Uniform Damage",
    "company_loan": "Company Loan",
    "cash_advance": "Cash Advance",
    "other": "Other",
}

ALLOWANCE_TYPES = {
    "meal_allowance": "Meal Allowance",
    "transportation_allowance": "Transportation Allowance",
    "internet_allowance": "Internet Allowance",
    "performance_bonus": "Performance Bonus",
    "incentive": "Incentive",
    "other": "Other",
}

KINDS = frozenset({"deduction", "allowance"})


def adjustments_editable(period_end: date, *, today: date | None = None) -> bool:
    """Editable until the pay period ends (no finalize action exists yet)."""
    return (today or date.today()) <= period_end


def display_name(row: PayrollAdjustment) -> str:
    if row.type_key == "other":
        custom = (row.custom_name or "").strip()
        return custom or "Other"
    catalog = DEDUCTION_TYPES if row.kind == "deduction" else ALLOWANCE_TYPES
    return catalog.get(row.type_key, row.type_key.replace("_", " ").title())


def serialize_adjustment(row: PayrollAdjustment) -> dict:
    return {
        "id": str(row.id),
        "employee_id": str(row.employee_id),
        "period_start": row.period_start.isoformat(),
        "period_end": row.period_end.isoformat(),
        "kind": row.kind,
        "type_key": row.type_key,
        "custom_name": row.custom_name,
        "display_name": display_name(row),
        "description": row.description,
        "amount": round(float(row.amount), 2),
        "created_by": str(row.created_by) if row.created_by else None,
        "created_at": row.created_at.isoformat() if row.created_at else None,
        "updated_by": str(row.updated_by) if row.updated_by else None,
        "updated_at": row.updated_at.isoformat() if row.updated_at else None,
        "previous_amount": (
            round(float(row.previous_amount), 2)
            if row.previous_amount is not None
            else None
        ),
    }


def list_active_adjustments(
    db: Session,
    *,
    business_id: uuid.UUID,
    employee_id: uuid.UUID,
    period_start: date,
    period_end: date,
) -> list[PayrollAdjustment]:
    return (
        db.query(PayrollAdjustment)
        .filter(
            PayrollAdjustment.business_id == business_id,
            PayrollAdjustment.employee_id == employee_id,
            PayrollAdjustment.period_start == period_start,
            PayrollAdjustment.period_end == period_end,
            PayrollAdjustment.deleted_at.is_(None),
        )
        .order_by(PayrollAdjustment.created_at.asc())
        .all()
    )


def list_active_adjustments_for_employees(
    db: Session,
    *,
    business_id: uuid.UUID,
    employee_ids: list[uuid.UUID],
    period_start: date,
    period_end: date,
) -> dict[uuid.UUID, list[PayrollAdjustment]]:
    if not employee_ids:
        return {}
    rows = (
        db.query(PayrollAdjustment)
        .filter(
            PayrollAdjustment.business_id == business_id,
            PayrollAdjustment.employee_id.in_(employee_ids),
            PayrollAdjustment.period_start == period_start,
            PayrollAdjustment.period_end == period_end,
            PayrollAdjustment.deleted_at.is_(None),
        )
        .order_by(PayrollAdjustment.created_at.asc())
        .all()
    )
    grouped: dict[uuid.UUID, list[PayrollAdjustment]] = {
        employee_id: [] for employee_id in employee_ids
    }
    for row in rows:
        grouped.setdefault(row.employee_id, []).append(row)
    return grouped


def totals_from_rows(rows: list[PayrollAdjustment]) -> tuple[float, float, float]:
    deduction_total = 0.0
    allowance_total = 0.0
    for row in rows:
        amount = float(row.amount)
        if row.kind == "allowance":
            allowance_total += amount
        else:
            deduction_total += amount
    net_adjustment = deduction_total - allowance_total
    return (
        round(deduction_total, 2),
        round(allowance_total, 2),
        round(net_adjustment, 2),
    )


def apply_adjustments_to_slip(
    slip: dict,
    rows: list[PayrollAdjustment],
    *,
    today: date | None = None,
) -> dict:
    """Attach adjustments and final_net_pay without mutating base net_pay math."""
    period_start = date.fromisoformat(str(slip["period_start"]))
    period_end = date.fromisoformat(str(slip["period_end"]))
    base_net = float(slip.get("net_pay") or 0)
    deduction_total, allowance_total, net_adjustment = totals_from_rows(rows)
    final_net = max(base_net - deduction_total + allowance_total, 0.0)
    editable = adjustments_editable(period_end, today=today)
    return {
        **slip,
        "base_net_pay": round(base_net, 2),
        "payroll_adjustments": [serialize_adjustment(row) for row in rows],
        "payroll_adjustments_deduction_total": deduction_total,
        "payroll_adjustments_allowance_total": allowance_total,
        "payroll_adjustments_total": net_adjustment,
        "final_net_pay": round(final_net, 2),
        "adjustments_editable": editable,
    }


def _validate_payload(
    *,
    kind: str,
    type_key: str,
    custom_name: str | None,
    amount: float,
) -> tuple[str, str, str | None, float]:
    kind_norm = (kind or "").strip().lower()
    if kind_norm not in KINDS:
        raise HTTPException(400, "Adjustment kind must be deduction or allowance")

    type_norm = (type_key or "").strip().lower()
    catalog = DEDUCTION_TYPES if kind_norm == "deduction" else ALLOWANCE_TYPES
    if type_norm not in catalog:
        raise HTTPException(400, "Invalid deduction/allowance type")

    custom = (custom_name or "").strip() or None
    if type_norm == "other" and not custom:
        raise HTTPException(400, "Custom name is required when type is Other")
    if type_norm != "other":
        custom = None

    try:
        amount_value = float(amount)
    except (TypeError, ValueError) as exc:
        raise HTTPException(400, "Amount must be a number") from exc
    if amount_value <= 0:
        raise HTTPException(400, "Amount must be greater than zero")

    return kind_norm, type_norm, custom, round(amount_value, 2)


def create_adjustment(
    db: Session,
    *,
    business_id: uuid.UUID,
    employee_id: uuid.UUID,
    period_start: date,
    period_end: date,
    kind: str,
    type_key: str,
    custom_name: str | None,
    description: str | None,
    amount: float,
    actor_id: uuid.UUID | None,
) -> PayrollAdjustment:
    if not adjustments_editable(period_end):
        raise HTTPException(
            400, "Payroll adjustments are read-only after the pay period ends"
        )
    kind_norm, type_norm, custom, amount_value = _validate_payload(
        kind=kind,
        type_key=type_key,
        custom_name=custom_name,
        amount=amount,
    )
    row = PayrollAdjustment(
        business_id=business_id,
        employee_id=employee_id,
        period_start=period_start,
        period_end=period_end,
        kind=kind_norm,
        type_key=type_norm,
        custom_name=custom,
        description=(description or "").strip() or None,
        amount=amount_value,
        created_by=actor_id,
    )
    db.add(row)
    db.commit()
    db.refresh(row)
    return row


def update_adjustment(
    db: Session,
    *,
    business_id: uuid.UUID,
    adjustment_id: uuid.UUID,
    kind: str | None = None,
    type_key: str | None = None,
    custom_name: str | None = None,
    description: str | None = None,
    amount: float | None = None,
    actor_id: uuid.UUID | None = None,
) -> PayrollAdjustment:
    row = (
        db.query(PayrollAdjustment)
        .filter(
            PayrollAdjustment.id == adjustment_id,
            PayrollAdjustment.business_id == business_id,
            PayrollAdjustment.deleted_at.is_(None),
        )
        .first()
    )
    if row is None:
        raise HTTPException(404, "Payroll adjustment not found")
    if not adjustments_editable(row.period_end):
        raise HTTPException(
            400, "Payroll adjustments are read-only after the pay period ends"
        )

    next_kind = kind if kind is not None else row.kind
    next_type = type_key if type_key is not None else row.type_key
    next_custom = custom_name if custom_name is not None else row.custom_name
    next_amount = float(amount) if amount is not None else float(row.amount)
    kind_norm, type_norm, custom, amount_value = _validate_payload(
        kind=next_kind,
        type_key=next_type,
        custom_name=next_custom,
        amount=next_amount,
    )

    if abs(float(row.amount) - amount_value) > 0.0001:
        row.previous_amount = float(row.amount)

    row.kind = kind_norm
    row.type_key = type_norm
    row.custom_name = custom
    if description is not None:
        row.description = description.strip() or None
    row.amount = amount_value
    row.updated_by = actor_id
    row.updated_at = datetime.now(timezone.utc)
    db.commit()
    db.refresh(row)
    return row


def soft_delete_adjustment(
    db: Session,
    *,
    business_id: uuid.UUID,
    adjustment_id: uuid.UUID,
    actor_id: uuid.UUID | None,
) -> None:
    row = (
        db.query(PayrollAdjustment)
        .filter(
            PayrollAdjustment.id == adjustment_id,
            PayrollAdjustment.business_id == business_id,
            PayrollAdjustment.deleted_at.is_(None),
        )
        .first()
    )
    if row is None:
        raise HTTPException(404, "Payroll adjustment not found")
    if not adjustments_editable(row.period_end):
        raise HTTPException(
            400, "Payroll adjustments are read-only after the pay period ends"
        )
    row.deleted_at = datetime.now(timezone.utc)
    row.deleted_by = actor_id
    db.commit()


def preset_catalog() -> dict:
    return {
        "deduction_types": [
            {"key": key, "label": label} for key, label in DEDUCTION_TYPES.items()
        ],
        "allowance_types": [
            {"key": key, "label": label} for key, label in ALLOWANCE_TYPES.items()
        ],
    }
