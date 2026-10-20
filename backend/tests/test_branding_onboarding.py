"""First-login branding progress: skip/complete persist, existing owners stay put."""

import uuid

from fastapi.testclient import TestClient

from app.core.security import create_access_token, hash_password
from app.db.session import SessionLocal
from app.main import app
from app.models.business import Business
from app.models.enums import EmploymentType, UserRole
from app.models.payroll import Position
from app.models.user import User
from app.services.setup_status import (
    BRANDING_ONBOARDING_DONE_KEY,
    needs_branding_onboarding,
)


def _auth_headers(user: User) -> dict[str, str]:
    token = create_access_token(
        str(user.id),
        extra={
            "role": user.role.value,
            "business_id": str(user.business_id) if user.business_id else None,
        },
    )
    return {"Authorization": f"Bearer {token}"}


def _create_owner(name="Branding Biz", setup_completed=False, theme=None):
    db = SessionLocal()
    business = Business(
        business_code=f"MB-{uuid.uuid4().hex[:6].upper()}",
        name=name,
        theme_settings=theme,
    )
    if setup_completed:
        from datetime import datetime, timezone

        business.setup_completed_at = datetime.now(timezone.utc)
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
    db.refresh(business)
    db.refresh(owner)
    return db, business, owner


def test_new_owner_needs_branding_onboarding():
    db, business, owner = _create_owner()
    client = TestClient(app)
    try:
        assert needs_branding_onboarding(db, business) is True
        me = client.get("/api/v1/auth/me", headers=_auth_headers(owner))
        assert me.status_code == 200
        assert me.json()["needs_branding_onboarding"] is True
        assert me.json()["setup_completed_at"] is None
    finally:
        db.rollback()
        db.close()


def test_existing_completed_owner_does_not_need_branding():
    db, business, owner = _create_owner(setup_completed=True)
    client = TestClient(app)
    try:
        assert needs_branding_onboarding(db, business) is False
        me = client.get("/api/v1/auth/me", headers=_auth_headers(owner))
        assert me.status_code == 200
        assert me.json()["needs_branding_onboarding"] is False
        assert me.json()["setup_completed_at"] is not None
    finally:
        db.rollback()
        db.close()


def test_mid_setup_owner_is_not_redirected_into_branding():
    db, business, owner = _create_owner()
    try:
        db.add(
            Position(
                business_id=business.id,
                title="Barista",
                employment_type=EmploymentType.full_time,
            )
        )
        db.commit()
        db.refresh(business)
        assert needs_branding_onboarding(db, business) is False
    finally:
        db.rollback()
        db.close()


def test_skip_branding_persists_without_overwriting_logo():
    existing_theme = {
        "primary_color": "#3D6280",
        "secondary_color": "#4A7090",
        "sidebar_color": "#35556F",
        "accent_color": "#5E86A3",
        "button_color": "#3A5C78",
        "card_style": "soft",
        "font_size": "comfortable",
        "color_mode": "light",
        "layout_density": "rounded",
    }
    db, business, owner = _create_owner(theme=dict(existing_theme))
    business.logo_url = "data:image/png;base64,keep-me"
    db.commit()
    client = TestClient(app)
    headers = _auth_headers(owner)
    try:
        skip = client.post(
            "/api/v1/businesses/me/branding-onboarding/complete",
            headers=headers,
            json={},
        )
        assert skip.status_code == 200
        assert skip.json()["needs_branding_onboarding"] is False

        db.refresh(business)
        assert business.logo_url == "data:image/png;base64,keep-me"
        assert business.theme_settings["primary_color"] == "#3D6280"
        assert business.theme_settings[BRANDING_ONBOARDING_DONE_KEY] is True

        me = client.get("/api/v1/auth/me", headers=headers)
        assert me.json()["needs_branding_onboarding"] is False
    finally:
        db.rollback()
        db.close()


def test_saving_branding_marks_onboarding_done_without_changing_address():
    db, business, owner = _create_owner()
    client = TestClient(app)
    headers = _auth_headers(owner)
    try:
        save = client.post(
            "/api/v1/businesses/me/branding-onboarding/complete",
            headers=headers,
            json={
                "branding": {
                    "logo_url": "data:image/png;base64,new-logo",
                    "owner_profile_image_url": None,
                    "display_image_url": "data:image/png;base64,new-logo",
                    "theme": {
                        "primary_color": "#426074",
                        "secondary_color": "#4E7084",
                        "sidebar_color": "#3A5568",
                        "accent_color": "#5C8498",
                        "button_color": "#3E5C70",
                        "card_style": "soft",
                        "font_size": "comfortable",
                        "color_mode": "light",
                        "layout_density": "rounded",
                    },
                }
            },
        )
        assert save.status_code == 200
        db.refresh(business)
        assert business.logo_url == "data:image/png;base64,new-logo"
        assert business.theme_settings["primary_color"] == "#426074"
        assert business.theme_settings[BRANDING_ONBOARDING_DONE_KEY] is True
        me = client.get("/api/v1/auth/me", headers=headers)
        assert me.json()["needs_branding_onboarding"] is False
    finally:
        db.rollback()
        db.close()
