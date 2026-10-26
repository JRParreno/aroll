"""Approval keeps existing account creation; email send is a later admin action."""

from __future__ import annotations

import uuid
from datetime import datetime, timedelta, timezone

from fastapi.testclient import TestClient

from app.core.security import create_access_token, hash_password, verify_password
from app.db.session import SessionLocal
from app.main import app
from app.models.business import Business, BusinessRegistration
from app.models.enums import ApplicationStatus, RegistrationStatus, UserRole
from app.models.payroll import BusinessPayrollConfig
from app.models.user import User
from app.services.approval_email import (
    EMAIL_NOT_SENT,
    EMAIL_SENDING,
    EMAIL_SENT,
    build_approval_email,
    build_rejection_email,
    smtp_configured,
)


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


def _configure_smtp(monkeypatch):
    from app.core.config import settings

    monkeypatch.setattr(settings, "smtp_host", "smtp.example.test")
    monkeypatch.setattr(settings, "smtp_from_email", "noreply@example.test")
    monkeypatch.setattr(settings, "smtp_username", "smtp-user")
    monkeypatch.setattr(settings, "smtp_password", "smtp-secret")
    monkeypatch.setattr(
        settings, "owner_login_url", "http://localhost:5173/owner-login"
    )


def _capture_send(monkeypatch):
    sent: list[dict] = []

    def fake_send(to_email, subject, text_body, html_body):
        sent.append(
            {
                "to": to_email,
                "subject": subject,
                "text": text_body,
                "html": html_body,
            }
        )

    monkeypatch.setattr("app.services.approval_email.send_message", fake_send)
    return sent


def test_build_approval_email_contains_login_instructions():
    subject, text, html_body = build_approval_email(
        owner_name="Jordan Owner",
        business_name="Harbor Cafe",
        business_code="MB-ABCDEF",
        owner_email="jordan@example.com",
        login_url="http://localhost:5173/owner-login",
    )
    assert subject == "Your Aroll+ Business Registration Has Been Approved"
    assert "MB-ABCDEF" in text
    assert "jordan@example.com" in text
    assert "http://localhost:5173/owner-login" in text
    assert "temporary initial password" in text
    assert "change your temporary password" in text
    assert "MB-ABCDEF" in html_body
    assert "Harbor Cafe" in html_body


def test_approve_creates_business_owner_and_payroll():
    db = SessionLocal()
    client = TestClient(app)
    try:
        admin = _platform_admin(db)
        reg = _pending_registration(db)
        approved = client.post(
            f"/api/v1/admin/registrations/{reg.id}/approve",
            headers=_auth(admin),
        )
        assert approved.status_code == 200, approved.text
        body = approved.json()
        assert body["owner_email"] == reg.owner_email
        assert body["business_code"].startswith("MB-")
        assert len(body["business_code"]) == 9

        db.expire_all()
        saved = db.get(BusinessRegistration, reg.id)
        assert saved.application_status == ApplicationStatus.approved
        assert saved.status == RegistrationStatus.approved
        business = (
            db.query(Business)
            .filter(Business.registration_id == reg.id)
            .one()
        )
        assert business.business_code == body["business_code"]
        owner = (
            db.query(User)
            .filter(User.business_id == business.id, User.role == UserRole.owner)
            .one()
        )
        assert owner.email == reg.owner_email.lower()
        assert owner.must_change_password is True
        assert verify_password(body["business_code"], owner.password_hash)
        payroll = db.get(BusinessPayrollConfig, business.id)
        assert payroll is not None

        again = client.post(
            f"/api/v1/admin/registrations/{reg.id}/approve",
            headers=_auth(admin),
        )
        assert again.status_code == 400
        assert (
            db.query(Business)
            .filter(Business.registration_id == reg.id)
            .count()
            == 1
        )
    finally:
        db.close()


