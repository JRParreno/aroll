"""Owner Help support email. The SMTP provider is mocked."""

from __future__ import annotations

import uuid

import pytest
from fastapi.testclient import TestClient

from app.core.security import create_access_token, hash_password
from app.db.session import SessionLocal
from app.main import app
from app.models.business import Business
from app.models.employee import Employee
from app.models.enums import BusinessStatus, UserRole
from app.models.user import User
from app.services.support_email import (
    SUPPORT_RECIPIENT,
    reset_support_email_rate_limit,
)


@pytest.fixture(autouse=True)
def _clear_rate_limit():
    reset_support_email_rate_limit()
    yield
    reset_support_email_rate_limit()


def _auth(user: User) -> dict[str, str]:
    token = create_access_token(
        str(user.id),
        extra={
            "role": user.role.value,
            "business_id": str(user.business_id) if user.business_id else None,
        },
    )
    return {"Authorization": f"Bearer {token}"}


def _business(db, name: str) -> Business:
    row = Business(
        business_code=f"SP{uuid.uuid4().hex[:8].upper()}",
        name=name,
        status=BusinessStatus.active,
    )
    db.add(row)
    db.commit()
    db.refresh(row)
    return row


def _user(db, *, role: UserRole, business: Business | None, email: str) -> User:
    row = User(
        business_id=business.id if business else None,
        email=email,
        password_hash=hash_password("SupportTest!23"),
        role=role,
        must_change_password=False,
        is_active=True,
    )
    db.add(row)
    db.commit()
    db.refresh(row)
    return row


def _owner_world(db):
    business = _business(db, "North Pier Cafe")
    owner = _user(
        db,
        role=UserRole.owner,
        business=business,
        email=f"owner-{uuid.uuid4().hex[:8]}@example.com",
    )
    db.add(
        Employee(
            business_id=business.id,
            user_id=owner.id,
            full_name="Mina North",
            phone="09170001111",
        )
    )
    db.commit()
    return business, owner


def _configure_smtp(monkeypatch):
    from app.core.config import settings

    monkeypatch.setattr(settings, "smtp_host", "smtp.example.test")
    monkeypatch.setattr(settings, "smtp_from_email", "noreply@example.test")
    monkeypatch.setattr(settings, "smtp_username", "smtp-user")
    monkeypatch.setattr(settings, "smtp_password", "smtp-secret")


def _capture_send(monkeypatch):
    sent: list[dict] = []

    def fake_send(to_email, subject, text_body, html_body, *, reply_to=None):
        sent.append(
            {
                "to": to_email,
                "subject": subject,
                "text": text_body,
                "html": html_body,
                "reply_to": reply_to,
            }
        )

    monkeypatch.setattr("app.services.support_email.send_message", fake_send)
    return sent


def test_owner_support_email_uses_account_identity_and_fixed_recipient(monkeypatch):
    _configure_smtp(monkeypatch)
    sent = _capture_send(monkeypatch)
    db = SessionLocal()
    try:
        business, owner = _owner_world(db)
        business_code = business.business_code
        owner_email = owner.email
        client = TestClient(app)
        response = client.post(
            "/api/v1/owner/support-email",
            headers=_auth(owner),
            json={
                "subject": "Scanner will not open",
                "message": "The attendance scanner shows a blank page.",
            },
        )
    finally:
        db.close()

    assert response.status_code == 200
    body = response.json()
    assert body["status"] == "accepted"
    assert "not guaranteed" in body["detail"]
    assert len(sent) == 1
    assert sent[0]["to"] == SUPPORT_RECIPIENT == "arollplus1111@gmail.com"
    assert sent[0]["subject"] == "[Aroll+ Support] Scanner will not open"
    assert "North Pier Cafe" in sent[0]["text"]
    assert "Mina North" in sent[0]["text"]
    assert owner_email in sent[0]["text"]
    assert business_code not in sent[0]["text"]
    assert sent[0]["reply_to"] == owner_email


