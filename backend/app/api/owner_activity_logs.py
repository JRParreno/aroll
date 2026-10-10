"""Owner-scoped read-only activity / audit history."""

from __future__ import annotations

import uuid
from typing import Annotated

from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy import and_, or_
from sqlalchemy.orm import Session

from app.core.deps import require_roles
from app.db.session import get_db
from app.models.activity_log import ActivityLog
from app.models.enums import UserRole
from app.models.user import User

router = APIRouter(prefix="/owner/activity-logs", tags=["owner-activity-logs"])

DELETED_ACCOUNT_LABEL = "Deleted Account"


@router.get("")
def list_owner_activity_logs(
    db: Annotated[Session, Depends(get_db)],
    user: Annotated[User, Depends(require_roles(UserRole.owner))],
    limit: Annotated[int, Query(ge=1, le=200)] = 50,
    offset: Annotated[int, Query(ge=0)] = 0,
):
    if user.business_id is None:
        raise HTTPException(400, "No business context")

    business_id: uuid.UUID = user.business_id

    rows = (
        db.query(ActivityLog, User)
        .outerjoin(User, ActivityLog.user_id == User.id)
        .filter(
            or_(
                User.business_id == business_id,
                and_(
                    ActivityLog.user_id.is_(None),
                    ActivityLog.business_id == business_id,
                ),
            )
        )
        .order_by(ActivityLog.created_at.desc())
        .offset(offset)
        .limit(limit)
        .all()
    )

    return [
        {
            "id": str(log.id),
            "action": log.action,
            "description": log.description,
            "created_at": log.created_at,
            "actor": (
                DELETED_ACCOUNT_LABEL
                if actor is None or log.user_id is None
                else actor.email
            ),
            "actor_deleted": actor is None or log.user_id is None,
        }
        for log, actor in rows
    ]
