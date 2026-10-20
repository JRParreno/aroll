"""Employee recovery email and forgot-password OTP."""

from datetime import datetime, timedelta, timezone

import pytest
from fastapi.testclient import TestClient

from app.core.security import verify_password
from app.main import app
from app.models.password_reset import PasswordResetChallenge
from app.services.employee_password_reset import NEUTRAL_SENT_MESSAGE
from tests.test_legal_consent import _auth, _create_tenant


def _codes_from_messages(messages: list[tuple]) -> list[str]:
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


def test_recovery_email_is_required_only_for_new_accounts_and_saved_to_self(sent):
    db, _business, owner, employee_user, employee = _create_tenant()
    client = TestClient(app)
    try:
        assert employee.recovery_email_required is False
        open_app = client.get(
            "/api/v1/employee/dashboard",
            headers=_auth(employee_user),
        )
        assert open_app.status_code == 200

        employee.recovery_email_required = True
        db.commit()
        blocked = client.get(
            "/api/v1/employee/dashboard",
            headers=_auth(employee_user),
        )
        assert blocked.status_code == 403
        assert blocked.json()["detail"]["code"] == "recovery_email_required"

        saved = client.post(
            "/api/v1/employee/recovery-email",
            headers=_auth(employee_user),
            json={"email": "Casey.Reset@Example.com"},
        )
        assert saved.status_code == 200, saved.text
        assert saved.json()["recovery_email"] == "casey.reset@example.com"
        assert saved.json()["needs_recovery_email"] is False
        db.refresh(employee)
        assert employee.recovery_email == "casey.reset@example.com"

        listed = client.get("/api/v1/employees", headers=_auth(owner))
        assert listed.status_code == 200
        row = next(item for item in listed.json() if item["id"] == str(employee.id))
        assert row["recovery_email"] == "casey.reset@example.com"
        assert "code_hash" not in row
        assert "reset_token" not in row
        assert "temporary_password" in row

        invalid = client.post(
            "/api/v1/employee/recovery-email",
            headers=_auth(employee_user),
            json={"email": "not-an-email"},
        )
        assert invalid.status_code == 422
        db.refresh(employee)
        assert employee.recovery_email == "casey.reset@example.com"
    finally:
        db.close()


def test_forgot_password_otp_is_single_use_and_cooldown_is_enforced(sent):
    db, _business, _owner, employee_user, employee = _create_tenant()
    client = TestClient(app)
    try:
        employee.recovery_email = "casey.reset@example.com"
        db.commit()
        body = {
            "username": employee_user.email,
            "email": "Casey.Reset@Example.com",
        }
        first = client.post("/api/v1/auth/employee/password-reset/request", json=body)
        assert first.status_code == 200, first.text
        assert first.json()["message"] == NEUTRAL_SENT_MESSAGE
        assert 170 <= first.json()["retry_after_seconds"] <= 180
        assert sent[0][0] == "casey.reset@example.com"
        code = _codes_from_messages(sent)[0]
        assert code not in first.text

        unknown = client.post(
            "/api/v1/auth/employee/password-reset/request",
            json={"username": "missing-user", "email": "nobody@example.com"},
        )
        assert unknown.status_code == 200
        assert unknown.json()["message"] == first.json()["message"]
        assert len(sent) == 1

        blocked = client.post("/api/v1/auth/employee/password-reset/request", json=body)
        assert blocked.status_code == 429
        assert len(sent) == 1

        wrong = client.post(
            "/api/v1/auth/employee/password-reset/verify",
            json={**body, "code": "000000" if code != "000000" else "000001"},
        )
        assert wrong.status_code == 400
        assert "incorrect" in wrong.json()["detail"]

        verified = client.post(
            "/api/v1/auth/employee/password-reset/verify",
            json={**body, "code": code},
        )
        assert verified.status_code == 200, verified.text
        token = verified.json()["reset_token"]
        assert code not in verified.text

        reused = client.post(
            "/api/v1/auth/employee/password-reset/verify",
            json={**body, "code": code},
        )
        assert reused.status_code == 400
        assert "already been used" in reused.json()["detail"]

        updated = client.post(
            "/api/v1/auth/employee/password-reset/complete",
            json={"reset_token": token, "new_password": "NewPass123!"},
        )
        assert updated.status_code == 200, updated.text
        assert "reset_token" not in updated.json()

        again = client.post(
            "/api/v1/auth/employee/password-reset/complete",
            json={"reset_token": token, "new_password": "OtherPass123!"},
        )
        assert again.status_code == 400

        login = client.post(
            "/api/v1/auth/login",
            json={"email": employee_user.email, "password": "NewPass123!"},
        )
        assert login.status_code == 200, login.text
        assert "NewPass123!" not in login.text
    finally:
        db.close()


