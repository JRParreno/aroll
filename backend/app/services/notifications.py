"""Centralized in-app notifications for owners and (future) employees."""

from __future__ import annotations

import json
import uuid
from typing import Any

from sqlalchemy.orm import Session

from app.models.enums import UserRole
from app.models.notification import Notification
from app.models.user import User

# Stable type keys — keep additive for future payroll/schedule/holiday events.
NOTIFICATION_TYPES = {
    "leave_submitted",
    "leave_updated",
    "leave_cancelled",
    "leave_cancellation_requested",
    "leave_approved",
    "leave_rejected",
    "leave_cancellation_approved",
    "leave_cancellation_rejected",
    "attendance_correction_submitted",
    "attendance_correction_approved",
    "attendance_correction_rejected",
    "incomplete_attendance",
    "employee_of_the_month",
    "payroll_generated",
    "schedule_conflict",
    "business_setup_reminder",
    "schedule_updated",
    "holiday_announcement",
}


def notification_exists_for_entity(
    db: Session,
    *,
    type: str,
    entity_type: str,
    entity_id: uuid.UUID,
    recipient_user_id: uuid.UUID | None = None,
) -> bool:
    """True when a notification for this entity/type already exists (dedupe)."""
    query = db.query(Notification.id).filter(
        Notification.type == type,
        Notification.entity_type == entity_type,
        Notification.entity_id == entity_id,
    )
    if recipient_user_id is not None:
        query = query.filter(Notification.recipient_user_id == recipient_user_id)
    return query.first() is not None


def _owner_users(db: Session, business_id: uuid.UUID) -> list[User]:
    return (
        db.query(User)
        .filter(
            User.business_id == business_id,
            User.role.in_([UserRole.owner, UserRole.manager]),
            User.is_active.is_(True),
        )
        .all()
    )


def create_notification(
    db: Session,
    *,
    recipient_user_id: uuid.UUID,
    recipient_role: str,
    type: str,
    title: str,
    message: str,
    business_id: uuid.UUID | None = None,
    entity_type: str | None = None,
    entity_id: uuid.UUID | None = None,
    deep_link: str | None = None,
    metadata: dict[str, Any] | None = None,
    commit: bool = True,
) -> Notification:
    row = Notification(
        business_id=business_id,
        recipient_user_id=recipient_user_id,
        recipient_role=recipient_role,
        type=type,
        title=title[:160],
        message=message[:280],
        entity_type=entity_type,
        entity_id=entity_id,
        deep_link=deep_link,
        metadata_json=json.dumps(metadata) if metadata else None,
        is_read=False,
    )
    db.add(row)
    if commit:
        db.commit()
        db.refresh(row)
    else:
        db.flush()
    return row


def notify_business_owners(
    db: Session,
    *,
    business_id: uuid.UUID,
    type: str,
    title: str,
    message: str,
    entity_type: str | None = None,
    entity_id: uuid.UUID | None = None,
    deep_link: str | None = None,
    metadata: dict[str, Any] | None = None,
) -> int:
    owners = _owner_users(db, business_id)
    for user in owners:
        create_notification(
            db,
            business_id=business_id,
            recipient_user_id=user.id,
            recipient_role=user.role.value,
            type=type,
            title=title,
            message=message,
            entity_type=entity_type,
            entity_id=entity_id,
            deep_link=deep_link,
            metadata=metadata,
            commit=False,
        )
    if owners:
        db.commit()
    return len(owners)


def notify_user(
    db: Session,
    *,
    user: User,
    type: str,
    title: str,
    message: str,
    entity_type: str | None = None,
    entity_id: uuid.UUID | None = None,
    deep_link: str | None = None,
    metadata: dict[str, Any] | None = None,
) -> Notification:
    return create_notification(
        db,
        business_id=user.business_id,
        recipient_user_id=user.id,
        recipient_role=user.role.value,
        type=type,
        title=title,
        message=message,
        entity_type=entity_type,
        entity_id=entity_id,
        deep_link=deep_link,
        metadata=metadata,
    )


def notify_user_once(
    db: Session,
    *,
    user: User,
    type: str,
    title: str,
    message: str,
    entity_type: str,
    entity_id: uuid.UUID,
    deep_link: str | None = None,
    metadata: dict[str, Any] | None = None,
) -> Notification | None:
    """Create a user notification only if one does not already exist for entity."""
    if notification_exists_for_entity(
        db,
        type=type,
        entity_type=entity_type,
        entity_id=entity_id,
        recipient_user_id=user.id,
    ):
        return None
    return notify_user(
        db,
        user=user,
        type=type,
        title=title,
        message=message,
        entity_type=entity_type,
        entity_id=entity_id,
        deep_link=deep_link,
        metadata=metadata,
    )


def list_notifications(
    db: Session,
    *,
    recipient_user_id: uuid.UUID,
    unread_only: bool = False,
    limit: int = 50,
) -> list[Notification]:
    query = db.query(Notification).filter(
        Notification.recipient_user_id == recipient_user_id
    )
    if unread_only:
        query = query.filter(Notification.is_read.is_(False))
    return (
        query.order_by(Notification.created_at.desc())
        .limit(max(1, min(limit, 100)))
        .all()
    )


def unread_count(db: Session, *, recipient_user_id: uuid.UUID) -> int:
    return (
        db.query(Notification)
        .filter(
            Notification.recipient_user_id == recipient_user_id,
            Notification.is_read.is_(False),
        )
        .count()
    )


def mark_notification_read(
    db: Session,
    *,
    recipient_user_id: uuid.UUID,
    notification_id: uuid.UUID,
) -> Notification | None:
    row = (
        db.query(Notification)
        .filter(
            Notification.id == notification_id,
            Notification.recipient_user_id == recipient_user_id,
        )
        .first()
    )
    if row is None:
        return None
    row.is_read = True
    db.commit()
    db.refresh(row)
    return row


def mark_all_read(db: Session, *, recipient_user_id: uuid.UUID) -> int:
    rows = (
        db.query(Notification)
        .filter(
            Notification.recipient_user_id == recipient_user_id,
            Notification.is_read.is_(False),
        )
        .all()
    )
    for row in rows:
        row.is_read = True
    db.commit()
    return len(rows)


def serialize_notification(row: Notification) -> dict:
    metadata = None
    if row.metadata_json:
        try:
            metadata = json.loads(row.metadata_json)
        except json.JSONDecodeError:
            metadata = None
    return {
        "id": row.id,
        "business_id": row.business_id,
        "type": row.type,
        "title": row.title,
        "message": row.message,
        "entity_type": row.entity_type,
        "entity_id": row.entity_id,
        "deep_link": row.deep_link,
        "is_read": row.is_read,
        "metadata": metadata,
        "created_at": row.created_at,
    }
