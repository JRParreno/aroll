"""Typed consent records, legal webpage, and biometric gates."""

from __future__ import annotations

import uuid

from fastapi.testclient import TestClient

from app.core.security import create_access_token, hash_password
from app.db.session import SessionLocal
from app.main import app
from app.models.business import Business
from app.models.consent_record import ConsentRecord
from app.models.employee import Employee
from app.models.enums import BusinessStatus, EmployeeStatus, EmploymentType, UserRole
from app.models.face_embedding import EmployeeFaceEmbedding
from app.models.user import User
from app.services.legal_consent import (
    DEFAULT_BIOMETRIC_VERSION,
    DEFAULT_PRIVACY_VERSION,
    DEFAULT_TERMS_VERSION,
    content_hash,
    default_legal_content,
    publish_default_legal,
)

JPEG_STUB = b"\xff\xd8\xff\xd9not-a-face"


def _auth(user: User) -> dict[str, str]:
    token = create_access_token(
        str(user.id),
        extra={
            "role": user.role.value,
            "business_id": str(user.business_id) if user.business_id else None,
        },
    )
    return {"Authorization": f"Bearer {token}"}


def _create_tenant(*, demo: bool = False):
    db = SessionLocal()
    business = Business(
        business_code=f"LC-{uuid.uuid4().hex[:6].upper()}",
        name="Consent Test Biz",
        status=BusinessStatus.active,
        is_demo=demo,
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
    employee_user = User(
        business_id=business.id,
        email=f"emp-{uuid.uuid4().hex[:8]}@example.com",
        password_hash=hash_password("EmpPass123!"),
        role=UserRole.employee,
        must_change_password=False,
        is_active=True,
    )
    db.add_all([owner, employee_user])
    db.flush()
    employee = Employee(
        business_id=business.id,
        user_id=employee_user.id,
        full_name="Casey Consent",
        position_title="Staff",
        employment_type=EmploymentType.full_time,
        status=EmployeeStatus.active,
        is_active=True,
        face_registration_status="not_registered",
    )
    db.add(employee)
    db.commit()
    db.refresh(business)
    db.refresh(owner)
    db.refresh(employee_user)
    db.refresh(employee)
    return db, business, owner, employee_user, employee


def _publish(db, business: Business) -> None:
    publish_default_legal(db, business, force=True)
    db.commit()
    db.refresh(business)


def _custom_payload(business: Business, **overrides):
    payload = {
        "use_custom_consents": True,
        "terms_content": default_legal_content(business.name, "terms"),
        "privacy_content": default_legal_content(business.name, "privacy"),
        "biometric_consent_content": default_legal_content(
            business.name, "biometric"
        ),
        "terms_version": DEFAULT_TERMS_VERSION,
        "privacy_version": DEFAULT_PRIVACY_VERSION,
        "biometric_consent_version": DEFAULT_BIOMETRIC_VERSION,
    }
    payload.update(overrides)
    return payload


def _enable_custom(client: TestClient, owner: User, business: Business, **overrides):
    return client.put(
        "/api/v1/businesses/me/legal",
        json=_custom_payload(business, **overrides),
        headers=_auth(owner),
    )


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


def _accept(client: TestClient, user: User, types: list[str], versions: dict[str, str]):
    return client.post(
        "/api/v1/employee/consent/accept",
        json={
            "accepted": True,
            "types": types,
            "versions": versions,
            "client": "mobile",
            "adult_acknowledged": True,
        },
        headers=_auth(user),
    )


def _face_files():
    return [
        ("files", ("a.jpg", JPEG_STUB, "image/jpeg")),
        ("files", ("b.jpg", JPEG_STUB, "image/jpeg")),
        ("files", ("c.jpg", JPEG_STUB, "image/jpeg")),
    ]


def _clock_face(client: TestClient, user: User, path: str):
    return client.post(
        path,
        headers=_auth(user),
        data={
            "latitude": "14.55",
            "longitude": "121.00",
            "liveness_gesture": "blink",
        },
        files={"file": ("probe.jpg", JPEG_STUB, "image/jpeg")},
    )


def _add_embedding(db, employee: Employee, owner: User, sample_index: int = 1) -> None:
    db.add(
        EmployeeFaceEmbedding(
            employee_id=employee.id,
            embedding=[0.01 * sample_index] * 512,
            model_version="test",
            sample_index=sample_index,
            enrolled_by=owner.id,
        )
    )
    employee.face_registration_status = "completed"
    db.commit()


def test_public_page_unpublished_custom_does_not_expose_admin_fallback():
    db, business, owner, _eu, _emp = _create_tenant()
    _publish(db, business)
    client = TestClient(app)
    try:
        saved = client.put(
            "/api/v1/businesses/me/legal",
            json={"use_custom_consents": True},
            headers=_auth(owner),
        )
        assert saved.status_code == 200, saved.text
        response = client.get(f"/api/v1/public/legal/{business.business_code}")
        assert response.status_code == 200
        payload = response.json()
        assert payload["use_custom_consents"] is True
        assert payload["terms"]["published"] is False
        assert payload["terms"]["content"] is None
        assert payload["terms"]["content_source"] == "business_custom"
        html = client.get(f"/api/v1/public/legal/{business.business_code}/page")
        assert html.status_code == 200
        assert "has not published" in html.text
    finally:
        db.close()


def test_owner_legal_settings_and_public_page():
    db, business, owner, _eu, _emp = _create_tenant()
    _publish(db, business)
    client = TestClient(app)
    try:
        headers = _auth(owner)
        listed = client.get("/api/v1/businesses/me/legal", headers=headers)
        assert listed.status_code == 200
        body = listed.json()
        assert body["legal_page_url"] == f"/legal/b/{business.business_code}"
        assert body["use_custom_consents"] is False
        assert body["effective"]["terms"]["published"] is True
        assert body["effective"]["terms"]["content_source"] == "admin_default"

        saved = _enable_custom(client, owner, business)
        assert saved.status_code == 200, saved.text
        saved_body = saved.json()
        assert saved_body["use_custom_consents"] is True
        assert saved_body["custom"]["terms_published"] is True
        assert saved_body["effective"]["terms"]["content_source"] == "business_custom"

        public = client.get(f"/api/v1/public/legal/{business.business_code}")
        assert public.status_code == 200
        assert public.json()["terms"]["published"] is True
        assert public.json()["terms"]["version"] == DEFAULT_TERMS_VERSION
        assert public.json()["terms"]["content_source"] == "business_custom"
    finally:
        db.close()


def test_typed_consent_records_persist_identity_version_timestamp():
    db, business, _owner, employee_user, employee = _create_tenant()
    _publish(db, business)
    client = TestClient(app)
    try:
        missing = client.get(
            "/api/v1/employee/consent/status", headers=_auth(employee_user)
        )
        assert missing.status_code == 200
        assert missing.json()["legal_satisfied"] is False

        first = _accept(
            client,
            employee_user,
            ["terms", "privacy"],
            {
                "terms": DEFAULT_TERMS_VERSION,
                "privacy": DEFAULT_PRIVACY_VERSION,
            },
        )
        assert first.status_code == 200, first.text
        body = first.json()
        assert body["legal_satisfied"] is True
        assert body["biometric_satisfied"] is False
        assert body["terms"]["accepted_at"]

        rows = (
            db.query(ConsentRecord)
            .filter(ConsentRecord.employee_id == employee.id)
            .all()
        )
        assert {row.consent_type for row in rows} == {"privacy", "terms"}
        expected_terms = default_legal_content("Aroll+", "terms")
        for row in rows:
            assert row.user_id == employee_user.id
            assert row.business_id == business.id
            assert row.action == "accepted"
            assert row.client == "mobile"
            assert row.created_at is not None
            assert row.content_source == "admin_default"
            assert row.content_snapshot
            assert row.accepted_content_hash == content_hash(row.content_snapshot)
            if row.consent_type == "terms":
                assert row.content_snapshot == expected_terms

        again = client.get(
            "/api/v1/employee/consent/status", headers=_auth(employee_user)
        )
        assert again.json()["legal_satisfied"] is True
    finally:
        db.close()


def test_unpublished_content_cannot_be_accepted():
    db, business, owner, employee_user, _emp = _create_tenant()
    _publish(db, business)
    client = TestClient(app)
    try:
        saved = client.put(
            "/api/v1/businesses/me/legal",
            json={"use_custom_consents": True},
            headers=_auth(owner),
        )
        assert saved.status_code == 200
        response = _accept(
            client,
            employee_user,
            ["terms"],
            {"terms": DEFAULT_TERMS_VERSION},
        )
        assert response.status_code == 400
        assert response.json()["detail"]["code"] == "legal_content_unpublished"
    finally:
        db.close()


def test_policy_version_bump_requires_reconsent():
    db, business, owner, employee_user, _emp = _create_tenant()
    _publish(db, business)
    client = TestClient(app)
    try:
        enabled = _enable_custom(client, owner, business)
        assert enabled.status_code == 200
        accepted = _accept(
            client,
            employee_user,
            ["terms", "privacy"],
            {
                "terms": DEFAULT_TERMS_VERSION,
                "privacy": DEFAULT_PRIVACY_VERSION,
            },
        )
        assert accepted.status_code == 200
        bumped = client.put(
            "/api/v1/businesses/me/legal",
            json={"terms_version": "terms-2026-10-01"},
            headers=_auth(owner),
        )
        assert bumped.status_code == 200
        status = client.get(
            "/api/v1/employee/consent/status", headers=_auth(employee_user)
        )
        assert status.json()["legal_satisfied"] is False
        stale = _accept(
            client,
            employee_user,
            ["terms"],
            {"terms": DEFAULT_TERMS_VERSION},
        )
        assert stale.status_code == 409
        assert stale.json()["detail"]["code"] == "consent_version_mismatch"
        fresh = _accept(
            client,
            employee_user,
            ["terms"],
            {"terms": "terms-2026-10-01"},
        )
        assert fresh.status_code == 200, fresh.text
        assert fresh.json()["legal_satisfied"] is True
    finally:
        db.close()


def test_biometric_gate_blocks_enrollment_and_attendance():
    db, business, owner, employee_user, employee = _create_tenant()
    _publish(db, business)
    client = TestClient(app)
    try:
        _accept(
            client,
            employee_user,
            ["terms", "privacy"],
            {
                "terms": DEFAULT_TERMS_VERSION,
                "privacy": DEFAULT_PRIVACY_VERSION,
            },
        )
        enroll = client.post(
            "/api/v1/employee/face-samples",
            headers=_auth(employee_user),
            files=_face_files(),
        )
        assert enroll.status_code == 403
        assert enroll.json()["detail"]["code"] == "biometric_consent_required"

        clock = _clock_face(
            client, employee_user, "/api/v1/employee/attendance/clock-in-face"
        )
        assert clock.status_code == 403
        assert clock.json()["detail"]["code"] == "biometric_consent_required"

        clock_out = _clock_face(
            client, employee_user, "/api/v1/employee/attendance/clock-out-face"
        )
        assert clock_out.status_code == 403
        assert clock_out.json()["detail"]["code"] == "biometric_consent_required"

        owner_enroll = client.post(
            f"/api/v1/employees/{employee.id}/face-samples",
            headers=_auth(owner),
            files=_face_files(),
        )
        assert owner_enroll.status_code == 403
        assert owner_enroll.json()["detail"]["code"] == "biometric_consent_required"
    finally:
        db.close()


def test_withdrawal_and_deactivation_clear_embeddings():
    db, business, owner, employee_user, employee = _create_tenant()
    _publish(db, business)
    client = TestClient(app)
    try:
        _accept(
            client,
            employee_user,
            ["terms", "privacy", "biometric"],
            {
                "terms": DEFAULT_TERMS_VERSION,
                "privacy": DEFAULT_PRIVACY_VERSION,
                "biometric": DEFAULT_BIOMETRIC_VERSION,
            },
        )
        db.add(
            EmployeeFaceEmbedding(
                employee_id=employee.id,
                embedding=[0.01] * 512,
                model_version="test",
                sample_index=1,
                enrolled_by=owner.id,
            )
        )
        employee.face_registration_status = "completed"
        db.commit()

        withdrawn = client.post(
            f"/api/v1/employees/{employee.id}/biometric-consent/withdraw",
            json={"client": "web"},
            headers=_auth(owner),
        )
        assert withdrawn.status_code == 200, withdrawn.text
        db.expire_all()
        employee = db.get(Employee, employee.id)
        remaining = (
            db.query(EmployeeFaceEmbedding)
            .filter(EmployeeFaceEmbedding.employee_id == employee.id)
            .count()
        )
        assert remaining == 0
        assert employee.face_registration_status == "not_registered"
        status = client.get(
            "/api/v1/employee/consent/status", headers=_auth(employee_user)
        )
        assert status.json()["biometric_satisfied"] is False

        db.add(
            EmployeeFaceEmbedding(
                employee_id=employee.id,
                embedding=[0.02] * 512,
                model_version="test",
                sample_index=1,
                enrolled_by=owner.id,
            )
        )
        employee.face_registration_status = "completed"
        db.commit()
        deactivated = client.post(
            f"/api/v1/employees/{employee.id}/deactivate",
            headers=_auth(owner),
        )
        assert deactivated.status_code == 200, deactivated.text
        remaining = (
            db.query(EmployeeFaceEmbedding)
            .filter(EmployeeFaceEmbedding.employee_id == employee.id)
            .count()
        )
        assert remaining == 0
    finally:
        db.close()


def test_cross_business_consent_isolation():
    db_a, _biz_a, _owner_a, emp_a, employee_a = _create_tenant()
    db_b, biz_b, owner_b, _emp_b, _employee_b = _create_tenant()
    _publish(db_a, db_a.get(Business, employee_a.business_id))
    _publish(db_b, biz_b)
    client = TestClient(app)
    try:
        _accept(
            client,
            emp_a,
            ["terms", "privacy"],
            {
                "terms": DEFAULT_TERMS_VERSION,
                "privacy": DEFAULT_PRIVACY_VERSION,
            },
        )
        listed = client.get("/api/v1/employees", headers=_auth(owner_b))
        assert listed.status_code == 200
        ids = {item["id"] for item in listed.json()}
        assert str(employee_a.id) not in ids
        public_b = client.get(f"/api/v1/public/legal/{biz_b.business_code}")
        assert public_b.status_code == 200
        assert public_b.json()["business_code"] == biz_b.business_code
    finally:
        db_a.close()
        db_b.close()


def test_demo_attendance_does_not_require_consent_records():
    db, _business, _owner, employee_user, _emp = _create_tenant(demo=True)
    client = TestClient(app)
    try:
        response = client.post(
            "/api/v1/employee/attendance/clock-in-face",
            headers=_auth(employee_user),
            data={
                "latitude": "1.0",
                "longitude": "1.0",
                "liveness_gesture": "blink",
            },
        )
        if response.status_code == 403:
            detail = response.json().get("detail")
            code = detail.get("code") if isinstance(detail, dict) else None
            assert code not in {
                "legal_consent_required",
                "biometric_consent_required",
            }
    finally:
        db.close()


def test_privacy_version_bump_requires_reconsent():
    db, business, owner, employee_user, _emp = _create_tenant()
    _publish(db, business)
    client = TestClient(app)
    try:
        enabled = _enable_custom(client, owner, business)
        assert enabled.status_code == 200
        accepted = _accept(
            client,
            employee_user,
            ["terms", "privacy"],
            {
                "terms": DEFAULT_TERMS_VERSION,
                "privacy": DEFAULT_PRIVACY_VERSION,
            },
        )
        assert accepted.status_code == 200
        bumped = client.put(
            "/api/v1/businesses/me/legal",
            json={"privacy_version": "privacy-2026-10-01"},
            headers=_auth(owner),
        )
        assert bumped.status_code == 200
        status = client.get(
            "/api/v1/employee/consent/status", headers=_auth(employee_user)
        )
        body = status.json()
        assert body["legal_satisfied"] is False
        assert body["privacy"]["satisfied"] is False
        assert body["terms"]["satisfied"] is True
        stale = _accept(
            client,
            employee_user,
            ["privacy"],
            {"privacy": DEFAULT_PRIVACY_VERSION},
        )
        assert stale.status_code == 409
        assert stale.json()["detail"]["code"] == "consent_version_mismatch"
        fresh = _accept(
            client,
            employee_user,
            ["privacy"],
            {"privacy": "privacy-2026-10-01"},
        )
        assert fresh.status_code == 200, fresh.text
        assert fresh.json()["legal_satisfied"] is True
    finally:
        db.close()


def test_biometric_version_bump_requires_reconsent():
    db, business, owner, employee_user, _emp = _create_tenant()
    _publish(db, business)
    client = TestClient(app)
    try:
        enabled = _enable_custom(client, owner, business)
        assert enabled.status_code == 200
        accepted = _accept(
            client,
            employee_user,
            ["terms", "privacy", "biometric"],
            {
                "terms": DEFAULT_TERMS_VERSION,
                "privacy": DEFAULT_PRIVACY_VERSION,
                "biometric": DEFAULT_BIOMETRIC_VERSION,
            },
        )
        assert accepted.status_code == 200
        assert accepted.json()["biometric_satisfied"] is True
        bumped = client.put(
            "/api/v1/businesses/me/legal",
            json={"biometric_consent_version": "biometric-consent-2026-10-01"},
            headers=_auth(owner),
        )
        assert bumped.status_code == 200
        status = client.get(
            "/api/v1/employee/consent/status", headers=_auth(employee_user)
        )
        body = status.json()
        assert body["legal_satisfied"] is True
        assert body["biometric_satisfied"] is False
        stale = _accept(
            client,
            employee_user,
            ["biometric"],
            {"biometric": DEFAULT_BIOMETRIC_VERSION},
        )
        assert stale.status_code == 409
        assert stale.json()["detail"]["code"] == "consent_version_mismatch"
        fresh = _accept(
            client,
            employee_user,
            ["biometric"],
            {"biometric": "biometric-consent-2026-10-01"},
        )
        assert fresh.status_code == 200, fresh.text
        assert fresh.json()["biometric_satisfied"] is True
    finally:
        db.close()


def test_terms_only_or_privacy_only_does_not_satisfy_legal_gate():
    db, business, _owner, employee_user, _emp = _create_tenant()
    _publish(db, business)
    client = TestClient(app)
    try:
        terms_only = _accept(
            client,
            employee_user,
            ["terms"],
            {"terms": DEFAULT_TERMS_VERSION},
        )
        assert terms_only.status_code == 200
        assert terms_only.json()["legal_satisfied"] is False
        clock = _clock_face(
            client, employee_user, "/api/v1/employee/attendance/clock-in-face"
        )
        assert clock.status_code == 403
        assert clock.json()["detail"]["code"] == "legal_consent_required"
        enroll = client.post(
            "/api/v1/employee/face-samples",
            headers=_auth(employee_user),
            files=_face_files(),
        )
        assert enroll.status_code == 403
        assert enroll.json()["detail"]["code"] == "legal_consent_required"
    finally:
        db.close()

    db, business, _owner, employee_user, _emp = _create_tenant()
    _publish(db, business)
    client = TestClient(app)
    try:
        privacy_only = _accept(
            client,
            employee_user,
            ["privacy"],
            {"privacy": DEFAULT_PRIVACY_VERSION},
        )
        assert privacy_only.status_code == 200
        assert privacy_only.json()["legal_satisfied"] is False
        clock = _clock_face(
            client, employee_user, "/api/v1/employee/attendance/clock-in-face"
        )
        assert clock.status_code == 403
        assert clock.json()["detail"]["code"] == "legal_consent_required"
    finally:
        db.close()


def test_withdrawal_blocks_enrollment_and_attendance():
    db, business, owner, employee_user, employee = _create_tenant()
    _publish(db, business)
    client = TestClient(app)
    try:
        accepted = _accept(
            client,
            employee_user,
            ["terms", "privacy", "biometric"],
            {
                "terms": DEFAULT_TERMS_VERSION,
                "privacy": DEFAULT_PRIVACY_VERSION,
                "biometric": DEFAULT_BIOMETRIC_VERSION,
            },
        )
        assert accepted.status_code == 200
        _add_embedding(db, employee, owner)
        withdrawn = client.post(
            f"/api/v1/employees/{employee.id}/biometric-consent/withdraw",
            json={"client": "web"},
            headers=_auth(owner),
        )
        assert withdrawn.status_code == 200, withdrawn.text
        db.expire_all()
        rows = (
            db.query(ConsentRecord)
            .filter(
                ConsentRecord.employee_id == employee.id,
                ConsentRecord.consent_type == "biometric",
                ConsentRecord.action == "withdrawn",
            )
            .all()
        )
        assert len(rows) == 1
        assert rows[0].policy_version == DEFAULT_BIOMETRIC_VERSION

        enroll = client.post(
            "/api/v1/employee/face-samples",
            headers=_auth(employee_user),
            files=_face_files(),
        )
        assert enroll.status_code == 403
        assert enroll.json()["detail"]["code"] == "biometric_consent_required"
        clock = _clock_face(
            client, employee_user, "/api/v1/employee/attendance/clock-in-face"
        )
        assert clock.status_code == 403
        assert clock.json()["detail"]["code"] == "biometric_consent_required"
    finally:
        db.close()


def test_employee_self_withdraw_biometric_consent():
    db, business, owner, employee_user, employee = _create_tenant()
    _publish(db, business)
    client = TestClient(app)
    try:
        accepted = _accept(
            client,
            employee_user,
            ["terms", "privacy", "biometric"],
            {
                "terms": DEFAULT_TERMS_VERSION,
                "privacy": DEFAULT_PRIVACY_VERSION,
                "biometric": DEFAULT_BIOMETRIC_VERSION,
            },
        )
        assert accepted.status_code == 200
        _add_embedding(db, employee, owner)
        withdrawn = client.post(
            "/api/v1/employee/consent/withdraw-biometric",
            json={"client": "mobile"},
            headers=_auth(employee_user),
        )
        assert withdrawn.status_code == 200, withdrawn.text
        assert withdrawn.json()["biometric_satisfied"] is False
        db.expire_all()
        employee = db.get(Employee, employee.id)
        remaining = (
            db.query(EmployeeFaceEmbedding)
            .filter(EmployeeFaceEmbedding.employee_id == employee.id)
            .count()
        )
        assert remaining == 0
        assert employee.face_registration_status == "not_registered"
        rows = (
            db.query(ConsentRecord)
            .filter(
                ConsentRecord.employee_id == employee.id,
                ConsentRecord.consent_type == "biometric",
                ConsentRecord.action == "withdrawn",
            )
            .all()
        )
        assert len(rows) == 1
        assert rows[0].user_id == employee_user.id
        assert rows[0].client == "mobile"
    finally:
        db.close()


def test_cross_business_owner_cannot_enroll_other_tenant_employee():
    db_a, _biz_a, _owner_a, emp_a, employee_a = _create_tenant()
    db_b, biz_b, owner_b, _emp_b, _employee_b = _create_tenant()
    _publish(db_a, db_a.get(Business, employee_a.business_id))
    _publish(db_b, biz_b)
    client = TestClient(app)
    try:
        _accept(
            client,
            emp_a,
            ["terms", "privacy", "biometric"],
            {
                "terms": DEFAULT_TERMS_VERSION,
                "privacy": DEFAULT_PRIVACY_VERSION,
                "biometric": DEFAULT_BIOMETRIC_VERSION,
            },
        )
        enroll = client.post(
            f"/api/v1/employees/{employee_a.id}/face-samples",
            headers=_auth(owner_b),
            files=_face_files(),
        )
        assert enroll.status_code == 404
    finally:
        db_a.close()
        db_b.close()


def test_hard_delete_employee_clears_embeddings():
    db, _business, owner, _employee_user, employee = _create_tenant()
    client = TestClient(app)
    employee_id = employee.id
    try:
        _add_embedding(db, employee, owner)
        remaining_before = (
            db.query(EmployeeFaceEmbedding)
            .filter(EmployeeFaceEmbedding.employee_id == employee_id)
            .count()
        )
        assert remaining_before == 1
        deleted = client.delete(
            f"/api/v1/employees/{employee_id}",
            headers=_auth(owner),
        )
        assert deleted.status_code == 200, deleted.text
        db.expire_all()
        remaining = (
            db.query(EmployeeFaceEmbedding)
            .filter(EmployeeFaceEmbedding.employee_id == employee_id)
            .count()
        )
        assert remaining == 0
        assert db.get(Employee, employee_id) is None
    finally:
        db.close()


def test_new_business_inherits_admin_defaults_without_owner_publish():
    db, business, owner, _eu, _emp = _create_tenant()
    _publish(db, business)
    client = TestClient(app)
    try:
        listed = client.get("/api/v1/businesses/me/legal", headers=_auth(owner))
        assert listed.status_code == 200
        body = listed.json()
        assert body["use_custom_consents"] is False
        assert body["effective"]["terms"]["published"] is True
        assert body["effective"]["terms"]["content_source"] == "admin_default"
        assert body["effective"]["privacy"]["published"] is True
        assert body["effective"]["biometric"]["published"] is True
        public = client.get(f"/api/v1/public/legal/{business.business_code}")
        assert public.status_code == 200
        payload = public.json()
        assert payload["use_custom_consents"] is False
        assert payload["terms"]["content_source"] == "admin_default"
        assert payload["terms"]["version"] == DEFAULT_TERMS_VERSION
        assert payload["terms"]["content"]
        assert "Aroll+" in payload["terms"]["content"]
    finally:
        db.close()


def test_admin_can_update_platform_defaults():
    db, business, _owner, _eu, _emp = _create_tenant()
    _publish(db, business)
    admin = _platform_admin(db)
    client = TestClient(app)
    try:
        headers = _auth(admin)
        listed = client.get("/api/v1/admin/legal", headers=headers)
        assert listed.status_code == 200
        assert listed.json()["terms"]["published"] is True
        saved = client.put(
            "/api/v1/admin/legal",
            json={
                "terms_content": "Updated Aroll+ Terms for tests.",
                "terms_version": "terms-admin-2026-11-01",
                "terms_published": True,
            },
            headers=headers,
        )
        assert saved.status_code == 200, saved.text
        assert saved.json()["terms"]["version"] == "terms-admin-2026-11-01"
        assert saved.json()["terms"]["updated_by"] == str(admin.id)
        public = client.get(f"/api/v1/public/legal/{business.business_code}")
        assert public.json()["terms"]["version"] == "terms-admin-2026-11-01"
        assert public.json()["terms"]["content"] == "Updated Aroll+ Terms for tests."
    finally:
        _publish(db, business)
        db.close()


def test_owner_and_employee_cannot_modify_platform_defaults():
    db, _business, owner, employee_user, _emp = _create_tenant()
    admin_payload = {
        "terms_content": "Should not save",
        "terms_version": "terms-forbidden",
    }
    client = TestClient(app)
    try:
        owner_get = client.get("/api/v1/admin/legal", headers=_auth(owner))
        assert owner_get.status_code == 403
        owner_put = client.put(
            "/api/v1/admin/legal",
            json=admin_payload,
            headers=_auth(owner),
        )
        assert owner_put.status_code == 403
        emp_put = client.put(
            "/api/v1/admin/legal",
            json=admin_payload,
            headers=_auth(employee_user),
        )
        assert emp_put.status_code == 403
    finally:
        db.close()


def test_admin_default_version_bump_requires_reconsent_for_default_mode():
    db, business, _owner, employee_user, employee = _create_tenant()
    _publish(db, business)
    admin = _platform_admin(db)
    client = TestClient(app)
    try:
        accepted = _accept(
            client,
            employee_user,
            ["terms", "privacy"],
            {
                "terms": DEFAULT_TERMS_VERSION,
                "privacy": DEFAULT_PRIVACY_VERSION,
            },
        )
        assert accepted.status_code == 200
        bumped = client.put(
            "/api/v1/admin/legal",
            json={"terms_version": "terms-admin-2026-12-01"},
            headers=_auth(admin),
        )
        assert bumped.status_code == 200
        status = client.get(
            "/api/v1/employee/consent/status", headers=_auth(employee_user)
        )
        assert status.json()["legal_satisfied"] is False
        stale = _accept(
            client,
            employee_user,
            ["terms"],
            {"terms": DEFAULT_TERMS_VERSION},
        )
        assert stale.status_code == 409
        fresh = _accept(
            client,
            employee_user,
            ["terms"],
            {"terms": "terms-admin-2026-12-01"},
        )
        assert fresh.status_code == 200, fresh.text
        assert fresh.json()["legal_satisfied"] is True
        db.expire_all()
        row = (
            db.query(ConsentRecord)
            .filter(
                ConsentRecord.employee_id == employee.id,
                ConsentRecord.consent_type == "terms",
                ConsentRecord.policy_version == "terms-admin-2026-12-01",
            )
            .one()
        )
        assert row.content_source == "admin_default"
        assert row.accepted_content_hash
        assert row.content_snapshot
    finally:
        _publish(db, business)
        db.close()


def test_custom_mode_not_affected_by_admin_default_version_bump():
    db, business, owner, employee_user, _emp = _create_tenant()
    _publish(db, business)
    admin = _platform_admin(db)
    client = TestClient(app)
    try:
        enabled = _enable_custom(client, owner, business)
        assert enabled.status_code == 200
        accepted = _accept(
            client,
            employee_user,
            ["terms", "privacy"],
            {
                "terms": DEFAULT_TERMS_VERSION,
                "privacy": DEFAULT_PRIVACY_VERSION,
            },
        )
        assert accepted.status_code == 200
        bumped = client.put(
            "/api/v1/admin/legal",
            json={
                "terms_content": "Admin-only new terms",
                "terms_version": "terms-admin-ignored",
            },
            headers=_auth(admin),
        )
        assert bumped.status_code == 200
        status = client.get(
            "/api/v1/employee/consent/status", headers=_auth(employee_user)
        )
        body = status.json()
        assert body["legal_satisfied"] is True
        assert body["terms"]["current_version"] == DEFAULT_TERMS_VERSION
        assert body["terms"]["content_source"] == "business_custom"
        public = client.get(f"/api/v1/public/legal/{business.business_code}")
        assert public.json()["terms"]["version"] == DEFAULT_TERMS_VERSION
        assert "Admin-only new terms" not in (public.json()["terms"]["content"] or "")
    finally:
        _publish(db, business)
        db.close()


def test_disable_custom_returns_to_admin_defaults():
    db, business, owner, employee_user, _emp = _create_tenant()
    _publish(db, business)
    client = TestClient(app)
    try:
        enabled = _enable_custom(
            client,
            owner,
            business,
            terms_version="terms-custom-1",
            privacy_version="privacy-custom-1",
            biometric_consent_version="biometric-custom-1",
        )
        assert enabled.status_code == 200
        accepted = _accept(
            client,
            employee_user,
            ["terms", "privacy"],
            {
                "terms": "terms-custom-1",
                "privacy": "privacy-custom-1",
            },
        )
        assert accepted.status_code == 200
        disabled = client.put(
            "/api/v1/businesses/me/legal",
            json={"use_custom_consents": False},
            headers=_auth(owner),
        )
        assert disabled.status_code == 200
        assert disabled.json()["use_custom_consents"] is False
        assert (
            disabled.json()["effective"]["terms"]["content_source"]
            == "admin_default"
        )
        status = client.get(
            "/api/v1/employee/consent/status", headers=_auth(employee_user)
        )
        assert status.json()["legal_satisfied"] is False
        public = client.get(f"/api/v1/public/legal/{business.business_code}")
        assert public.json()["terms"]["version"] == DEFAULT_TERMS_VERSION
        assert public.json()["terms"]["content_source"] == "admin_default"
    finally:
        db.close()


def test_cross_business_custom_content_isolation():
    db_a, biz_a, owner_a, _emp_a, _employee_a = _create_tenant()
    db_b, biz_b, _owner_b, _emp_b, _employee_b = _create_tenant()
    _publish(db_a, biz_a)
    _publish(db_b, biz_b)
    client = TestClient(app)
    try:
        custom_text = f"TENANT-A-ONLY {biz_a.business_code}"
        saved = _enable_custom(
            client,
            owner_a,
            biz_a,
            terms_content=custom_text,
        )
        assert saved.status_code == 200
        page_a = client.get(f"/api/v1/public/legal/{biz_a.business_code}")
        page_b = client.get(f"/api/v1/public/legal/{biz_b.business_code}")
        assert page_a.json()["terms"]["content_source"] == "business_custom"
        assert page_a.json()["terms"]["content"] == custom_text
        assert page_b.json()["terms"]["content_source"] == "admin_default"
        assert custom_text not in (page_b.json()["terms"]["content"] or "")
        settings_b = client.get(
            "/api/v1/businesses/me/legal", headers=_auth(_owner_b)
        )
        assert settings_b.status_code == 200
        assert custom_text not in (
            settings_b.json()["effective"]["terms"]["content"] or ""
        )
    finally:
        db_a.close()
        db_b.close()