def test_support_email_escapes_message_html(monkeypatch):
    _configure_smtp(monkeypatch)
    sent = _capture_send(monkeypatch)
    db = SessionLocal()
    try:
        _business_unused, owner = _owner_world(db)
        client = TestClient(app)
        response = client.post(
            "/api/v1/owner/support-email",
            headers=_auth(owner),
            json={"subject": "Display", "message": "<script>alert(1)</script>"},
        )
    finally:
        db.close()
    assert response.status_code == 200
    assert "<script>" not in sent[0]["html"]
    assert "&lt;script&gt;" in sent[0]["html"]


def test_smtp_sender_uses_configured_from_and_reply_to(monkeypatch):
    _configure_smtp(monkeypatch)
    captured: dict = {}

    class FakeSMTP:
        def __init__(self, host, port, timeout=30):
            captured["host"] = host
            captured["port"] = port

        def starttls(self, context=None):
            captured["tls"] = True

        def login(self, username, password):
            captured["username"] = username
            assert password == "smtp-secret"

        def send_message(self, message):
            captured["message"] = message

        def quit(self):
            captured["quit"] = True

    monkeypatch.setattr("app.services.approval_email.smtplib.SMTP", FakeSMTP)
    from app.services.approval_email import send_message

    send_message(
        SUPPORT_RECIPIENT,
        "[Aroll+ Support] Hello",
        "plain",
        "<p>plain</p>",
        reply_to="owner@example.com",
    )
    message = captured["message"]
    assert captured["host"] == "smtp.example.test"
    assert captured["quit"] is True
    assert message["From"] == "noreply@example.test"
    assert message["To"] == SUPPORT_RECIPIENT
    assert message["Reply-To"] == "owner@example.com"
    assert message["Subject"] == "[Aroll+ Support] Hello"


def test_support_email_requires_authentication():
    client = TestClient(app)
    response = client.post(
        "/api/v1/owner/support-email",
        json={"subject": "Hello", "message": "Need help"},
    )
    assert response.status_code == 401


@pytest.mark.parametrize("role", [UserRole.manager, UserRole.employee, UserRole.platform_admin])
def test_support_email_rejects_other_roles(monkeypatch, role):
    _configure_smtp(monkeypatch)
    sent = _capture_send(monkeypatch)
    db = SessionLocal()
    try:
        business = None if role == UserRole.platform_admin else _business(db, "Other Role Cafe")
        user = _user(
            db,
            role=role,
            business=business,
            email=f"{role.value}-{uuid.uuid4().hex[:8]}@example.com",
        )
        client = TestClient(app)
        response = client.post(
            "/api/v1/owner/support-email",
            headers=_auth(user),
            json={"subject": "Hello", "message": "Need help"},
        )
    finally:
        db.close()
    assert response.status_code == 403
    assert sent == []


def test_support_email_rejects_blank_and_header_injection(monkeypatch):
    _configure_smtp(monkeypatch)
    sent = _capture_send(monkeypatch)
    db = SessionLocal()
    try:
        _business_row, owner = _owner_world(db)
        client = TestClient(app)
        blank = client.post(
            "/api/v1/owner/support-email",
            headers=_auth(owner),
            json={"subject": "   ", "message": "Need help"},
        )
        injected = client.post(
            "/api/v1/owner/support-email",
            headers=_auth(owner),
            json={"subject": "Hello\nBcc: evil@example.com", "message": "Need help"},
        )
        too_long = client.post(
            "/api/v1/owner/support-email",
            headers=_auth(owner),
            json={"subject": "Hello", "message": "x" * 4001},
        )
    finally:
        db.close()
    assert blank.status_code == 422
    assert injected.status_code == 422
    assert too_long.status_code == 422
    assert sent == []


def test_client_cannot_choose_recipient_or_business_name(monkeypatch):
    _configure_smtp(monkeypatch)
    sent = _capture_send(monkeypatch)
    db = SessionLocal()
    try:
        _business_row, owner = _owner_world(db)
        client = TestClient(app)
        response = client.post(
            "/api/v1/owner/support-email",
            headers=_auth(owner),
            json={
                "subject": "Hello",
                "message": "Need help",
                "recipient": "other@example.com",
                "business_name": "Fake Cafe",
            },
        )
    finally:
        db.close()
    assert response.status_code == 422
    assert sent == []


