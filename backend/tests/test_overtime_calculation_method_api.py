"""Owner overtime method is stored per business and reloads unchanged."""

import uuid

from fastapi.testclient import TestClient

from app.core.security import create_access_token, hash_password
from app.db.session import SessionLocal
from app.main import app
from app.models.business import Business
from app.models.enums import UserRole
from app.models.payroll import BusinessPayrollConfig
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


def _create_owner(name: str):
    db = SessionLocal()
    business = Business(
        business_code=f"OT-{uuid.uuid4().hex[:6].upper()}",
        name=name,
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


def _cleanup(db, owner: User) -> None:
    business_id = owner.business_id
    db.query(BusinessPayrollConfig).filter(
        BusinessPayrollConfig.business_id == business_id
    ).delete()
    db.query(User).filter(User.id == owner.id).delete()
    db.query(Business).filter(Business.id == business_id).delete()
    db.commit()
    db.close()


def test_new_business_defaults_to_flat_and_persists_each_method():
    db, owner = _create_owner("Flat Default Biz")
    other_db, other = _create_owner("Other Biz")
    client = TestClient(app)
    headers = _auth_headers(owner)
    other_headers = _auth_headers(other)
    try:
        created = client.get("/api/v1/businesses/me/payroll-config", headers=headers)
        assert created.status_code == 200
        data = created.json()
        assert data["overtime_calculation_method"] == "flat_per_minute"
        saved_rate = data["overtime_per_minute"]

        hourly = client.put(
            "/api/v1/businesses/me/payroll-config",
            json={**data, "overtime_calculation_method": "hourly_statutory"},
            headers=headers,
        )
        assert hourly.status_code == 200

        reloaded = client.get(
            "/api/v1/businesses/me/payroll-config", headers=headers
        )
        assert reloaded.json()["overtime_calculation_method"] == "hourly_statutory"
        assert reloaded.json()["overtime_per_minute"] == saved_rate

        other_config = client.get(
            "/api/v1/businesses/me/payroll-config", headers=other_headers
        )
        assert other_config.status_code == 200
        assert other_config.json()["overtime_calculation_method"] == "flat_per_minute"

        flat = client.put(
            "/api/v1/businesses/me/payroll-config",
            json={
                **reloaded.json(),
                "overtime_calculation_method": "flat_per_minute",
                "overtime_per_minute": 2.25,
            },
            headers=headers,
        )
        assert flat.status_code == 200
        saved_flat = client.get(
            "/api/v1/businesses/me/payroll-config", headers=headers
        )
        assert saved_flat.json()["overtime_calculation_method"] == "flat_per_minute"
        assert saved_flat.json()["overtime_per_minute"] == 2.25

        omitted = client.put(
            "/api/v1/businesses/me/payroll-config",
            json={
                key: value
                for key, value in saved_flat.json().items()
                if key != "overtime_calculation_method"
            },
            headers=headers,
        )
        assert omitted.status_code == 200
        after_omit = client.get(
            "/api/v1/businesses/me/payroll-config", headers=headers
        )
        assert after_omit.json()["overtime_calculation_method"] == "flat_per_minute"
        assert after_omit.json()["overtime_per_minute"] == 2.25

        rejected = client.put(
            "/api/v1/businesses/me/payroll-config",
            json={**after_omit.json(), "overtime_calculation_method": "double_time"},
            headers=headers,
        )
        assert rejected.status_code == 422
        still = client.get("/api/v1/businesses/me/payroll-config", headers=headers)
        assert still.json()["overtime_calculation_method"] == "flat_per_minute"
        assert still.json()["overtime_per_minute"] == 2.25
    finally:
        _cleanup(db, owner)
        _cleanup(other_db, other)
