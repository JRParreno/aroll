"""Owner forgot-password uses the shared employee recovery service."""

from datetime import datetime, timedelta, timezone

import pytest
from fastapi.testclient import TestClient

from app.core.security import hash_password, verify_password
from app.main import app
from app.models.enums import UserRole
from app.models.password_reset import PasswordResetChallenge
from app.models.user import User
from app.services.employee_password_reset import OWNER_NEUTRAL_SENT_MESSAGE
from tests.test_legal_consent import _create_tenant


def _codes(messages: list[tuple]) -> list[str]:
    codes = []
    for _to, _subject, text, _html in messages:
        for line in text.splitlines():
            stripped = line.strip()
            if stripped.isdigit() and len(stripped) == 6:
                codes.append(stripped)
    return codes


@pytest.fixture()
def sent(monkeypatch):
    messages: list[tuple] = []

    def _send(to_email, subject, text_body, html_body):
        messages.append((to_email, subject, text_body, html_body))

    monkeypatch.setattr(
        "app.services.employee_password_reset.smtp_configured",
        lambda: True,
    )
    monkeypatch.setattr(
        "app.services.employee_password_reset.send_message",
        _send,
    )
    return messages


def test_owner_reset_requires_matching_email_and_business_code(sent):
    db, business, owner, employee_user, employee = _create_tenant()
    other_db, other_business, other_owner, _other_employee_user, _other_emp = (
        _create_tenant()
    )
    client = TestClient(app)
    try:
        employee.recovery_email = "employee.reset@example.com"
        manager = User(
            business_id=business.id,
            email="manager.reset@example.com",
            password_hash=hash_password("ManagerPass123!"),
            role=UserRole.manager,
            must_change_password=False,
            is_active=True,
        )
        db.add(manager)
        db.commit()
        original_email = owner.email
        body = {
            "email": owner.email.upper(),
            "business_code": f" {business.business_code.lower()} ",
        }

        first = client.post("/api/v1/auth/owner/password-reset/request", json=body)
        assert first.status_code == 200, first.text
        assert first.json()["message"] == OWNER_NEUTRAL_SENT_MESSAGE
        assert 170 <= first.json()["retry_after_seconds"] <= 180
        assert sent[0][0] == original_email
        assert "owner password" in sent[0][2]
        code = _codes(sent)[0]
        assert code not in first.text
        db.refresh(owner)
        assert owner.email == original_email

        mismatches = [
            {"email": "missing@example.com", "business_code": business.business_code},
            {"email": owner.email, "business_code": "NO-SUCH"},
            {"email": owner.email, "business_code": other_business.business_code},
            {"email": other_owner.email, "business_code": business.business_code},
            {"email": employee.recovery_email, "business_code": business.business_code},
            {"email": manager.email, "business_code": business.business_code},
        ]
        for payload in mismatches:
            response = client.post(
                "/api/v1/auth/owner/password-reset/request",
                json=payload,
            )
            assert response.status_code in (200, 429), response.text
            assert code not in response.text
        assert len(sent) == 1

        employee_body = {
            "username": owner.email,
            "email": owner.email,
        }
        employee_request = client.post(
            "/api/v1/auth/employee/password-reset/request",
            json=employee_body,
        )
        assert employee_request.status_code == 200
        assert len(sent) == 1

        wrong_context = client.post(
            "/api/v1/auth/employee/password-reset/verify",
            json={**employee_body, "code": code},
        )
        assert wrong_context.status_code == 400

        verified = client.post(
            "/api/v1/auth/owner/password-reset/verify",
            json={**body, "code": code},
        )
        assert verified.status_code == 200, verified.text
        token = verified.json()["reset_token"]
        assert code not in verified.text

        employee_complete = client.post(
            "/api/v1/auth/employee/password-reset/complete",
            json={"reset_token": token, "new_password": "StolenPass123!"},
        )
        assert employee_complete.status_code == 400
        db.refresh(owner)
        assert verify_password("OwnerPass123!", owner.password_hash)

        updated = client.post(
            "/api/v1/auth/owner/password-reset/complete",
            json={"reset_token": token, "new_password": "NewOwner123!"},
        )
        assert updated.status_code == 200, updated.text
        assert "reset_token" not in updated.json()
        assert "NewOwner123!" not in updated.text

        reused = client.post(
            "/api/v1/auth/owner/password-reset/complete",
            json={"reset_token": token, "new_password": "OtherOwner123!"},
        )
        assert reused.status_code == 400

        login = client.post(
            "/api/v1/auth/business-owner-login",
            json={
                "business_code": business.business_code,
                "email": owner.email,
                "password": "NewOwner123!",
            },
        )
        assert login.status_code == 200, login.text
        assert "access_token" in login.json()
        old = client.post(
            "/api/v1/auth/business-owner-login",
            json={
                "business_code": business.business_code,
                "email": owner.email,
                "password": "OwnerPass123!",
            },
        )
        assert old.status_code == 401
    finally:
        db.close()
        other_db.close()


