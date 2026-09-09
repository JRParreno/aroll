"""Employee legal consent persistence and per-business consent webpage."""

from fastapi.testclient import TestClient

from app.db.session import SessionLocal
from app.main import app
from app.models.employee import Employee
from app.models.user import User
from app.seed_demo import (
    DEMO_BUSINESS_CODE,
    DEMO_BUSINESS_NAME,
    DEMO_EMPLOYEE_01_EMAIL,
    DEMO_OWNER_EMAIL,
    DEMO_SEED_PASSWORD,
    seed_demo,
)


def _employee_token(client: TestClient) -> str:
    login = client.post(
        "/api/v1/auth/login",
        json={"email": DEMO_EMPLOYEE_01_EMAIL, "password": DEMO_SEED_PASSWORD},
    )
    assert login.status_code == 200, login.text
    return login.json()["access_token"]


def _owner_token(client: TestClient) -> str:
    login = client.post(
        "/api/v1/auth/business-owner-login",
        json={
            "business_code": DEMO_BUSINESS_CODE,
            "email": DEMO_OWNER_EMAIL,
            "password": DEMO_SEED_PASSWORD,
        },
    )
    assert login.status_code == 200, login.text
    return login.json()["access_token"]


def _reset_hannah_consent() -> None:
    db = SessionLocal()
    try:
        employee = (
            db.query(Employee)
            .join(User, Employee.user_id == User.id)
            .filter(User.email == DEMO_EMPLOYEE_01_EMAIL)
            .one()
        )
        employee.legal_consent_accepted = False
        employee.legal_consent_accepted_at = None
        db.commit()
    finally:
        db.close()


def test_public_legal_page_is_business_specific():
    seed_demo()
    client = TestClient(app)
    response = client.get(f"/api/v1/public/legal/{DEMO_BUSINESS_CODE}")
    assert response.status_code == 200, response.text
    body = response.json()
    assert body["business_code"] == DEMO_BUSINESS_CODE
    assert body["business_name"] == DEMO_BUSINESS_NAME
    assert body["legal_consent_url"] == f"/legal/b/{DEMO_BUSINESS_CODE}"
    assert "Demo Café" in body["content"] or "Demo" in body["content"]
    assert "live camera" in body["content"].lower() or "GPS" in body["content"]

    html = client.get(f"/api/v1/public/legal/{DEMO_BUSINESS_CODE}/page")
    assert html.status_code == 200
    assert "text/html" in html.headers["content-type"]
    assert DEMO_BUSINESS_NAME in html.text

    missing = client.get("/api/v1/public/legal/NOPE99")
    assert missing.status_code == 404


def test_employee_consent_flag_is_persisted_and_skips_repeat_prompt():
    seed_demo()
    _reset_hannah_consent()
    client = TestClient(app)
    token = _employee_token(client)
    headers = {"Authorization": f"Bearer {token}"}

    me = client.get("/api/v1/auth/me", headers=headers)
    assert me.status_code == 200
    payload = me.json()
    assert payload["legal_consent_accepted"] is False
    assert payload["legal_consent_url"] == f"/legal/b/{DEMO_BUSINESS_CODE}"
    assert payload["legal_consent_page_url"].endswith(
        f"/api/v1/public/legal/{DEMO_BUSINESS_CODE}/page"
    )

    status = client.get("/api/v1/employee/legal-consent", headers=headers)
    assert status.status_code == 200
    assert status.json()["accepted"] is False
    assert status.json()["content"]

    files = [
        ("files", ("a.jpg", b"\xff\xd8\xff\xd9x", "image/jpeg")),
        ("files", ("b.jpg", b"\xff\xd8\xff\xd9x", "image/jpeg")),
        ("files", ("c.jpg", b"\xff\xd8\xff\xd9x", "image/jpeg")),
    ]
    blocked = client.post(
        "/api/v1/employee/face-samples",
        files=files,
        headers=headers,
    )
    assert blocked.status_code == 403
    assert blocked.json()["detail"]["code"] == "legal_consent_required"

    accepted = client.post(
        "/api/v1/employee/legal-consent",
        json={"accepted": True},
        headers=headers,
    )
    assert accepted.status_code == 200, accepted.text
    assert accepted.json()["accepted"] is True
    assert accepted.json()["accepted_at"] is not None

    me_after = client.get("/api/v1/auth/me", headers=headers)
    assert me_after.json()["legal_consent_accepted"] is True

    still_blocked_by_demo = client.post(
        "/api/v1/employee/face-samples",
        files=files,
        headers=headers,
    )
    assert still_blocked_by_demo.status_code == 403
    assert still_blocked_by_demo.json()["detail"]["code"] == "demo_enrollment_locked"


def test_owner_can_configure_business_consent_content():
    seed_demo()
    client = TestClient(app)
    token = _owner_token(client)
    headers = {"Authorization": f"Bearer {token}"}

    current = client.get("/api/v1/businesses/me/business-settings", headers=headers)
    assert current.status_code == 200, current.text
    settings = current.json()
    assert settings["legal_consent_url"] == f"/legal/b/{DEMO_BUSINESS_CODE}"

    custom = "Custom Cafe consent page for employees.\nFace enrollment requires agreement."
    saved = client.put(
        "/api/v1/businesses/me/business-settings",
        json={
            "business_name": settings["business_name"],
            "business_type": settings["business_type"],
            "address": settings["address"] or "123 Demo Street",
            "legal_consent_content": custom,
        },
        headers=headers,
    )
    assert saved.status_code == 200, saved.text

    public = client.get(f"/api/v1/public/legal/{DEMO_BUSINESS_CODE}")
    assert public.status_code == 200
    assert public.json()["content"] == custom
