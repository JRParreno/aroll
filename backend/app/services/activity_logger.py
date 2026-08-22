from __future__ import annotations

from sqlalchemy.orm import Session

from app.models.activity_log import ActivityLog


def create_log(
    db: Session,
    user_id,
    action: str,
    description: str | None = None,
    *,
    previous_value: str | None = None,
    new_value: str | None = None,
    platform: str | None = None,
    device: str | None = None,
    ip_address: str | None = None,
):
    log = ActivityLog(
        user_id=user_id,
        action=action,
        description=(description or "")[:500],
        previous_value=previous_value,
        new_value=new_value,
        platform=(platform or None) and platform[:40],
        device=(device or None) and device[:120],
        ip_address=(ip_address or None) and ip_address[:64],
    )

    db.add(log)
    db.commit()
    db.refresh(log)

    return log
