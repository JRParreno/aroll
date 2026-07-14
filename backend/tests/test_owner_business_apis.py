"""Integration tests for owner profile image and business location APIs."""

import uuid

from fastapi.testclient import TestClient

from app.core.security import create_access_token, hash_password
from app.db.session import SessionLocal
from app.main import app
from app.models.business import Business
from app.models.enums import UserRole
from app.models.user import User

VALID_PROFILE_IMAGE = "data:image/png;base64,abcd"


def _auth_headers(user: User) -> dict[str, str]:
    token = create_access_token(
        str(user.id),
        extra={
            "role": user.role.value,
            "business_id": str(user.business_id) if user.business_id else None,
        },
    )
    return {"Authorization": f"Bearer {token}"}


def _create_business_with_users():
    db = SessionLocal()
    business = Business(
        business_code=f"MB-{uuid.uuid4().hex[:6].upper()}",
        name="API Test Biz",
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
    manager = User(
        business_id=business.id,
        email=f"manager-{uuid.uuid4().hex[:8]}@example.com",
        password_hash=hash_password("ManagerPass123!"),
        role=UserRole.manager,
        must_change_password=False,
        is_active=True,
    )
    db.add_all([owner, manager])
    db.commit()
    db.refresh(business)
    db.refresh(owner)
    db.refresh(manager)
    return db, business, owner, manager


def test_owner_profile_image_upload_and_remove():
    db, _business, owner, _manager = _create_business_with_users()
    client = TestClient(app)
    headers = _auth_headers(owner)
    try:
        upload = client.post(
            "/api/v1/businesses/me/profile/image",
            json={"image_data": VALID_PROFILE_IMAGE},
            headers=headers,
        )
        assert upload.status_code == 200
        assert upload.json()["owner_profile_image_url"] == VALID_PROFILE_IMAGE

        remove = client.delete(
            "/api/v1/businesses/me/profile/image",
            headers=headers,
        )
        assert remove.status_code == 200
        assert remove.json()["owner_profile_image_url"] is None
    finally:
        db.rollback()
        db.close()


def test_manager_can_upload_owner_profile_image():
    db, _business, _owner, manager = _create_business_with_users()
    client = TestClient(app)
    try:
        response = client.post(
            "/api/v1/businesses/me/profile/image",
            json={"image_data": VALID_PROFILE_IMAGE},
            headers=_auth_headers(manager),
        )
        assert response.status_code == 200
        assert response.json()["owner_profile_image_url"] == VALID_PROFILE_IMAGE
    finally:
        db.rollback()
        db.close()


def test_owner_update_location():
    db, _business, owner, _manager = _create_business_with_users()
    client = TestClient(app)
    try:
        response = client.put(
            "/api/v1/businesses/me/location",
            json={
                "label": "Main",
                "address": "123 Test Street, Manila",
                "latitude": 14.5995,
                "longitude": 120.9842,
                "geofence_radius_m": 75,
            },
            headers=_auth_headers(owner),
        )
        assert response.status_code == 200
        assert response.json()["status"] == "ok"

        location = client.get(
            "/api/v1/businesses/me/location",
            headers=_auth_headers(owner),
        )
        assert location.status_code == 200
        body = location.json()
        assert body["address"] == "123 Test Street, Manila"
        assert body["latitude"] == 14.5995
        assert body["longitude"] == 120.9842
        assert body["geofence_radius_m"] == 75
    finally:
        db.rollback()
        db.close()


def test_manager_cannot_update_location():
    db, _business, _owner, manager = _create_business_with_users()
    client = TestClient(app)
    try:
        response = client.put(
            "/api/v1/businesses/me/location",
            json={
                "label": "Main",
                "address": "456 Manager Street, Manila",
                "latitude": 14.5995,
                "longitude": 120.9842,
                "geofence_radius_m": 75,
            },
            headers=_auth_headers(manager),
        )
        assert response.status_code == 403
    finally:
        db.rollback()
        db.close()
