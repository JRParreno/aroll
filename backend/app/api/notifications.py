"""Centralized notification APIs for owners (employee-ready)."""

from __future__ import annotations

import uuid
from typing import Annotated

from fastapi import APIRouter, Depends, HTTPException, Query
from pydantic import BaseModel
from sqlalchemy.orm import Session

from app.core.deps import get_current_user, require_roles
from app.db.session import get_db
from app.models.enums import UserRole
from app.models.user import User
from app.services.notifications import (
    list_notifications,
    mark_all_read,
    mark_notification_read,
    serialize_notification,
    unread_count,
)

router = APIRouter(prefix="/notifications", tags=["notifications"])


class NotificationResponse(BaseModel):
    id: uuid.UUID
    business_id: uuid.UUID | None = None
    type: str
    title: str
    message: str
    entity_type: str | None = None
    entity_id: uuid.UUID | None = None
    deep_link: str | None = None
    is_read: bool
    metadata: dict | None = None
    created_at: object

    model_config = {"from_attributes": True}


class UnreadCountResponse(BaseModel):
    count: int


@router.get("", response_model=list[NotificationResponse])
def get_notifications(
    db: Annotated[Session, Depends(get_db)],
    user: Annotated[User, Depends(get_current_user)],
    unread_only: Annotated[bool, Query()] = False,
    limit: Annotated[int, Query(ge=1, le=100)] = 50,
):
    rows = list_notifications(
        db,
        recipient_user_id=user.id,
        unread_only=unread_only,
        limit=limit,
    )
    return [serialize_notification(row) for row in rows]


@router.get("/unread-count", response_model=UnreadCountResponse)
def get_unread_count(
    db: Annotated[Session, Depends(get_db)],
    user: Annotated[User, Depends(get_current_user)],
):
    return {"count": unread_count(db, recipient_user_id=user.id)}


@router.post("/{notification_id}/read", response_model=NotificationResponse)
def read_notification(
    notification_id: uuid.UUID,
    db: Annotated[Session, Depends(get_db)],
    user: Annotated[User, Depends(get_current_user)],
):
    row = mark_notification_read(
        db, recipient_user_id=user.id, notification_id=notification_id
    )
    if row is None:
        raise HTTPException(404, "Notification not found")
    return serialize_notification(row)


@router.post("/read-all")
def read_all_notifications(
    db: Annotated[Session, Depends(get_db)],
    user: Annotated[User, Depends(get_current_user)],
):
    count = mark_all_read(db, recipient_user_id=user.id)
    return {"marked_read": count}


# Keep role-gated alias for owners used by older clients if needed.
owner_router = APIRouter(prefix="/owner/notifications", tags=["owner-notifications"])


@owner_router.get("", response_model=list[NotificationResponse])
def owner_get_notifications(
    db: Annotated[Session, Depends(get_db)],
    user: Annotated[User, Depends(require_roles(UserRole.owner, UserRole.manager))],
    unread_only: Annotated[bool, Query()] = False,
    limit: Annotated[int, Query(ge=1, le=100)] = 50,
):
    return get_notifications(
        db=db, user=user, unread_only=unread_only, limit=limit
    )


@owner_router.get("/unread-count", response_model=UnreadCountResponse)
def owner_unread_count(
    db: Annotated[Session, Depends(get_db)],
    user: Annotated[User, Depends(require_roles(UserRole.owner, UserRole.manager))],
):
    return get_unread_count(db=db, user=user)


@owner_router.post("/{notification_id}/read", response_model=NotificationResponse)
def owner_read_notification(
    notification_id: uuid.UUID,
    db: Annotated[Session, Depends(get_db)],
    user: Annotated[User, Depends(require_roles(UserRole.owner, UserRole.manager))],
):
    return read_notification(
        notification_id=notification_id, db=db, user=user
    )


@owner_router.post("/read-all")
def owner_read_all_notifications(
    db: Annotated[Session, Depends(get_db)],
    user: Annotated[User, Depends(require_roles(UserRole.owner, UserRole.manager))],
):
    return read_all_notifications(db=db, user=user)
