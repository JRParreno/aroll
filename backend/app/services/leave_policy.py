"""Company Leave Policy — paid/unpaid treatment per leave type."""

from __future__ import annotations

import json
import uuid

from fastapi import HTTPException
from sqlalchemy.orm import Session

from app.models.enums import LeaveType
from app.models.leave_allowance import BusinessLeaveAllowance
from app.models.leave_policy import BusinessLeavePolicy
from app.models.user import User
from app.services.activity_logger import create_log

# Seeded defaults — editable per business; not runtime hardcoding.
DEFAULT_LEAVE_TREATMENTS: dict[str, bool] = {
    LeaveType.sick.value: True,
    LeaveType.vacation.value: True,
    LeaveType.emergency.value: False,
    LeaveType.maternity.value: True,
    LeaveType.paternity.value: True,
    LeaveType.unpaid.value: False,
    LeaveType.other.value: False,
}

_LEAVE_TYPE_LABELS: dict[LeaveType, str] = {
    LeaveType.sick: "Sick Leave",
    LeaveType.vacation: "Vacation Leave",
    LeaveType.emergency: "Emergency Leave",
    LeaveType.maternity: "Maternity Leave",
    LeaveType.paternity: "Paternity Leave",
    LeaveType.unpaid: "Unpaid Leave",
    LeaveType.other: "Other",
}


def default_treatments() -> dict[str, bool]:
    return dict(DEFAULT_LEAVE_TREATMENTS)


def normalize_treatments(raw: dict | None) -> dict[str, bool]:
    base = default_treatments()
    if not raw:
        return base
    for leave_type in LeaveType:
        key = leave_type.value
        if key in raw:
            base[key] = bool(raw[key])
    return base


def get_or_create_leave_policy(
    db: Session, business_id: uuid.UUID
) -> BusinessLeavePolicy:
    policy = db.get(BusinessLeavePolicy, business_id)
    if policy is not None:
        # Keep map complete if new leave types are added later.
        normalized = normalize_treatments(policy.treatments)
        if policy.treatments != normalized:
            policy.treatments = normalized
            db.commit()
            db.refresh(policy)
        return policy

    policy = BusinessLeavePolicy(
        business_id=business_id,
        treatments=default_treatments(),
        config_json={},
    )
    db.add(policy)
    db.commit()
    db.refresh(policy)
    return policy


def is_leave_type_paid_for_business(
    db: Session,
    *,
    business_id: uuid.UUID,
    leave_type: LeaveType,
) -> bool:
    policy = get_or_create_leave_policy(db, business_id)
    treatments = normalize_treatments(policy.treatments)
    return bool(treatments.get(leave_type.value, leave_type != LeaveType.unpaid))


def serialize_leave_policy(policy: BusinessLeavePolicy) -> dict:
    treatments = normalize_treatments(policy.treatments)
    items = []
    for leave_type in LeaveType:
        paid = bool(treatments[leave_type.value])
        items.append(
            {
                "leave_type": leave_type.value,
                "leave_type_label": _LEAVE_TYPE_LABELS.get(
                    leave_type, leave_type.value
                ),
                "is_paid": paid,
                "payroll_treatment": "paid" if paid else "unpaid",
            }
        )
    return {
        "business_id": policy.business_id,
        "items": items,
        "treatments": treatments,
        "minimum_advance_notice_days": int(policy.minimum_advance_notice_days or 0),
        "updated_at": policy.updated_at,
    }


def update_leave_policy(
    db: Session,
    *,
    business_id: uuid.UUID,
    treatments: dict[str, bool],
    actor: User,
    minimum_advance_notice_days: int | None = None,
    platform: str | None = None,
    device: str | None = None,
    ip_address: str | None = None,
) -> BusinessLeavePolicy:
    unknown = set(treatments.keys()) - {lt.value for lt in LeaveType}
    if unknown:
        raise HTTPException(
            400,
            f"Unknown leave type(s): {', '.join(sorted(unknown))}",
        )

    policy = get_or_create_leave_policy(db, business_id)
    previous = normalize_treatments(policy.treatments)
    previous_notice = int(policy.minimum_advance_notice_days or 0)
    merged = normalize_treatments({**previous, **{k: bool(v) for k, v in treatments.items()}})
    next_notice = previous_notice
    if minimum_advance_notice_days is not None:
        next_notice = int(minimum_advance_notice_days)
        if next_notice < 0 or next_notice > 365:
            raise HTTPException(
                400,
                "Minimum advance notice must be between 0 and 365 days.",
            )
    if merged == previous and next_notice == previous_notice:
        return policy

    policy.treatments = merged
    policy.minimum_advance_notice_days = next_notice
    db.commit()
    db.refresh(policy)

    create_log(
        db,
        user_id=actor.id,
        action="leave_policy_updated",
        description="Updated company Leave Policy payroll treatments.",
        previous_value=json.dumps(
            {
                "treatments": previous,
                "minimum_advance_notice_days": previous_notice,
            }
        ),
        new_value=json.dumps(
            {
                "treatments": merged,
                "minimum_advance_notice_days": next_notice,
            }
        ),
        platform=platform,
        device=device,
        ip_address=ip_address,
    )
    db.refresh(policy)
    return policy