def test_employee_reset_cannot_reset_an_owner(sent):
    db, business, owner, employee_user, employee = _create_tenant()
    client = TestClient(app)
    try:
        employee.recovery_email = "casey.reset@example.com"
        db.commit()
        employee_body = {
            "username": employee_user.email,
            "email": employee.recovery_email,
        }
        requested = client.post(
            "/api/v1/auth/employee/password-reset/request",
            json=employee_body,
        )
        assert requested.status_code == 200, requested.text
        code = _codes(sent)[0]
        owner_verify = client.post(
            "/api/v1/auth/owner/password-reset/verify",
            json={
                "email": owner.email,
                "business_code": business.business_code,
                "code": code,
            },
        )
        assert owner_verify.status_code == 400
        verified = client.post(
            "/api/v1/auth/employee/password-reset/verify",
            json={**employee_body, "code": code},
        )
        assert verified.status_code == 200, verified.text
        blocked = client.post(
            "/api/v1/auth/owner/password-reset/complete",
            json={
                "reset_token": verified.json()["reset_token"],
                "new_password": "OwnerSteal123!",
            },
        )
        assert blocked.status_code == 400
        db.refresh(owner)
        assert verify_password("OwnerPass123!", owner.password_hash)
        db.refresh(employee_user)
        assert verify_password("EmpPass123!", employee_user.password_hash)
    finally:
        db.close()


def test_owner_email_failure_does_not_report_success(sent, monkeypatch):
    db, business, owner, _employee_user, _employee = _create_tenant()
    client = TestClient(app)
    try:
        def _fail(*_args, **_kwargs):
            raise RuntimeError("smtp secret should not leak")

        monkeypatch.setattr(
            "app.services.employee_password_reset.send_message",
            _fail,
        )
        failed = client.post(
            "/api/v1/auth/owner/password-reset/request",
            json={"email": owner.email, "business_code": business.business_code},
        )
        assert failed.status_code == 503
        assert "smtp secret" not in failed.text
        assert "couldn't send" in failed.json()["detail"]
        assert (
            db.query(PasswordResetChallenge)
            .filter(PasswordResetChallenge.user_id == owner.id)
            .count()
            == 0
        )
    finally:
        db.close()


def test_owner_replacement_code_invalidates_the_previous_code(sent):
    db, business, owner, _employee_user, _employee = _create_tenant()
    client = TestClient(app)
    try:
        body = {"email": owner.email, "business_code": business.business_code}
        client.post("/api/v1/auth/owner/password-reset/request", json=body)
        first_code = _codes(sent)[0]
        challenge = (
            db.query(PasswordResetChallenge)
            .filter(PasswordResetChallenge.user_id == owner.id)
            .one()
        )
        challenge.resend_available_at = datetime.now(timezone.utc) - timedelta(seconds=1)
        db.commit()
        client.post("/api/v1/auth/owner/password-reset/request", json=body)
        second_code = _codes(sent)[1]
        assert first_code != second_code
        assert sent[1][0] == owner.email
        old = client.post(
            "/api/v1/auth/owner/password-reset/verify",
            json={**body, "code": first_code},
        )
        assert old.status_code == 400
        new = client.post(
            "/api/v1/auth/owner/password-reset/verify",
            json={**body, "code": second_code},
        )
        assert new.status_code == 200
    finally:
        db.close()
