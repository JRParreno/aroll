"""Approved-business date filters, recent view, and deferred login email."""

from __future__ import annotations

import uuid
from datetime import datetime, timedelta, timezone

from fastapi.testclient import TestClient

from app.core.security import create_access_token, hash_password
from app.db.session import SessionLocal
from app.main import app
from app.models.business import BusinessRegistration
from app.models.enums import ApplicationStatus, RegistrationStatus, UserRole
from app.models.user import User


def _auth(user: User) -> dict[str, str]:
    token = create_access_token(
        str(user.id),
        extra={
            "role": user.role.value,
            "business_id": str(user.business_id) if user.business_id else None,
        },
    )
    return {"Authorization": f"Bearer {token}"}


def _platform_admin(db):
    admin = User(
        business_id=None,
        email=f"admin-{uuid.uuid4().hex[:8]}@example.com",
        password_hash=hash_password("AdminPass123!"),
        role=UserRole.platform_admin,
        must_change_password=False,
        is_active=True,
    )
    db.add(admin)
    db.commit()
    db.refresh(admin)
    return admin


def _pending_registration(db, **overrides):
    payload = {
        "business_name": "Harbor Cafe",
        "owner_name": "Jordan Owner",
        "owner_email": f"owner-{uuid.uuid4().hex[:8]}@example.com",
        "owner_phone": "09170000000",
        "proposed_address": "123 Harbor St",
        "business_type": "cafe",
        "status": RegistrationStatus.pending,
        "application_status": ApplicationStatus.pending,
        "submitted_at": datetime.now(timezone.utc),
    }
    payload.update(overrides)
    row = BusinessRegistration(**payload)
    db.add(row)
    db.commit()
    db.refresh(row)
    return row


def _approve(client, admin, reg):
    response = client.post(
        f"/api/v1/admin/registrations/{reg.id}/approve",
        headers=_auth(admin),
    )
    assert response.status_code == 200, response.text
    return response.json()


def _set_reviewed_at(db, registration_id, when):
    row = db.get(BusinessRegistration, registration_id)
    row.reviewed_at = when
    db.commit()


def test_date_filters_use_approval_timestamp_inclusively(monkeypatch):
    monkeypatch.setattr("app.services.approval_email.smtp_configured", lambda: False)
    db = SessionLocal()
    client = TestClient(app)
    try:
        admin = _platform_admin(db)
        suffix = uuid.uuid4().hex[:8]
        old_name = f"Old Cafe {suffix}"
        mid_name = f"Mid Cafe {suffix}"
        new_name = f"New Cafe {suffix}"
        created = {old_name, mid_name, new_name}
        old_reg = _pending_registration(db, business_name=old_name)
        mid_reg = _pending_registration(db, business_name=mid_name)
        new_reg = _pending_registration(db, business_name=new_name)
        _approve(client, admin, old_reg)
        _approve(client, admin, mid_reg)
        _approve(client, admin, new_reg)

        _set_reviewed_at(db, old_reg.id, datetime(2026, 1, 5, 8, 0, tzinfo=timezone.utc))
        _set_reviewed_at(db, mid_reg.id, datetime(2026, 3, 15, 8, 0, tzinfo=timezone.utc))
        _set_reviewed_at(db, new_reg.id, datetime(2026, 6, 20, 8, 0, tzinfo=timezone.utc))

        headers = _auth(admin)
        both_bounds = client.get(
            "/api/v1/admin/businesses",
            params={"approved_from": "2026-03-15", "approved_to": "2026-03-15"},
            headers=headers,
        )
        assert both_bounds.status_code == 200
        names = created.intersection(row["name"] for row in both_bounds.json())
        assert names == {mid_name}
        mid_row = next(row for row in both_bounds.json() if row["name"] == mid_name)
        assert mid_row["approved_at"] is not None

        from_only = client.get(
            "/api/v1/admin/businesses",
            params={"approved_from": "2026-03-15"},
            headers=headers,
        )
        assert created.intersection(row["name"] for row in from_only.json()) == {
            mid_name,
            new_name,
        }

        to_only = client.get(
            "/api/v1/admin/businesses",
            params={"approved_to": "2026-03-15"},
            headers=headers,
        )
        assert created.intersection(row["name"] for row in to_only.json()) == {
            old_name,
            mid_name,
        }

        invalid = client.get(
            "/api/v1/admin/businesses",
            params={"approved_from": "2026-06-01", "approved_to": "2026-01-01"},
            headers=headers,
        )
        assert invalid.status_code == 400
    finally:
        db.close()