def _allowance_label(leave_type: LeaveType) -> str:
    return _LEAVE_TYPE_LABELS.get(leave_type, leave_type.value)


def list_leave_allowances(
    db: Session, *, business_id: uuid.UUID, year: int
) -> list[dict]:
    rows = (
        db.query(BusinessLeaveAllowance)
        .filter(
            BusinessLeaveAllowance.business_id == business_id,
            BusinessLeaveAllowance.year == year,
        )
        .all()
    )
    by_type = {row.leave_type: row for row in rows}
    items = []
    for leave_type in LeaveType:
        row = by_type.get(leave_type)
        enabled = bool(row is not None and row.enabled)
        items.append(
            {
                "leave_type": leave_type.value,
                "leave_type_label": _allowance_label(leave_type),
                "enabled": enabled,
                "disabled": row is not None and not row.enabled,
                "configured": enabled,
                "allowance_days": int(row.allowance_days)
                if enabled and row is not None and row.allowance_days is not None
                else None,
            }
        )
    return items


def replace_leave_allowances(
    db: Session,
    *,
    business_id: uuid.UUID,
    year: int,
    items: list[dict],
    actor: User,
    platform: str | None = None,
    device: str | None = None,
    ip_address: str | None = None,
) -> list[dict]:
    """Upsert business allowances for one year.

    Omitted leave types are left unchanged. An enabled item requires
    allowance days. A disabled item stores no allowance days.
    """
    if year < 2000 or year > 2100:
        raise HTTPException(400, "Allowance year is out of range.")

    seen: set[LeaveType] = set()
    for item in items:
        leave_type = item["leave_type"]
        if not isinstance(leave_type, LeaveType):
            leave_type = LeaveType(leave_type)
        if leave_type in seen:
            raise HTTPException(400, "Each leave type can only be set once.")
        seen.add(leave_type)
        enabled = bool(item["enabled"])
        allowance = item.get("allowance_days")
        if enabled:
            if allowance is None or int(allowance) < 0 or int(allowance) > 366:
                raise HTTPException(
                    400,
                    "Allowance days must be between 0 and 366 when a leave type is available.",
                )
            allowance = int(allowance)
        else:
            allowance = None

        row = (
            db.query(BusinessLeaveAllowance)
            .filter(
                BusinessLeaveAllowance.business_id == business_id,
                BusinessLeaveAllowance.leave_type == leave_type,
                BusinessLeaveAllowance.year == year,
            )
            .with_for_update()
            .one_or_none()
        )
        if row is None:
            db.add(
                BusinessLeaveAllowance(
                    business_id=business_id,
                    leave_type=leave_type,
                    year=year,
                    enabled=enabled,
                    allowance_days=allowance,
                )
            )
        else:
            row.enabled = enabled
            row.allowance_days = allowance

    db.commit()
    saved = list_leave_allowances(db, business_id=business_id, year=year)
    create_log(
        db,
        user_id=actor.id,
        action="leave_allowance_updated",
        description=f"Updated {year} business leave allowances.",
        new_value=json.dumps(
            {
                "year": year,
                "items": [
                    {
                        "leave_type": item["leave_type"].value
                        if isinstance(item["leave_type"], LeaveType)
                        else item["leave_type"],
                        "enabled": bool(item["enabled"]),
                        "allowance_days": item.get("allowance_days")
                        if item["enabled"]
                        else None,
                    }
                    for item in items
                ],
            }
        ),
        platform=platform,
        device=device,
        ip_address=ip_address,
    )
    return saved