def test_send_email_after_approval_uses_stored_owner_and_code(monkeypatch):
    _configure_smtp(monkeypatch)
    sent = _capture_send(monkeypatch)
    db = SessionLocal()
    client = TestClient(app)
    try:
        admin = _platform_admin(db)
        reg = _pending_registration(db)
        approved = client.post(
            f"/api/v1/admin/registrations/{reg.id}/approve",
            headers=_auth(admin),
        )
        code = approved.json()["business_code"]

        mailed = client.post(
            f"/api/v1/admin/registrations/{reg.id}/send-approval-email",
            json={
                "recipient": "attacker@example.com",
                "business_code": "MB-FAKE01",
                "owner_email": "attacker@example.com",
            },
            headers=_auth(admin),
        )
        assert mailed.status_code == 200, mailed.text
        payload = mailed.json()
        assert payload["status"] == "sent"
        assert payload["recipient"] == reg.owner_email.lower()
        assert payload["previously_sent"] is False
        assert len(sent) == 1
        assert sent[0]["to"] == reg.owner_email.lower()
        assert code in sent[0]["text"]
        assert "MB-FAKE01" not in sent[0]["text"]
        assert "attacker@example.com" not in sent[0]["text"]
        assert "http://localhost:5173/owner-login" in sent[0]["text"]
        assert "temporary initial password" in sent[0]["text"]

        public = client.get(f"/api/v1/registrations/by-email/{reg.owner_email}")
        assert public.status_code == 200
        assert "business_code" not in public.json()
        assert code not in public.text
    finally:
        db.close()


def test_pending_and_rejected_cannot_send_email(monkeypatch):
    _configure_smtp(monkeypatch)
    sent = _capture_send(monkeypatch)
    db = SessionLocal()
    client = TestClient(app)
    try:
        admin = _platform_admin(db)
        pending = _pending_registration(db)
        blocked = client.post(
            f"/api/v1/admin/registrations/{pending.id}/send-approval-email",
            headers=_auth(admin),
        )
        assert blocked.status_code == 400
        assert sent == []

        rejected = _pending_registration(db)
        reject = client.post(
            f"/api/v1/admin/registrations/{rejected.id}/reject",
            json={"reasons": ["incomplete_documents"]},
            headers=_auth(admin),
        )
        assert reject.status_code == 200
        assert reject.json()["email_status"] == "sent"
        assert len(sent) == 1
        assert sent[0]["to"] == rejected.owner_email
        refused = client.post(
            f"/api/v1/admin/registrations/{rejected.id}/send-approval-email",
            headers=_auth(admin),
        )
        assert refused.status_code == 400
        assert len(sent) == 1
        db.expire_all()
        saved = db.get(BusinessRegistration, rejected.id)
        assert saved.application_status == ApplicationStatus.rejected
        assert (
            db.query(Business)
            .filter(Business.registration_id == rejected.id)
            .count()
            == 0
        )
    finally:
        db.close()


def test_unauthorized_user_cannot_send_email(monkeypatch):
    _configure_smtp(monkeypatch)
    sent = _capture_send(monkeypatch)
    db = SessionLocal()
    client = TestClient(app)
    try:
        admin = _platform_admin(db)
        reg = _pending_registration(db)
        client.post(
            f"/api/v1/admin/registrations/{reg.id}/approve",
            headers=_auth(admin),
        )
        owner = (
            db.query(User)
            .filter(User.role == UserRole.owner)
            .order_by(User.created_at.desc())
            .first()
        )
        denied = client.post(
            f"/api/v1/admin/registrations/{reg.id}/send-approval-email",
            headers=_auth(owner),
        )
        assert denied.status_code in {401, 403}
        assert sent == []
    finally:
        db.close()


def test_smtp_configured_requires_password_when_username_set(monkeypatch):
    from app.core.config import settings

    monkeypatch.setattr(settings, "smtp_host", "smtp.example.test")
    monkeypatch.setattr(settings, "smtp_from_email", "noreply@example.test")
    monkeypatch.setattr(settings, "smtp_username", "smtp-user")
    monkeypatch.setattr(settings, "smtp_password", "")
    assert smtp_configured() is False
    monkeypatch.setattr(settings, "smtp_password", "smtp-secret")
    assert smtp_configured() is True
    monkeypatch.setattr(settings, "smtp_username", "")
    assert smtp_configured() is False
    monkeypatch.setattr(settings, "smtp_username", "smtp-user")
    monkeypatch.setattr(settings, "smtp_use_tls", False)
    monkeypatch.setattr(settings, "smtp_use_ssl", False)
    assert smtp_configured() is False
    monkeypatch.setattr(settings, "smtp_use_ssl", True)
    assert smtp_configured() is True