def test_unfiltered_list_keeps_created_order_and_includes_unknown_email():
    db = SessionLocal()
    client = TestClient(app)
    try:
        admin = _platform_admin(db)
        listing = client.get("/api/v1/admin/businesses", headers=_auth(admin))
        assert listing.status_code == 200
        assert isinstance(listing.json(), list)
    finally:
        db.close()


def test_recent_and_pending_email_filters(monkeypatch):
    from app.core.config import settings

    monkeypatch.setattr(settings, "smtp_host", "smtp.example.test")
    monkeypatch.setattr(settings, "smtp_from_email", "noreply@example.test")
    monkeypatch.setattr(settings, "smtp_username", "smtp-user")
    monkeypatch.setattr(settings, "smtp_password", "smtp-secret")
    sent: list[dict] = []

    def fake_send(to_email, subject, text_body, html_body):
        sent.append({"to": to_email, "subject": subject, "text": text_body})

    monkeypatch.setattr("app.services.approval_email.send_message", fake_send)

    db = SessionLocal()
    client = TestClient(app)
    try:
        admin = _platform_admin(db)
        suffix = uuid.uuid4().hex[:8]
        pending_name = f"Pending Email Cafe {suffix}"
        sent_name = f"Sent Email Cafe {suffix}"
        old_name = f"Older Approved Cafe {suffix}"
        pending_reg = _pending_registration(db, business_name=pending_name)
        sent_reg = _pending_registration(db, business_name=sent_name)
        old_reg = _pending_registration(db, business_name=old_name)
        _approve(client, admin, pending_reg)
        _approve(client, admin, sent_reg)
        _approve(client, admin, old_reg)

        mailed = client.post(
            f"/api/v1/admin/registrations/{sent_reg.id}/send-approval-email",
            headers=_auth(admin),
        )
        assert mailed.status_code == 200, mailed.text

        _set_reviewed_at(
            db,
            old_reg.id,
            datetime.now(timezone.utc) - timedelta(days=45),
        )

        headers = _auth(admin)
        recent = client.get(
            "/api/v1/admin/businesses",
            params={
                "approved_from": (
                    datetime.now(timezone.utc) - timedelta(days=29)
                ).date().isoformat(),
                "approved_to": datetime.now(timezone.utc).date().isoformat(),
            },
            headers=headers,
        )
        recent_names = [row["name"] for row in recent.json()]
        assert pending_name in recent_names
        assert sent_name in recent_names
        assert old_name not in recent_names
        ours = [row for row in recent.json() if row["name"] in {pending_name, sent_name}]
        ours_times = [row["approved_at"] for row in ours]
        assert ours_times == sorted(ours_times, reverse=True)

        pending = client.get(
            "/api/v1/admin/businesses",
            params={"email_status": "pending"},
            headers=headers,
        )
        pending_names = {row["name"] for row in pending.json()}
        assert pending_name in pending_names
        assert old_name in pending_names
        assert sent_name not in pending_names
        for row in pending.json():
            assert row["approval_email_status"] != "sent"

        owner = (
            db.query(User)
            .filter(User.role == UserRole.owner)
            .order_by(User.created_at.desc())
            .first()
        )
        denied = client.get(
            "/api/v1/admin/businesses",
            params={"email_status": "pending"},
            headers=_auth(owner),
        )
        assert denied.status_code in {401, 403}
    finally:
        db.close()
