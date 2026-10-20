"""Employee notification badge watermark and mark-all-read isolation."""

from __future__ import annotations

import uuid
from datetime import datetime, timedelta, timezone

from fastapi.testclient import TestClient

from app.core.security import hash_password
from app.db.session import SessionLocal
from app.main import app
from app.models.employee import Employee
from app.models.enums import EmployeeStatus, EmploymentType, UserRole
from app.models.notification import Notification
from app.models.user import User
from app.services.notifications import create_notification
from tests.test_legal_consent import _auth, _create_tenant


def _parse(value: str) -> datetime:
    return datetime.fromisoformat(value.replace("Z", "+00:00"))


def _add_employee(db, business, name: str) -> User:
    user = User(
        business_id=business.id,
        email=f"{name}-{uuid.uuid4().hex[:8]}@example.com",
        password_hash=hash_password("EmpPass123!"),
        role=UserRole.employee,
        must_change_password=False,
        is_active=True,
    )
    db.add(user)
    db.flush()
    db.add(
        Employee(
            business_id=business.id,
            user_id=user.id,
            full_name=name,
            position_title="Staff",
            employment_type=EmploymentType.full_time,
            status=EmployeeStatus.active,
            is_active=True,
            face_registration_status="not_registered",
        )
    )
    db.commit()
    db.refresh(user)
    return user


def _notify(db, user: User, *, title: str, created_at: datetime, role: str) -> Notification:
    row = create_notification(
        db,
        recipient_user_id=user.id,
        recipient_role=role,
        type="schedule_assigned",
        title=title,
        message=title,
        business_id=user.business_id,
        deep_link="/schedule",
        commit=False,
    )
    db.flush()
    row.created_at = created_at
    db.commit()
    db.refresh(row)
    return row


def _cleanup(db, *user_ids: uuid.UUID) -> None:
    db.rollback()
    if user_ids:
        db.query(Notification).filter(
            Notification.recipient_user_id.in_(list(user_ids))
        ).delete(synchronize_session=False)
        db.commit()
    db.close()


def test_listing_notifications_does_not_mark_them_read():
    db, business, _owner, employee, _emp = _create_tenant()
    client = TestClient(app)
    older = datetime(2026, 10, 1, 8, 0, tzinfo=timezone.utc)
    newer = older + timedelta(days=2)
    try:
        _notify(db, employee, title="Older", created_at=older, role="employee")
        _notify(db, employee, title="Newer", created_at=newer, role="employee")

        listed = client.get("/api/v1/notifications", headers=_auth(employee))
        assert listed.status_code == 200, listed.text
        body = listed.json()
        assert len(body) == 2
        assert all(row["is_read"] is False for row in body)
        assert {row["title"] for row in body} == {"Older", "Newer"}

        db.expire_all()
        stored = (
            db.query(Notification)
            .filter(Notification.recipient_user_id == employee.id)
            .all()
        )
        assert len(stored) == 2
        assert all(row.is_read is False for row in stored)
    finally:
        _cleanup(db, employee.id)