def test_smtp_settings_rereads_env_file_outside_pytest(monkeypatch):
    from app.core import config

    monkeypatch.delenv("PYTEST_CURRENT_TEST", raising=False)
    sentinel = object()
    monkeypatch.setattr(config, "Settings", lambda: sentinel)
    assert config.smtp_settings() is sentinel


def test_smtp_settings_keeps_imported_settings_during_pytest():
    from app.core.config import settings, smtp_settings

    assert smtp_settings() is settings


def test_smtp_env_file_is_recognized_without_sending(monkeypatch, tmp_path):
    """A populated SMTP env file counts as configured and does not connect."""
    from app.core.config import Settings, settings

    env_file = tmp_path / ".env"
    env_file.write_text(
        "SMTP_HOST=smtp.example.test\n"
        "SMTP_PORT=2525\n"
        "SMTP_USERNAME=smtp-user\n"
        "SMTP_PASSWORD=smtp-secret\n"
        "SMTP_FROM_EMAIL=noreply@example.test\n"
        "SMTP_USE_TLS=true\n"
        "SMTP_USE_SSL=false\n",
        encoding="utf-8",
    )
    for name in (
        "SMTP_HOST",
        "SMTP_PORT",
        "SMTP_USERNAME",
        "SMTP_PASSWORD",
        "SMTP_FROM_EMAIL",
        "SMTP_USE_TLS",
        "SMTP_USE_SSL",
    ):
        monkeypatch.delenv(name, raising=False)

    # Import-time settings stay empty, as they would if the process started
    # before backend/.env contained these keys.
    monkeypatch.setattr(settings, "smtp_host", "")
    monkeypatch.setattr(settings, "smtp_from_email", "")
    monkeypatch.setattr(settings, "smtp_username", "")
    monkeypatch.setattr(settings, "smtp_password", "")

    loaded = Settings(_env_file=env_file, _env_file_encoding="utf-8")
    assert loaded.smtp_host == "smtp.example.test"
    assert loaded.smtp_port == 2525
    assert loaded.smtp_from_email == "noreply@example.test"
    assert loaded.smtp_use_tls is True
    assert loaded.smtp_use_ssl is False
    assert (loaded.smtp_password or "").strip()

    monkeypatch.setattr("app.services.approval_email.smtp_settings", lambda: loaded)
    assert smtp_configured() is True


def test_send_email_uses_env_file_when_imported_settings_are_empty(monkeypatch):
    from app.core.config import settings

    monkeypatch.setattr(settings, "smtp_host", "")
    monkeypatch.setattr(settings, "smtp_from_email", "")
    monkeypatch.setattr(settings, "smtp_username", "")
    monkeypatch.setattr(settings, "smtp_password", "")

    class _FileSettings:
        smtp_host = "smtp.example.test"
        smtp_port = 2525
        smtp_username = "smtp-user"
        smtp_password = "smtp-secret"
        smtp_from_email = "noreply@example.test"
        smtp_use_tls = True
        smtp_use_ssl = False

    monkeypatch.setattr(
        "app.services.approval_email.smtp_settings",
        lambda: _FileSettings(),
    )
    sent = _capture_send(monkeypatch)
    db = SessionLocal()
    client = TestClient(app)
    try:
        admin = _platform_admin(db)
        reg = _pending_registration(db)
        approved = client.post(
            f"/api/v1/admin/registrations/{reg.id}/approve",
            headers=_auth(admin),
        )
        assert approved.status_code == 200
        mailed = client.post(
            f"/api/v1/admin/registrations/{reg.id}/send-approval-email",
            headers=_auth(admin),
        )
        assert mailed.status_code == 200, mailed.text
        assert mailed.json()["status"] == "sent"
        assert len(sent) == 1
    finally:
        db.close()