def test_missing_smtp_configuration_is_a_safe_error(monkeypatch):
    from app.core.config import settings

    monkeypatch.setattr(settings, "smtp_host", "")
    monkeypatch.setattr(settings, "smtp_from_email", "")
    sent = _capture_send(monkeypatch)
    db = SessionLocal()
    try:
        _business_row, owner = _owner_world(db)
        client = TestClient(app)
        response = client.post(
            "/api/v1/owner/support-email",
            headers=_auth(owner),
            json={"subject": "Hello", "message": "Need help"},
        )
    finally:
        db.close()
    assert response.status_code == 503
    assert response.json()["detail"].startswith("Email delivery is not configured")
    assert "traceback" not in response.text.lower()
    assert sent == []


def test_provider_failure_hides_internal_details(monkeypatch, caplog):
    _configure_smtp(monkeypatch)

    def boom(*_args, **_kwargs):
        raise RuntimeError("smtp password secret-token rejected")

    monkeypatch.setattr("app.services.support_email.send_message", boom)
    db = SessionLocal()
    try:
        _business_row, owner = _owner_world(db)
        client = TestClient(app)
        with caplog.at_level("WARNING"):
            response = client.post(
                "/api/v1/owner/support-email",
                headers=_auth(owner),
                json={"subject": "Hello", "message": "Need help"},
            )
    finally:
        db.close()
    assert response.status_code == 502
    assert response.json()["detail"] == "The email provider could not accept the message."
    assert "secret-token" not in response.text
    assert "secret-token" not in caplog.text


def test_smtp_authentication_and_connection_failures_stay_safe(monkeypatch):
    import smtplib

    from app.services.approval_email import send_message
    from app.services.support_email import SupportEmailError, submit_owner_support_email

    class _User:
        id = uuid.uuid4()
        business_id = uuid.uuid4()
        email = "owner@example.com"

    class _Business:
        id = _User.business_id
        name = "North Pier Cafe"

    class _Employee:
        full_name = "Mina North"
        phone = "09170001111"

    class _Db:
        def get(self, _model, _business_id):
            return _Business()

        def query(self, _model):
            return self

        def filter(self, *_args):
            return self

        def one_or_none(self):
            return _Employee()

    def _reject(exc: Exception):
        def send(*_args, **_kwargs):
            raise exc

        monkeypatch.setattr("app.services.support_email.send_message", send)
        with pytest.raises(SupportEmailError) as caught:
            submit_owner_support_email(
                _Db(),
                _User(),
                subject="Scanner",
                message="The scanner is blank.",
            )
        assert caught.value.status_code == 502
        assert caught.value.message == "The email provider could not accept the message."
        assert "secret" not in caught.value.message

    _configure_smtp(monkeypatch)
    _reject(smtplib.SMTPAuthenticationError(535, b"secret-token"))
    _reject(OSError("connection secret-token refused"))

    class FakeSMTP:
        def __init__(self, host, port, timeout=30):
            self.host = host

        def starttls(self, context=None):
            return None

        def login(self, username, password):
            raise smtplib.SMTPAuthenticationError(535, b"secret-token")

        def quit(self):
            return None

    monkeypatch.setattr("app.services.approval_email.smtplib.SMTP", FakeSMTP)
    with pytest.raises(smtplib.SMTPAuthenticationError):
        send_message(
            SUPPORT_RECIPIENT,
            "[Aroll+ Support] Hello",
            "plain",
            "<p>plain</p>",
        )


def test_support_email_rate_limit(monkeypatch):
    _configure_smtp(monkeypatch)
    sent = _capture_send(monkeypatch)
    db = SessionLocal()
    try:
        _business_row, owner = _owner_world(db)
        client = TestClient(app)
        headers = _auth(owner)
        statuses = [
            client.post(
                "/api/v1/owner/support-email",
                headers=headers,
                json={"subject": f"Issue {index}", "message": "Need help"},
            ).status_code
            for index in range(6)
        ]
    finally:
        db.close()
    assert statuses[:5] == [200, 200, 200, 200, 200]
    assert statuses[5] == 429
    assert len(sent) == 5