def test_badge_watermark_hides_seen_unread_and_counts_new_ones():
    db, _business, owner, employee, _emp = _create_tenant()
    client = TestClient(app)
    older = datetime(2026, 10, 1, 8, 0, tzinfo=timezone.utc)
    newer = older + timedelta(hours=3)
    try:
        _notify(db, employee, title="Older", created_at=older, role="employee")
        newest = _notify(
            db, employee, title="Newer", created_at=newer, role="employee"
        )
        owner_row = _notify(
            db, owner, title="Owner alert", created_at=older, role="owner"
        )

        full = client.get(
            "/api/v1/notifications/unread-count", headers=_auth(employee)
        )
        assert full.status_code == 200, full.text
        assert full.json()["count"] == 2

        seen = client.get(
            "/api/v1/notifications/unread-count",
            params={"created_after": newest.created_at.isoformat()},
            headers=_auth(employee),
        )
        assert seen.status_code == 200, seen.text
        assert seen.json()["count"] == 0

        db.expire_all()
        assert db.get(Notification, newest.id).is_read is False

        arrived = _notify(
            db,
            employee,
            title="After open",
            created_at=newer + timedelta(minutes=5),
            role="employee",
        )
        again = client.get(
            "/api/v1/notifications/unread-count",
            params={"created_after": newest.created_at.isoformat()},
            headers=_auth(employee),
        )
        assert again.json()["count"] == 1

        owner_count = client.get(
            "/api/v1/owner/notifications/unread-count",
            headers=_auth(owner),
        )
        assert owner_count.status_code == 200, owner_count.text
        assert owner_count.json()["count"] == 1
        assert db.get(Notification, owner_row.id).is_read is False
        assert db.get(Notification, arrived.id).is_read is False
    finally:
        _cleanup(db, employee.id, owner.id)


def test_mark_all_read_persists_employee_rows_and_leaves_others():
    db, business, owner, employee, _emp = _create_tenant()
    other = _add_employee(db, business, "Other")
    client = TestClient(app)
    older = datetime(2026, 10, 2, 9, 0, tzinfo=timezone.utc)
    newer = older + timedelta(hours=4)
    try:
        first = _notify(
            db, employee, title="First", created_at=older, role="employee"
        )
        second = _notify(
            db, employee, title="Second", created_at=newer, role="employee"
        )
        theirs = _notify(
            db, other, title="Theirs", created_at=older, role="employee"
        )
        owner_row = _notify(
            db, owner, title="Owner alert", created_at=older, role="owner"
        )

        denied = client.post(
            "/api/v1/owner/notifications/read-all",
            headers={**_auth(employee), "Content-Type": "application/json"},
        )
        assert denied.status_code == 403

        marked = client.post(
            "/api/v1/notifications/read-all",
            params={"created_through": second.created_at.isoformat()},
            headers={**_auth(employee), "Content-Type": "application/json"},
        )
        assert marked.status_code == 200, marked.text
        assert marked.json()["marked_read"] == 2

        listed = client.get("/api/v1/notifications", headers=_auth(employee))
        assert listed.status_code == 200
        body = listed.json()
        assert len(body) == 2
        assert {row["id"] for row in body} == {str(first.id), str(second.id)}
        assert all(row["is_read"] is True for row in body)
        assert all(row["title"] in {"First", "Second"} for row in body)
        assert all(row["deep_link"] == "/schedule" for row in body)

        db.expire_all()
        assert db.get(Notification, theirs.id).is_read is False
        assert db.get(Notification, owner_row.id).is_read is False

        count = client.get(
            "/api/v1/notifications/unread-count", headers=_auth(employee)
        )
        assert count.json()["count"] == 0
        other_count = client.get(
            "/api/v1/notifications/unread-count", headers=_auth(other)
        )
        assert other_count.json()["count"] == 1
    finally:
        _cleanup(db, employee.id, other.id, owner.id)


def test_mark_all_read_does_not_include_a_notification_after_the_snapshot():
    db, _business, _owner, employee, _emp = _create_tenant()
    client = TestClient(app)
    seen_at = datetime(2026, 10, 3, 10, 0, tzinfo=timezone.utc)
    try:
        _notify(db, employee, title="Visible", created_at=seen_at, role="employee")
        arrived = _notify(
            db,
            employee,
            title="Arrived during mark all",
            created_at=seen_at + timedelta(minutes=2),
            role="employee",
        )
        marked = client.post(
            "/api/v1/notifications/read-all",
            params={"created_through": seen_at.isoformat()},
            headers=_auth(employee),
        )
        assert marked.status_code == 200, marked.text
        assert marked.json()["marked_read"] == 1

        listed = client.get("/api/v1/notifications", headers=_auth(employee))
        rows = {row["title"]: row for row in listed.json()}
        assert rows["Visible"]["is_read"] is True
        assert rows["Arrived during mark all"]["is_read"] is False
        assert len(rows) == 2

        db.expire_all()
        assert db.get(Notification, arrived.id).is_read is False
        unread = client.get(
            "/api/v1/notifications/unread-count", headers=_auth(employee)
        )
        assert unread.json()["count"] == 1
    finally:
        _cleanup(db, employee.id)