def test_missing_smtp_config_does_not_unapprove(monkeypatch):
    from app.core.config import settings

    monkeypatch.setattr(settings, "smtp_host", "")
    monkeypatch.setattr(settings, "smtp_from_email", "")
    monkeypatch.setattr(settings, "smtp_username", "")
    monkeypatch.setattr(settings, "smtp_password", "")
    db = SessionLocal()
    client = TestClient(app)
    try:
        admin = _platform_admin(db)
        reg = _pending_registration(db)
        approved = client.post(
            f"/api/v1/admin/registrations/{reg.id}/approve",
            headers=_auth(admin),
        )
        assert approved.status_code == 200
        failed = client.post(
            f"/api/v1/admin/registrations/{reg.id}/send-approval-email",
            headers=_auth(admin),
        )
        assert failed.status_code == 503
        assert "not configured" in failed.json()["detail"].lower()
        db.expire_all()
        saved = db.get(BusinessRegistration, reg.id)
        assert saved.application_status == ApplicationStatus.approved
        assert saved.approval_email_status != EMAIL_SENT
    finally:
        db.close()


def test_provider_failure_does_not_unapprove(monkeypatch):
    _configure_smtp(monkeypatch)

    def boom(*_args, **_kwargs):
        raise RuntimeError("smtp-secret blew up MB-ABCDEF")

    monkeypatch.setattr("app.services.approval_email.send_message", boom)
    db = SessionLocal()
    client = TestClient(app)
    try:
        admin = _platform_admin(db)
        reg = _pending_registration(db)
        approved = client.post(
            f"/api/v1/admin/registrations/{reg.id}/approve",
            headers=_auth(admin),
        )
        assert approved.status_code == 200
        code = approved.json()["business_code"]
        failed = client.post(
            f"/api/v1/admin/registrations/{reg.id}/send-approval-email",
            headers=_auth(admin),
        )
        assert failed.status_code == 502
        detail = failed.json()["detail"]
        assert "smtp-secret" not in detail
        assert code not in detail
        assert "MB-ABCDEF" not in detail
        db.expire_all()
        saved = db.get(BusinessRegistration, reg.id)
        assert saved.application_status == ApplicationStatus.approved
        assert saved.approval_email_status == "failed"
        assert saved.approval_email_last_error
        assert "smtp-secret" not in saved.approval_email_last_error
        assert code not in (saved.approval_email_last_error or "")
    finally:
        db.close()


def test_concurrent_send_is_rejected_then_intentional_resend_works(monkeypatch):
    _configure_smtp(monkeypatch)
    sent = _capture_send(monkeypatch)
    db = SessionLocal()
    client = TestClient(app)
    try:
        admin = _platform_admin(db)
        reg = _pending_registration(db)
        client.post(
            f"/api/v1/admin/registrations/{reg.id}/approve",
            headers=_auth(admin),
        )
        db.expire_all()
        locked = db.get(BusinessRegistration, reg.id)
        locked.approval_email_status = EMAIL_SENDING
        locked.approval_email_sent_at = datetime.now(timezone.utc)
        db.commit()

        busy = client.post(
            f"/api/v1/admin/registrations/{reg.id}/send-approval-email",
            headers=_auth(admin),
        )
        assert busy.status_code == 409
        assert sent == []

        locked = db.get(BusinessRegistration, reg.id)
        locked.approval_email_status = EMAIL_SENDING
        locked.approval_email_sent_at = datetime.now(timezone.utc) - timedelta(
            minutes=5
        )
        db.commit()

        first = client.post(
            f"/api/v1/admin/registrations/{reg.id}/send-approval-email",
            headers=_auth(admin),
        )
        assert first.status_code == 200, first.text
        second = client.post(
            f"/api/v1/admin/registrations/{reg.id}/send-approval-email",
            headers=_auth(admin),
        )
        assert second.status_code == 200, second.text
        assert second.json()["previously_sent"] is True
        assert len(sent) == 2
        db.expire_all()
        business = (
            db.query(Business)
            .filter(Business.registration_id == reg.id)
            .one()
        )
        assert sent[0]["text"].count(business.business_code) >= 1
        assert sent[1]["text"].count(business.business_code) >= 1
    finally:
        db.close()


