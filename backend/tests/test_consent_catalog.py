"""Consent document catalog APIs, public pages, and per-document accept."""

from __future__ import annotations

from fastapi.testclient import TestClient

from app.main import app
from app.models.consent_record import ConsentRecord
from tests.test_legal_consent import (
    JPEG_STUB,
    _auth,
    _clock_face,
    _create_tenant,
    _enable_custom,
    _platform_admin,
    _publish,
)


def _accept_all(client: TestClient, user, items: list[dict]):
    last = None
    for item in items:
        last = client.post(
            f"/api/v1/consents/{item['id']}/accept",
            json={"client": "mobile"},
            headers=_auth(user),
        )
        assert last.status_code == 200, last.text
    return last


def test_admin_text_and_file_generate_public_urls():
    db, _business, _owner, _eu, _emp = _create_tenant()
    admin = _platform_admin(db)
    client = TestClient(app)
    try:
        created = client.post(
            "/api/v1/admin/consents",
            json={
                "title": "Handbook",
                "body_text": "Workplace handbook body.",
                "consent_type": "custom",
                "is_active": True,
                "is_required": False,
            },
            headers=_auth(admin),
        )
        assert created.status_code == 200, created.text
        doc = created.json()
        page = client.get(f"/api/v1/public/consents/{doc['id']}/page")
        assert page.status_code == 200
        assert "Workplace handbook body." in page.text

        uploaded = client.post(
            f"/api/v1/admin/consents/{doc['id']}/file",
            headers=_auth(admin),
            files={"file": ("policy.png", JPEG_STUB, "image/png")},
        )
        assert uploaded.status_code == 200, uploaded.text
        page_after = client.get(f"/api/v1/public/consents/{doc['id']}/page")
        assert page_after.status_code == 200
        file_res = client.get(f"/api/v1/public/consents/{doc['id']}/file")
        assert file_res.status_code == 200
        assert file_res.content == JPEG_STUB
    finally:
        db.close()


def test_toggle_off_uses_platform_docs_toggle_on_uses_business_docs():
    db, business, owner, employee_user, _emp = _create_tenant()
    _publish(db, business)
    admin = _platform_admin(db)
    client = TestClient(app)
    try:
        listed = client.get("/api/v1/consents", headers=_auth(employee_user))
        assert listed.status_code == 200, listed.text
        platform_ids = {item["id"] for item in listed.json()["items"]}
        assert len(platform_ids) >= 3

        enabled = _enable_custom(client, owner, business)
        assert enabled.status_code == 200, enabled.text
        custom_list = client.get("/api/v1/consents", headers=_auth(employee_user))
        assert custom_list.status_code == 200
        custom_ids = {item["id"] for item in custom_list.json()["items"]}
        assert custom_ids
        assert custom_ids.isdisjoint(platform_ids)

        client.put(
            "/api/v1/businesses/me/legal",
            json={"use_custom_consents": False},
            headers=_auth(owner),
        )
        restored = client.get("/api/v1/consents", headers=_auth(employee_user))
        restored_ids = {item["id"] for item in restored.json()["items"]}
        assert restored_ids == platform_ids
        assert admin.email
    finally:
        db.close()


def test_per_document_accept_gates_face_clock_in():
    db, business, _owner, employee_user, _emp = _create_tenant()
    _publish(db, business)
    client = TestClient(app)
    try:
        listed = client.get("/api/v1/consents", headers=_auth(employee_user))
        items = listed.json()["items"]
        required = [item for item in items if item["required"]]
        assert required
        first = required[0]
        accepted = client.post(
            f"/api/v1/consents/{first['id']}/accept",
            json={"client": "mobile"},
            headers=_auth(employee_user),
        )
        assert accepted.status_code == 200, accepted.text
        assert accepted.json()["consents_completed"] is False

        clock = _clock_face(
            client, employee_user, "/api/v1/employee/attendance/clock-in-face"
        )
        assert clock.status_code == 403
        assert clock.json()["detail"]["code"] in {
            "legal_consent_required",
            "biometric_consent_required",
        }

        done = _accept_all(client, employee_user, required)
        assert done.json()["consents_completed"] is True
        me = client.get("/api/v1/auth/me", headers=_auth(employee_user))
        assert me.status_code == 200
        assert me.json()["consents_completed"] is True

        clock_after = _clock_face(
            client, employee_user, "/api/v1/employee/attendance/clock-in-face"
        )
        detail = clock_after.json().get("detail")
        code = detail.get("code") if isinstance(detail, dict) else None
        assert code not in {
            "legal_consent_required",
            "biometric_consent_required",
        }
    finally:
        db.close()


def test_content_update_requires_reaccept():
    db, business, _owner, employee_user, _emp = _create_tenant()
    _publish(db, business)
    admin = _platform_admin(db)
    client = TestClient(app)
    try:
        listed = client.get("/api/v1/consents", headers=_auth(employee_user))
        items = listed.json()["items"]
        _accept_all(client, employee_user, [item for item in items if item["required"]])
        target = items[0]
        updated = client.patch(
            f"/api/v1/admin/consents/{target['id']}",
            json={"body_text": "Updated consent body for re-accept."},
            headers=_auth(admin),
        )
        assert updated.status_code == 200, updated.text
        relisted = client.get("/api/v1/consents", headers=_auth(employee_user))
        payload = relisted.json()
        assert payload["consents_completed"] is False
        changed = next(item for item in payload["items"] if item["id"] == target["id"])
        assert changed["accepted"] is False

        records = (
            db.query(ConsentRecord)
            .filter(ConsentRecord.document_id == target["id"])
            .all()
        )
        assert records
    finally:
        db.close()