def test_empty_and_already_read_mark_all_changes_nothing():
    db, _business, _owner, employee, _emp = _create_tenant()
    client = TestClient(app)
    created_at = datetime(2026, 10, 4, 11, 0, tzinfo=timezone.utc)
    try:
        empty = client.post(
            "/api/v1/notifications/read-all",
            headers={**_auth(employee), "Content-Type": "application/json"},
        )
        assert empty.status_code == 200, empty.text
        assert empty.json()["marked_read"] == 0

        row = _notify(
            db, employee, title="Already", created_at=created_at, role="employee"
        )
        row.is_read = True
        db.commit()
        again = client.post(
            "/api/v1/notifications/read-all",
            headers=_auth(employee),
        )
        assert again.status_code == 200, again.text
        assert again.json()["marked_read"] == 0
        listed = client.get("/api/v1/notifications", headers=_auth(employee))
        assert len(listed.json()) == 1
        assert listed.json()[0]["is_read"] is True
        assert listed.json()[0]["title"] == "Already"
    finally:
        _cleanup(db, employee.id)


def test_individual_read_does_not_change_other_notifications():
    db, business, _owner, employee, _emp = _create_tenant()
    other = _add_employee(db, business, "Other")
    client = TestClient(app)
    created_at = datetime(2026, 10, 5, 12, 0, tzinfo=timezone.utc)
    try:
        own = _notify(
            db, employee, title="Mine", created_at=created_at, role="employee"
        )
        theirs = _notify(
            db, other, title="Theirs", created_at=created_at, role="employee"
        )
        blocked = client.post(
            f"/api/v1/notifications/{theirs.id}/read",
            headers=_auth(employee),
        )
        assert blocked.status_code == 404
        opened = client.post(
            f"/api/v1/notifications/{own.id}/read",
            headers=_auth(employee),
        )
        assert opened.status_code == 200, opened.text
        assert opened.json()["is_read"] is True
        assert opened.json()["deep_link"] == "/schedule"
        assert opened.json()["title"] == "Mine"

        db.expire_all()
        assert db.get(Notification, theirs.id).is_read is False
        listed = client.get("/api/v1/notifications", headers=_auth(employee))
        assert len(listed.json()) == 1
        assert listed.json()[0]["id"] == str(own.id)
    finally:
        _cleanup(db, employee.id, other.id)


def test_owner_mark_all_does_not_change_employee_notifications():
    db, _business, owner, employee, _emp = _create_tenant()
    client = TestClient(app)
    created_at = datetime(2026, 10, 6, 13, 0, tzinfo=timezone.utc)
    try:
        employee_row = _notify(
            db, employee, title="Employee", created_at=created_at, role="employee"
        )
        owner_row = _notify(
            db, owner, title="Owner", created_at=created_at, role="owner"
        )
        marked = client.post(
            "/api/v1/owner/notifications/read-all",
            headers={**_auth(owner), "Content-Type": "application/json"},
        )
        assert marked.status_code == 200, marked.text
        assert marked.json()["marked_read"] == 1

        db.expire_all()
        assert db.get(Notification, owner_row.id).is_read is True
        assert db.get(Notification, employee_row.id).is_read is False
        employee_count = client.get(
            "/api/v1/notifications/unread-count",
            headers=_auth(employee),
        )
        assert employee_count.json()["count"] == 1
    finally:
        _cleanup(db, employee.id, owner.id)
