"""Company Leave Policy — paid/unpaid treatment per leave type."""

from __future__ import annotations

import json
import uuid

from fastapi import HTTPException
from sqlalchemy.orm import Session

from app.models.enums import LeaveType
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
        "updated_at": policy.updated_at,
    }


def update_leave_policy(
    db: Session,
    *,
    business_id: uuid.UUID,
    treatments: dict[str, bool],
    actor: User,
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
    merged = normalize_treatments({**previous, **{k: bool(v) for k, v in treatments.items()}})
    if merged == previous:
        return policy

    policy.treatments = merged
    db.commit()
    db.refresh(policy)

    create_log(
        db,
        user_id=actor.id,
        action="leave_policy_updated",
        description="Updated company Leave Policy payroll treatments.",
        previous_value=json.dumps(previous),
        new_value=json.dumps(merged),
        platform=platform,
        device=device,
        ip_address=ip_address,
    )
    db.refresh(policy)
    return policy
