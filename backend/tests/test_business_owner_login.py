"""Tests for business owner authentication."""

import uuid

from fastapi.testclient import TestClient

from app.core.security import hash_password
from app.db.session import SessionLocal
from app.main import app
from app.models.business import Business
from app.models.enums import UserRole
from app.models.user import User


def test_business_owner_login_accepts_lowercase_business_code():
    db = SessionLocal()
    try:
        owner = User(
            email="owner-login-test@example.com",
            password_hash=hash_password("OwnerPass123!"),
            role=UserRole.owner,
            must_change_password=False,
            is_active=True,
        )
        db.add(owner)
        db.flush()

        business = Business(
            business_code=f"MB-{uuid.uuid4().hex[:6].upper()}",
            name="Login Test Biz",
        )
        db.add(business)
        db.flush()
        owner.business_id = business.id
        db.commit()

        client = TestClient(app)
        response = client.post(
            "/api/v1/auth/business-owner-login",
            json={
                "business_code": "mb-test01",
                "email": owner.email,
                "password": "OwnerPass123!",
            },
        )
        assert response.status_code == 200
        assert response.json()["access_token"]
    finally:
        db.rollback()
        db.close()


def test_business_owner_login_resolves_owner_when_email_is_shared():
    db = SessionLocal()
    try:
        business = Business(business_code=f"MB-{uuid.uuid4().hex[:6].upper()}", name="Shared Email Biz")
        db.add(business)
        db.flush()

        owner = User(
            business_id=business.id,
            email="shared@example.com",
            password_hash=hash_password("OwnerPass123!"),
            role=UserRole.owner,
            must_change_password=False,
            is_active=True,
        )
        employee_user = User(
            business_id=business.id,
            email="shared@example.com",
            password_hash=hash_password("EmployeePass123!"),
            role=UserRole.employee,
            must_change_password=False,
            is_active=True,
        )
        db.add_all([owner, employee_user])
        db.commit()

        client = TestClient(app)
        response = client.post(
            "/api/v1/auth/business-owner-login",
            json={
                "business_code": business.business_code,
                "email": "shared@example.com",
                "password": "OwnerPass123!",
            },
        )
        assert response.status_code == 200
        assert response.json()["role"] == "owner"
    finally:
        db.rollback()
        db.close()


def test_business_owner_login_accepts_business_code_for_first_time_owner():
    db = SessionLocal()
    try:
        code = f"MB-{uuid.uuid4().hex[:6].upper()}"
        business = Business(business_code=code, name="First Login Biz")
        db.add(business)
        db.flush()

        owner = User(
            business_id=business.id,
            email="first-owner@example.com",
            password_hash=hash_password(code),
            role=UserRole.owner,
            must_change_password=True,
            is_active=True,
        )
        db.add(owner)
        db.commit()

        client = TestClient(app)
        response = client.post(
            "/api/v1/auth/business-owner-login",
            json={
                "business_code": code,
                "email": owner.email,
                "password": "wrong-password-attempt",
            },
        )
        assert response.status_code == 200
        assert response.json()["must_change_password"] is True
    finally:
        db.rollback()
        db.close()
