"""Owner read-only audit history + hard-delete activity_log FK handling."""

from datetime import datetime, timezone
from types import SimpleNamespace
from unittest.mock import MagicMock, patch
from uuid import uuid4

import pytest
from fastapi import HTTPException

from app.models.enums import UserRole
from app.models.user import User


def test_activity_log_user_id_is_nullable():
    from app.models.activity_log import ActivityLog

    assert ActivityLog.__table__.c.user_id.nullable is True


def test_owner_activity_logs_requires_business_context():
    from app.api.owner_activity_logs import list_owner_activity_logs

    owner = User(
        id=uuid4(),
        business_id=None,
        role=UserRole.owner,
        is_active=True,
    )
    db = MagicMock()
    with pytest.raises(HTTPException) as exc:
        list_owner_activity_logs(db, owner, limit=50, offset=0)
    assert exc.value.status_code == 400


def test_owner_activity_logs_returns_newest_first_with_deleted_label():
    from app.api.owner_activity_logs import (
        DELETED_ACCOUNT_LABEL,
        list_owner_activity_logs,
    )
    from app.models.activity_log import ActivityLog

    business_id = uuid4()
    owner = User(
        id=uuid4(),
        business_id=business_id,
        role=UserRole.owner,
        is_active=True,
        email="owner@example.com",
    )
    active_actor = User(
        id=uuid4(),
        business_id=business_id,
        role=UserRole.employee,
        is_active=True,
        email="worker@example.com",
    )
    newer = SimpleNamespace(
        id=uuid4(),
        user_id=None,
        business_id=business_id,
        action="FACE_ENROLL",
        description="Enrolled face",
        created_at=datetime(2026, 9, 22, 12, 0, tzinfo=timezone.utc),
    )
    older = SimpleNamespace(
        id=uuid4(),
        user_id=active_actor.id,
        business_id=business_id,
        action="LOGIN",
        description="Signed in",
        created_at=datetime(2026, 9, 21, 8, 0, tzinfo=timezone.utc),
    )

    db = MagicMock()
    query = MagicMock()
    db.query.return_value = query
    query.outerjoin.return_value = query
    query.filter.return_value = query
    query.order_by.return_value = query
    query.offset.return_value = query
    query.limit.return_value = query
    query.all.return_value = [(newer, None), (older, active_actor)]

    result = list_owner_activity_logs(db, owner, limit=50, offset=0)

    assert result[0]["actor"] == DELETED_ACCOUNT_LABEL
    assert result[0]["actor_deleted"] is True
    assert result[0]["action"] == "FACE_ENROLL"
    assert result[1]["actor"] == "worker@example.com"
    assert result[1]["actor_deleted"] is False
    db.query.assert_called_once_with(ActivityLog, User)
    query.order_by.assert_called_once()


def test_owner_activity_logs_rejects_employee_role_via_dependency():
    """Endpoint is wired with require_roles(owner) only — inspect source."""
    import inspect

    from app.api import owner_activity_logs

    source = inspect.getsource(owner_activity_logs.list_owner_activity_logs)
    assert "UserRole.owner" in source
    assert "UserRole.employee" not in source