def test_activity_log_failure_does_not_block_approval_or_email(monkeypatch):
    _configure_smtp(monkeypatch)
    sent = _capture_send(monkeypatch)

    def fail_log(*_args, **_kwargs):
        raise RuntimeError("activity log unavailable")

    monkeypatch.setattr("app.api.admin.create_log", fail_log)
    db = SessionLocal()
    client = TestClient(app)
    try:
        admin = _platform_admin(db)
        reg = _pending_registration(db)
        approved = client.post(
            f"/api/v1/admin/registrations/{reg.id}/approve",
            headers=_auth(admin),
        )
        assert approved.status_code == 200, approved.text
        mailed = client.post(
            f"/api/v1/admin/registrations/{reg.id}/send-approval-email",
            headers=_auth(admin),
        )
        assert mailed.status_code == 200, mailed.text
        assert len(sent) == 1
        db.expire_all()
        saved = db.get(BusinessRegistration, reg.id)
        assert saved.application_status == ApplicationStatus.approved
        assert saved.approval_email_status == EMAIL_SENT
    finally:
        db.close()


def test_build_rejection_email_includes_reason_and_resubmission():
    subject, text, html_body = build_rejection_email(
        owner_name="Jordan Owner",
        business_name="Harbor Cafe",
        rejection_reason="Submitted documents are incomplete.",
    )
    assert "has not been approved" in text
    assert "Harbor Cafe" in text
    assert "- Submitted documents are incomplete." in text
    assert "resubmit" in text.lower()
    assert "Submitted documents are incomplete." in html_body


def test_build_rejection_email_lists_multiple_reasons_and_other_explanation():
    _subject, text, html_body = build_rejection_email(
        owner_name="Jordan Owner",
        business_name="Harbor Cafe",
        rejection_reason=(
            "Required documents are missing.\nPermit photo is cropped"
        ),
    )
    assert "- Required documents are missing." in text
    assert "- Permit photo is cropped" in text
    assert "Required documents are missing." in html_body
    assert "Permit photo is cropped" in html_body


def test_build_rejection_email_omits_missing_reason():
    _subject, text, html_body = build_rejection_email(
        owner_name="Jordan Owner",
        business_name="Harbor Cafe",
        rejection_reason="  ",
    )
    assert "following reason(s)" not in text
    assert "following reason(s)" not in html_body


def test_reject_sends_email_and_keeps_rejected_on_smtp_failure(monkeypatch):
    _configure_smtp(monkeypatch)
    sent = _capture_send(monkeypatch)
    db = SessionLocal()
    client = TestClient(app)
    try:
        admin = _platform_admin(db)
        reg = _pending_registration(db)
        rejected = client.post(
            f"/api/v1/admin/registrations/{reg.id}/reject",
            json={"reasons": ["incomplete_documents"]},
            headers=_auth(admin),
        )
        assert rejected.status_code == 200, rejected.text
        body = rejected.json()
        assert body["status"] == "rejected"
        assert body["email_status"] == "sent"
        assert body["recipient"] == reg.owner_email
        assert len(sent) == 1
        assert sent[0]["to"] == reg.owner_email
        assert "- Submitted documents are incomplete." in sent[0]["text"]
        assert "Harbor Cafe" in sent[0]["text"]
        db.expire_all()
        saved = db.get(BusinessRegistration, reg.id)
        assert saved.application_status == ApplicationStatus.rejected
        assert saved.rejection_reason == "Submitted documents are incomplete."
    finally:
        db.close()

    def boom(*_args, **_kwargs):
        raise RuntimeError("smtp-secret blew up")

    monkeypatch.setattr("app.services.approval_email.send_message", boom)
    db = SessionLocal()
    client = TestClient(app)
    try:
        admin = _platform_admin(db)
        reg = _pending_registration(db, business_name="Failing Cafe")
        rejected = client.post(
            f"/api/v1/admin/registrations/{reg.id}/reject",
            json={
                "reasons": ["unverified_information"],
            },
            headers=_auth(admin),
        )
        assert rejected.status_code == 200, rejected.text
        body = rejected.json()
        assert body["status"] == "rejected"
        assert body["email_status"] == "failed"
        assert "smtp-secret" not in (body.get("email_error") or "")
        db.expire_all()
        saved = db.get(BusinessRegistration, reg.id)
        assert saved.application_status == ApplicationStatus.rejected
        assert saved.rejection_reason == "Submitted information could not be verified."
    finally:
        db.close()
