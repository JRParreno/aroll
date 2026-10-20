"""Tests for POST /auth/change-password."""

import uuid

from fastapi.testclient import TestClient

from app.core.security import hash_password, verify_password
from app.db.session import SessionLocal
from app.main import app
from app.models.business import Business
from app.models.enums import UserRole
from app.models.user import User


def _create_owner(*, password: str) -> tuple[User, Business]:
    db = SessionLocal()
    try:
        owner = User(
            email=f"owner-cp-{uuid.uuid4().hex[:8]}@example.com",
            password_hash=hash_password(password),
            role=UserRole.owner,
            must_change_password=False,
            is_active=True,
        )
        db.add(owner)
        db.flush()
        business = Business(
            business_code=f"MB-{uuid.uuid4().hex[:6].upper()}",
            name="Change Password Biz",
        )
        db.add(business)
        db.flush()
        owner.business_id = business.id
        db.commit()
        db.refresh(owner)
        db.refresh(business)
        return owner, business
    finally:
        db.close()


def test_change_password_rejects_incorrect_current_password():
    old_password = "OwnerPass123!"
    owner, business = _create_owner(password=old_password)
    client = TestClient(app)

    login = client.post(
        "/api/v1/auth/business-owner-login",
        json={
            "business_code": business.business_code,
            "email": owner.email,
            "password": old_password,
        },
    )
    assert login.status_code == 200
    token = login.json()["access_token"]

    response = client.post(
        "/api/v1/auth/change-password",
        headers={"Authorization": f"Bearer {token}"},
        json={
            "current_password": "WrongPass123!",
            "new_password": "NewOwnerPass123!",
        },
    )
    assert response.status_code == 400
    assert response.json()["detail"] == "Current password is incorrect"


def test_change_password_updates_hash_and_allows_new_login():
    old_password = "OwnerPass123!"
    new_password = "NewOwnerPass123!"
    owner, business = _create_owner(password=old_password)
    client = TestClient(app)

    login = client.post(
        "/api/v1/auth/business-owner-login",
        json={
            "business_code": business.business_code,
            "email": owner.email,
            "password": old_password,
        },
    )
    assert login.status_code == 200
    token = login.json()["access_token"]

    response = client.post(
        "/api/v1/auth/change-password",
        headers={"Authorization": f"Bearer {token}"},
        json={
            "current_password": old_password,
            "new_password": new_password,
        },
    )
    assert response.status_code == 200
    assert response.json()["access_token"]
    assert response.json()["must_change_password"] is False

    db = SessionLocal()
    try:
        refreshed = db.get(User, owner.id)
        assert refreshed is not None
        assert verify_password(new_password, refreshed.password_hash)
        assert not verify_password(old_password, refreshed.password_hash)
    finally:
        db.close()

    old_login = client.post(
        "/api/v1/auth/business-owner-login",
        json={
            "business_code": business.business_code,
            "email": owner.email,
            "password": old_password,
        },
    )
    assert old_login.status_code == 401

    new_login = client.post(
        "/api/v1/auth/business-owner-login",
        json={
            "business_code": business.business_code,
            "email": owner.email,
            "password": new_password,
        },
    )
    assert new_login.status_code == 200
    assert new_login.json()["access_token"]
