"""Holiday OT premium API parity for Owner Web and Mobile."""

import uuid
from datetime import date

from fastapi.testclient import TestClient

from app.core.security import create_access_token, hash_password
from app.db.session import SessionLocal
from app.main import app
from app.models.business import Business
from app.models.enums import UserRole
from app.models.user import User


def _auth_headers(user: User) -> dict[str, str]:
    token = create_access_token(
        str(user.id),
        extra={
            "role": user.role.value,
            "business_id": str(user.business_id) if user.business_id else None,
        },
    )
    return {"Authorization": f"Bearer {token}"}


def _create_owner():
    db = SessionLocal()
    business = Business(
        business_code=f"HO-{uuid.uuid4().hex[:6].upper()}",
        name="Holiday OT Biz",
    )
    db.add(business)
    db.flush()
    owner = User(
        business_id=business.id,
        email=f"owner-{uuid.uuid4().hex[:8]}@example.com",
        password_hash=hash_password("OwnerPass123!"),
        role=UserRole.owner,
        must_change_password=False,
        is_active=True,
    )
    db.add(owner)
    db.commit()
    db.refresh(owner)
    return db, owner


def test_payroll_config_omits_legacy_business_ot_fields():
    db, owner = _create_owner()
    client = TestClient(app)
    headers = _auth_headers(owner)
    try:
        response = client.get("/api/v1/businesses/me/payroll-config", headers=headers)
        assert response.status_code == 200
        data = response.json()
        assert "ordinary_ot_premium_percent" in data
        assert "rest_day_ot_premium_percent" in data
        assert "special_day_ot_premium_percent" not in data
        assert "regular_holiday_ot_premium_percent" not in data
        assert "holiday_rest_day_ot_premium_percent" not in data

        ignored = client.put(
            "/api/v1/businesses/me/payroll-config",
            json={
                **data,
                "special_day_ot_premium_percent": 99,
                "regular_holiday_ot_premium_percent": 98,
                "holiday_rest_day_ot_premium_percent": 97,
            },
            headers=headers,
        )
        assert ignored.status_code == 200
        again = client.get("/api/v1/businesses/me/payroll-config", headers=headers)
        assert "special_day_ot_premium_percent" not in again.json()
    finally:
        db.close()


def test_holiday_ot_premium_create_get_null_vs_zero():
    db, owner = _create_owner()
    client = TestClient(app)
    headers = _auth_headers(owner)
    try:
        unset = client.post(
            "/api/v1/holidays",
            json={
                "name": "Unset OT",
                "holiday_date": date(2026, 9, 1).isoformat(),
                "is_paid": True,
                "pay_multiplier": 1.0,
                "holiday_type": "company",
            },
            headers=headers,
        )
        assert unset.status_code == 201
        unset_body = unset.json()
        assert unset_body["ot_premium_percent"] is None

        zero = client.post(
            "/api/v1/holidays",
            json={
                "name": "Zero OT",
                "holiday_date": date(2026, 9, 2).isoformat(),
                "is_paid": True,
                "pay_multiplier": 1.0,
                "ot_premium_percent": 0,
                "holiday_type": "company",
            },
            headers=headers,
        )
        assert zero.status_code == 201
        zero_body = zero.json()
        assert zero_body["ot_premium_percent"] == 0.0
        assert zero_body["ot_premium_percent"] is not None

        configured = client.post(
            "/api/v1/holidays",
            json={
                "name": "Configured OT",
                "holiday_date": date(2026, 9, 3).isoformat(),
                "is_paid": True,
                "pay_multiplier": 2.0,
                "ot_premium_percent": 30,
                "holiday_type": "company",
            },
            headers=headers,
        )
        assert configured.status_code == 201
        assert configured.json()["ot_premium_percent"] == 30.0

        listed = client.get("/api/v1/holidays", headers=headers)
        assert listed.status_code == 200
        by_name = {row["name"]: row for row in listed.json()}
        assert by_name["Unset OT"]["ot_premium_percent"] is None
        assert by_name["Zero OT"]["ot_premium_percent"] == 0.0
        assert by_name["Configured OT"]["ot_premium_percent"] == 30.0

        cleared = client.put(
            f"/api/v1/holidays/{configured.json()['id']}",
            json={"ot_premium_percent": None},
            headers=headers,
        )
        assert cleared.status_code == 200
        assert cleared.json()["ot_premium_percent"] is None
    finally:
        db.close()


def test_holiday_active_toggle_keeps_holiday_listed_without_changing_pay():
    db, owner = _create_owner()
    client = TestClient(app)
    headers = _auth_headers(owner)
    try:
        created = client.post(
            "/api/v1/holidays",
            json={
                "name": "Toggle Holiday",
                "holiday_date": date(2026, 9, 23).isoformat(),
                "is_paid": True,
                "pay_multiplier": 2.0,
                "ot_premium_percent": 30,
                "holiday_type": "company",
            },
            headers=headers,
        )
        assert created.status_code == 201
        holiday_id = created.json()["id"]
        assert created.json()["is_active"] is True

        turned_off = client.put(
            f"/api/v1/holidays/{holiday_id}",
            json={"is_active": False},
            headers=headers,
        )
        assert turned_off.status_code == 200
        body = turned_off.json()
        assert body["is_active"] is False
        assert body["pay_multiplier"] == 2.0
        assert body["is_paid"] is True
        assert body["ot_premium_percent"] == 30.0

        active_only = client.get("/api/v1/holidays", headers=headers)
        assert active_only.status_code == 200
        assert all(row["name"] != "Toggle Holiday" for row in active_only.json())

        listed = client.get(
            "/api/v1/holidays",
            params={"include_inactive": True},
            headers=headers,
        )
        assert listed.status_code == 200
        match = next(row for row in listed.json() if row["name"] == "Toggle Holiday")
        assert match["is_active"] is False
        assert match["pay_multiplier"] == 2.0

        turned_on = client.put(
            f"/api/v1/holidays/{holiday_id}",
            json={"is_active": True},
            headers=headers,
        )
        assert turned_on.status_code == 200
        assert turned_on.json()["is_active"] is True
        assert turned_on.json()["pay_multiplier"] == 2.0
        assert turned_on.json()["ot_premium_percent"] == 30.0
    finally:
        db.close()
