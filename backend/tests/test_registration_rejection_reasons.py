"""Admin rejection checklist validation and persistence."""

from __future__ import annotations

import uuid
from datetime import datetime, timezone

from fastapi.testclient import TestClient

from app.core.security import create_access_token, hash_password
from app.db.session import SessionLocal
from app.main import app
from app.models.business import BusinessRegistration
from app.models.enums import ApplicationStatus, RegistrationStatus, UserRole
from app.models.user import User
from app.services.registration_rejection import (
    format_rejection_reasons,
    validate_rejection_reasons,
)


def _auth(user: User) -> dict[str, str]:
    token = create_access_token(
        str(user.id),
        extra={
            "role": user.role.value,
            "business_id": str(user.business_id) if user.business_id else None,
        },
    )
    return {"Authorization": f"Bearer {token}"}


def _platform_admin(db):
    admin = User(
        business_id=None,
        email=f"admin-{uuid.uuid4().hex[:8]}@example.com",
        password_hash=hash_password("AdminPass123!"),
        role=UserRole.platform_admin,
        must_change_password=False,
        is_active=True,
    )
    db.add(admin)
    db.commit()
    db.refresh(admin)
    return admin


def _pending_registration(db, **overrides):
    payload = {
        "business_name": "Harbor Cafe",
        "owner_name": "Jordan Owner",
        "owner_email": f"owner-{uuid.uuid4().hex[:8]}@example.com",
        "owner_phone": "09170000000",
        "proposed_address": "123 Harbor St",
        "business_type": "cafe",
        "status": RegistrationStatus.pending,
        "application_status": ApplicationStatus.pending,
        "submitted_at": datetime.now(timezone.utc),
    }
    payload.update(overrides)
    row = BusinessRegistration(**payload)
    db.add(row)
    db.commit()
    db.refresh(row)
    return row


def test_validate_rejection_reasons_rules():
    from fastapi import HTTPException

    assert validate_rejection_reasons(
        ["missing_documents", "incomplete_documents"]
    ) == ["missing_documents", "incomplete_documents"]
    try:
        validate_rejection_reasons([])
        raise AssertionError("empty reasons should fail")
    except HTTPException as exc:
        assert exc.status_code == 400
    try:
        validate_rejection_reasons(["not_a_real_reason"])
        raise AssertionError("unknown reasons should fail")
    except HTTPException as exc:
        assert exc.status_code == 400
    try:
        validate_rejection_reasons(["other"], "   ")
        raise AssertionError("other without explanation should fail")
    except HTTPException as exc:
        assert exc.status_code == 400
    assert validate_rejection_reasons(
        ["missing_documents"], "ignored extra explanation"
    ) == ["missing_documents"]
    stored = format_rejection_reasons(
        ["missing_documents", "other"],
        "Permit photo is cropped",
    )
    assert stored == (
        "Required documents are missing.\nPermit photo is cropped"
    )


def test_reject_accepts_multiple_reasons_and_rejects_invalid_payload(monkeypatch):
    monkeypatch.setattr("app.services.approval_email.send_message", lambda *a, **k: None)
    from app.core.config import settings

    monkeypatch.setattr(settings, "smtp_host", "smtp.example.test")
    monkeypatch.setattr(settings, "smtp_from_email", "noreply@example.test")
    monkeypatch.setattr(settings, "smtp_username", "smtp-user")
    monkeypatch.setattr(settings, "smtp_password", "smtp-secret")

    db = SessionLocal()
    client = TestClient(app)
    try:
        admin = _platform_admin(db)
        headers = _auth(admin)
        valid = _pending_registration(db)
        accepted = client.post(
            f"/api/v1/admin/registrations/{valid.id}/reject",
            json={
                "reasons": ["missing_documents", "other"],
                "other_explanation": "Permit photo is cropped",
            },
            headers=headers,
        )
        assert accepted.status_code == 200, accepted.text
        db.expire_all()
        saved = db.get(BusinessRegistration, valid.id)
        assert saved.application_status == ApplicationStatus.rejected
        assert saved.rejection_reason == (
            "Required documents are missing.\nPermit photo is cropped"
        )

        unknown = _pending_registration(db)
        bad_unknown = client.post(
            f"/api/v1/admin/registrations/{unknown.id}/reject",
            json={"reasons": ["forged_reason"]},
            headers=headers,
        )
        assert bad_unknown.status_code == 400
        db.expire_all()
        assert (
            db.get(BusinessRegistration, unknown.id).application_status
            == ApplicationStatus.pending
        )

        empty = _pending_registration(db)
        bad_empty = client.post(
            f"/api/v1/admin/registrations/{empty.id}/reject",
            json={"reasons": []},
            headers=headers,
        )
        assert bad_empty.status_code == 422

        other_only = _pending_registration(db)
        bad_other = client.post(
            f"/api/v1/admin/registrations/{other_only.id}/reject",
            json={"reasons": ["other"], "other_explanation": "   "},
            headers=headers,
        )
        assert bad_other.status_code == 400
        db.expire_all()
        assert (
            db.get(BusinessRegistration, other_only.id).application_status
            == ApplicationStatus.pending
        )
    finally:
        db.close()