def test_replacement_code_invalidates_the_previous_code(sent):
    db, _business, _owner, employee_user, employee = _create_tenant()
    client = TestClient(app)
    try:
        employee.recovery_email = "casey.reset@example.com"
        db.commit()
        body = {"username": employee_user.email, "email": employee.recovery_email}
        client.post("/api/v1/auth/employee/password-reset/request", json=body)
        first_code = _codes_from_messages(sent)[0]
        challenge = (
            db.query(PasswordResetChallenge)
            .filter(PasswordResetChallenge.user_id == employee_user.id)
            .one()
        )
        challenge.resend_available_at = datetime.now(timezone.utc) - timedelta(seconds=1)
        db.commit()
        client.post("/api/v1/auth/employee/password-reset/request", json=body)
        second_code = _codes_from_messages(sent)[1]
        assert first_code != second_code
        old = client.post(
            "/api/v1/auth/employee/password-reset/verify",
            json={**body, "code": first_code},
        )
        assert old.status_code == 400
        new = client.post(
            "/api/v1/auth/employee/password-reset/verify",
            json={**body, "code": second_code},
        )
        assert new.status_code == 200
    finally:
        db.close()


def test_expired_and_excessive_attempts_are_rejected(sent):
    db, _business, _owner, employee_user, employee = _create_tenant()
    client = TestClient(app)
    try:
        employee.recovery_email = "casey.reset@example.com"
        db.commit()
        body = {"username": employee_user.email, "email": employee.recovery_email}
        client.post("/api/v1/auth/employee/password-reset/request", json=body)
        code = _codes_from_messages(sent)[0]
        challenge = (
            db.query(PasswordResetChallenge)
            .filter(PasswordResetChallenge.user_id == employee_user.id)
            .one()
        )
        challenge.code_expires_at = datetime.now(timezone.utc) - timedelta(minutes=1)
        db.commit()
        expired = client.post(
            "/api/v1/auth/employee/password-reset/verify",
            json={**body, "code": code},
        )
        assert expired.status_code == 400
        assert "expired" in expired.json()["detail"]

        challenge = (
            db.query(PasswordResetChallenge)
            .filter(PasswordResetChallenge.user_id == employee_user.id)
            .one()
        )
        challenge.code_expires_at = datetime.now(timezone.utc) + timedelta(minutes=5)
        challenge.attempt_count = 0
        db.commit()
        for _ in range(5):
            failed = client.post(
                "/api/v1/auth/employee/password-reset/verify",
                json={**body, "code": "111111" if code != "111111" else "222222"},
            )
            assert failed.status_code == 400
        locked = client.post(
            "/api/v1/auth/employee/password-reset/verify",
            json={**body, "code": code},
        )
        assert locked.status_code == 400
        assert "Too many attempts" in locked.json()["detail"] or "incorrect" in locked.json()["detail"]
        db.refresh(challenge)
        assert challenge.code_hash is None or not verify_password(code, challenge.code_hash)
    finally:
        db.close()


def test_email_failure_does_not_report_success_or_store_a_code(sent, monkeypatch):
    db, _business, _owner, employee_user, employee = _create_tenant()
    client = TestClient(app)
    try:
        employee.recovery_email = "casey.reset@example.com"
        db.commit()

        def _fail(*_args, **_kwargs):
            raise RuntimeError("smtp secret should not leak")

        monkeypatch.setattr(
            "app.services.employee_password_reset.send_message",
            _fail,
        )
        failed = client.post(
            "/api/v1/auth/employee/password-reset/request",
            json={"username": employee_user.email, "email": employee.recovery_email},
        )
        assert failed.status_code == 503
        assert "smtp secret" not in failed.text
        assert "couldn't send" in failed.json()["detail"]
        assert (
            db.query(PasswordResetChallenge)
            .filter(PasswordResetChallenge.user_id == employee_user.id)
            .count()
            == 0
        )
    finally:
        db.close()


def test_authenticated_password_change_still_works_without_recovery_email():
    db, _business, _owner, employee_user, employee = _create_tenant()
    client = TestClient(app)
    try:
        changed = client.post(
            "/api/v1/auth/change-password",
            headers=_auth(employee_user),
            json={
                "current_password": "EmpPass123!",
                "new_password": "Changed123!",
            },
        )
        assert changed.status_code == 200, changed.text
        assert changed.json()["must_change_password"] is False
        db.refresh(employee)
        assert employee.recovery_email is None
        login = client.post(
            "/api/v1/auth/login",
            json={"email": employee_user.email, "password": "Changed123!"},
        )
        assert login.status_code == 200
    finally:
        db.close()
