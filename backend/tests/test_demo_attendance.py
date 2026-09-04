"""Phase 2: DEMO01 vs DEVTEST face identity and GPS behavior."""

from __future__ import annotations

from pathlib import Path
from types import SimpleNamespace
from unittest.mock import patch
from uuid import UUID

import pytest
from fastapi import HTTPException
from fastapi.testclient import TestClient

from app.core.timezone import business_now
from app.db.session import SessionLocal
from app.main import app
from app.models.attendance import AttendanceRecord
from app.models.business import Business
from app.models.employee import Employee
from app.models.face_embedding import EmployeeFaceEmbedding
from app.models.user import User
from app.seed_demo import (
    DEMO_BUSINESS_CODE,
    DEMO_EMPLOYEE_01_EMAIL,
    DEMO_LATITUDE,
    DEMO_LONGITUDE,
    DEMO_OWNER_EMAIL,
    DEMO_SEED_PASSWORD,
    seed_demo,
)
from app.seed_internal_test import (
    DEV_BUSINESS_CODE,
    DEV_EMPLOYEE_EMAIL,
    DEV_LATITUDE,
    DEV_LONGITUDE,
    DEV_SEED_PASSWORD,
    seed_internal_test,
)
from app.services.attendance_clock import GeofenceValidationError, clock_in_employee
from app.services.demo_tenant import (
    DEMO_ENROLLMENT_LOCKED,
    business_is_demo,
    raise_if_demo_enrollment_locked,
    substitute_demo_worksite_coordinates,
    verify_demo_seeded_identity,
)
from app.services.face_enrollment import enroll_face_sample_bytes

_PHASE1_JPEG = (
    Path(__file__).resolve().parents[1]
    / "app"
    / "seed_assets"
    / "demo_faces"
    / "hannah_1.jpg"
)
_GARBAGE_JPEG = b"\xff\xd8\xff\xd9not-a-detectable-face"
_FAR_LAT = 1.0000000
_FAR_LNG = 1.0000000


def _auth_header(token: str) -> dict[str, str]:
    return {"Authorization": f"Bearer {token}"}


def _login_employee(client: TestClient, email: str, password: str) -> str:
    response = client.post(
        "/api/v1/auth/login",
        json={"email": email, "password": password},
    )
    assert response.status_code == 200, response.text
    return response.json()["access_token"]


def _login_owner(client: TestClient, *, code: str, email: str, password: str) -> str:
    response = client.post(
        "/api/v1/auth/business-owner-login",
        json={"business_code": code, "email": email, "password": password},
    )
    assert response.status_code == 200, response.text
    return response.json()["access_token"]


def _hannah(db) -> Employee:
    return (
        db.query(Employee)
        .join(User, Employee.user_id == User.id)
        .filter(User.email == DEMO_EMPLOYEE_01_EMAIL)
        .one()
    )


def _dev_employee(db) -> Employee:
    return (
        db.query(Employee)
        .join(User, Employee.user_id == User.id)
        .filter(User.email == DEV_EMPLOYEE_EMAIL)
        .one()
    )


def _clear_open_punches(employee_id) -> None:
    db = SessionLocal()
    try:
        db.query(AttendanceRecord).filter(
            AttendanceRecord.employee_id == employee_id,
            AttendanceRecord.time_out.is_(None),
        ).delete(synchronize_session=False)
        db.commit()
    finally:
        db.close()


def _morning_now():
    now = business_now("Asia/Manila")
    return now.replace(hour=8, minute=15, second=0, microsecond=0)


def _patch_demo_morning():
    frozen = _morning_now()
    return (
        patch(
            "app.services.attendance_clock.business_now",
            return_value=frozen,
        ),
        patch(
            "app.services.attendance_clock.business_today",
            return_value=frozen.date(),
        ),
    )


def test_business_is_demo_requires_real_true_flag():
    assert business_is_demo(None) is False
    assert business_is_demo(SimpleNamespace(is_demo=False)) is False
    assert business_is_demo(SimpleNamespace(is_demo=True)) is True
    assert business_is_demo(SimpleNamespace(is_internal_test=True, is_demo=False)) is False


def test_gps_substitution_only_for_demo_business_record():
    location = SimpleNamespace(latitude=DEMO_LATITUDE, longitude=DEMO_LONGITUDE)
    demo = SimpleNamespace(is_demo=True, business_code=DEMO_BUSINESS_CODE)
    lat, lng = substitute_demo_worksite_coordinates(
        business=demo,
        location=location,
        latitude=_FAR_LAT,
        longitude=_FAR_LNG,
    )
    assert lat == pytest.approx(DEMO_LATITUDE)
    assert lng == pytest.approx(DEMO_LONGITUDE)

    ordinary = SimpleNamespace(is_demo=False, business_code="ACME01")
    lat, lng = substitute_demo_worksite_coordinates(
        business=ordinary,
        location=location,
        latitude=_FAR_LAT,
        longitude=_FAR_LNG,
    )
    assert lat == _FAR_LAT
    assert lng == _FAR_LNG

    lab = SimpleNamespace(is_demo=False, is_internal_test=True, business_code=DEV_BUSINESS_CODE)
    lat, lng = substitute_demo_worksite_coordinates(
        business=lab,
        location=location,
        latitude=_FAR_LAT,
        longitude=_FAR_LNG,
    )
    assert lat == _FAR_LAT
    assert lng == _FAR_LNG


def test_demo_enrollment_lock_helper():
    with pytest.raises(Exception) as exc:
        raise_if_demo_enrollment_locked(SimpleNamespace(is_demo=True, business_code="DEMO01"))
    assert exc.value.status_code == 403
    assert exc.value.detail["code"] == DEMO_ENROLLMENT_LOCKED["code"]
    raise_if_demo_enrollment_locked(SimpleNamespace(is_demo=False))
    raise_if_demo_enrollment_locked(None)


def test_demo_face_enrollment_is_blocked_and_does_not_overwrite():
    seed_demo()
    db = SessionLocal()
    try:
        employee = _hannah(db)
        before = (
            db.query(EmployeeFaceEmbedding)
            .filter(EmployeeFaceEmbedding.employee_id == employee.id)
            .count()
        )
        assert before >= 3
        employee_id = employee.id
        status_before = employee.face_registration_status
    finally:
        db.close()

    client = TestClient(app)
    token = _login_employee(client, DEMO_EMPLOYEE_01_EMAIL, DEMO_SEED_PASSWORD)
    files = [
        ("files", ("a.jpg", _GARBAGE_JPEG, "image/jpeg")),
        ("files", ("b.jpg", _GARBAGE_JPEG, "image/jpeg")),
        ("files", ("c.jpg", _GARBAGE_JPEG, "image/jpeg")),
    ]
    response = client.post(
        "/api/v1/employee/face-samples",
        files=files,
        headers=_auth_header(token),
    )
    assert response.status_code == 403
    assert response.json()["detail"]["code"] == "demo_enrollment_locked"

    owner_token = _login_owner(
        client,
        code=DEMO_BUSINESS_CODE,
        email=DEMO_OWNER_EMAIL,
        password=DEMO_SEED_PASSWORD,
    )
    owner_enroll = client.post(
        f"/api/v1/employees/{employee_id}/face-samples",
        files=files,
        headers=_auth_header(owner_token),
    )
    assert owner_enroll.status_code == 403
    assert owner_enroll.json()["detail"]["code"] == "demo_enrollment_locked"

    owner_delete = client.delete(
        f"/api/v1/employees/{employee_id}/face-samples",
        headers=_auth_header(owner_token),
    )
    assert owner_delete.status_code == 403
    assert owner_delete.json()["detail"]["code"] == "demo_enrollment_locked"

    db = SessionLocal()
    try:
        after = (
            db.query(EmployeeFaceEmbedding)
            .filter(EmployeeFaceEmbedding.employee_id == employee_id)
            .count()
        )
        employee = db.get(Employee, employee_id)
        assert after == before
        assert employee.face_registration_status == status_before
    finally:
        db.close()


def test_demo_seeded_identity_resolves_without_live_probe():
    seed_demo()
    db = SessionLocal()
    try:
        business = db.query(Business).filter(Business.business_code == DEMO_BUSINESS_CODE).one()
        employee = _hannah(db)
        score = verify_demo_seeded_identity(db, employee, business)
        assert score == 1.0
    finally:
        db.close()


def test_demo_clock_in_uses_worksite_coords_and_stays_on_demo01():
    seed_demo()
    seed_internal_test()
    db = SessionLocal()
    try:
        employee = _hannah(db)
        demo = db.query(Business).filter(Business.business_code == DEMO_BUSINESS_CODE).one()
        lab = db.query(Business).filter(Business.business_code == DEV_BUSINESS_CODE).one()
        employee_id = employee.id
        demo_id = demo.id
        lab_id = lab.id
        lab_attendance_before = (
            db.query(AttendanceRecord)
            .filter(AttendanceRecord.business_id == lab_id)
            .count()
        )
        lab_faces_before = (
            db.query(EmployeeFaceEmbedding)
            .join(Employee, EmployeeFaceEmbedding.employee_id == Employee.id)
            .filter(Employee.business_id == lab_id)
            .count()
        )
    finally:
        db.close()

    _clear_open_punches(employee_id)
    client = TestClient(app)
    token = _login_employee(client, DEMO_EMPLOYEE_01_EMAIL, DEMO_SEED_PASSWORD)
    now_patch, today_patch = _patch_demo_morning()
    created_id = None
    try:
        with now_patch, today_patch, patch(
            "app.api.employee_mobile.verify_employee_face_match"
        ) as live_match:
            response = client.post(
                "/api/v1/employee/attendance/clock-in-face",
                data={
                    "latitude": str(_FAR_LAT),
                    "longitude": str(_FAR_LNG),
                    "is_demo": "false",
                    "mode": "live",
                },
                files={"file": ("junk.jpg", _GARBAGE_JPEG, "image/jpeg")},
                headers=_auth_header(token),
            )
            assert response.status_code == 200, response.text
            live_match.assert_not_called()
        body = response.json()
        created_id = body["id"]
        assert body["geofence"]["inside_geofence"] is True
        assert body["geofence"]["distance_m"] < 1
        assert body["face_match_score"] == pytest.approx(1.0)
    finally:
        db = SessionLocal()
        try:
            if created_id:
                row = db.get(AttendanceRecord, UUID(str(created_id)))
                assert row is not None
                assert row.business_id == demo_id
                assert row.employee_id == employee_id
                assert float(row.latitude_in) == pytest.approx(DEMO_LATITUDE)
                assert float(row.longitude_in) == pytest.approx(DEMO_LONGITUDE)
                db.delete(row)
                db.commit()
            assert (
                db.query(AttendanceRecord)
                .filter(AttendanceRecord.business_id == lab_id)
                .count()
                == lab_attendance_before
            )
            assert (
                db.query(EmployeeFaceEmbedding)
                .join(Employee, EmployeeFaceEmbedding.employee_id == Employee.id)
                .filter(Employee.business_id == lab_id)
                .count()
                == lab_faces_before
            )
        finally:
            db.close()


def test_demo_attendance_independent_of_phase1_yunet_jpeg():
    """DEMO01 Time In must work even if the generated JPEG is not YuNet-detectable."""
    seed_demo()
    db = SessionLocal()
    try:
        employee_id = _hannah(db).id
    finally:
        db.close()
    _clear_open_punches(employee_id)

    jpeg = _GARBAGE_JPEG
    if _PHASE1_JPEG.exists():
        jpeg = _PHASE1_JPEG.read_bytes()

    client = TestClient(app)
    token = _login_employee(client, DEMO_EMPLOYEE_01_EMAIL, DEMO_SEED_PASSWORD)
    now_patch, today_patch = _patch_demo_morning()
    created_ids: list[str] = []
    try:
        with now_patch, today_patch, patch(
            "app.services.face_embedding.detect_and_embed",
            side_effect=AssertionError("YuNet must not run for DEMO01 attendance"),
        ):
            with_file = client.post(
                "/api/v1/employee/attendance/clock-in-face",
                data={"latitude": str(_FAR_LAT), "longitude": str(_FAR_LNG)},
                files={"file": ("hannah_1.jpg", jpeg, "image/jpeg")},
                headers=_auth_header(token),
            )
            assert with_file.status_code == 200, with_file.text
            created_ids.append(with_file.json()["id"])

            db = SessionLocal()
            try:
                db.query(AttendanceRecord).filter(
                    AttendanceRecord.id == UUID(str(created_ids[0]))
                ).delete(synchronize_session=False)
                db.commit()
            finally:
                db.close()

            without_file = client.post(
                "/api/v1/employee/attendance/clock-in-face",
                data={"latitude": str(_FAR_LAT), "longitude": str(_FAR_LNG)},
                headers=_auth_header(token),
            )
            assert without_file.status_code == 200, without_file.text
            created_ids.append(without_file.json()["id"])
    finally:
        db = SessionLocal()
        try:
            if created_ids:
                db.query(AttendanceRecord).filter(
                    AttendanceRecord.id.in_([UUID(str(value)) for value in created_ids])
                ).delete(synchronize_session=False)
                db.commit()
        finally:
            db.close()


def test_demo_clock_out_also_substitutes_worksite_coords():
    seed_demo()
    db = SessionLocal()
    try:
        employee_id = _hannah(db).id
        demo_id = (
            db.query(Business)
            .filter(Business.business_code == DEMO_BUSINESS_CODE)
            .one()
            .id
        )
    finally:
        db.close()
    _clear_open_punches(employee_id)

    client = TestClient(app)
    token = _login_employee(client, DEMO_EMPLOYEE_01_EMAIL, DEMO_SEED_PASSWORD)
    now_patch, today_patch = _patch_demo_morning()
    record_id = None
    try:
        with now_patch, today_patch:
            clock_in = client.post(
                "/api/v1/employee/attendance/clock-in-face",
                data={"latitude": str(_FAR_LAT), "longitude": str(_FAR_LNG)},
                headers=_auth_header(token),
            )
            assert clock_in.status_code == 200, clock_in.text
            record_id = clock_in.json()["id"]
            clock_out = client.post(
                "/api/v1/employee/attendance/clock-out-face",
                data={"latitude": str(_FAR_LAT), "longitude": str(_FAR_LNG)},
                headers=_auth_header(token),
            )
            assert clock_out.status_code == 200, clock_out.text
            assert clock_out.json()["geofence"]["inside_geofence"] is True
    finally:
        db = SessionLocal()
        try:
            if record_id:
                row = db.get(AttendanceRecord, UUID(str(record_id)))
                assert row is not None
                assert row.business_id == demo_id
                assert float(row.latitude_in) == pytest.approx(DEMO_LATITUDE)
                assert float(row.longitude_in) == pytest.approx(DEMO_LONGITUDE)
                assert float(row.latitude_out) == pytest.approx(DEMO_LATITUDE)
                assert float(row.longitude_out) == pytest.approx(DEMO_LONGITUDE)
                db.delete(row)
                db.commit()
        finally:
            db.close()


def test_devtest_enrollment_is_not_demo_locked():
    seed_internal_test()
    client = TestClient(app)
    token = _login_employee(client, DEV_EMPLOYEE_EMAIL, DEV_SEED_PASSWORD)
    response = client.post(
        "/api/v1/employee/face-samples",
        files=[
            ("files", ("a.jpg", _GARBAGE_JPEG, "image/jpeg")),
            ("files", ("b.jpg", _GARBAGE_JPEG, "image/jpeg")),
            ("files", ("c.jpg", _GARBAGE_JPEG, "image/jpeg")),
        ],
        headers=_auth_header(token),
    )
    assert response.status_code != 403
    detail = response.json().get("detail")
    if isinstance(detail, dict):
        assert detail.get("code") != "demo_enrollment_locked"
    else:
        assert "demo_enrollment_locked" not in str(detail)


def test_devtest_clock_in_requires_live_face_and_does_not_use_demo_path():
    seed_internal_test()
    client = TestClient(app)
    token = _login_employee(client, DEV_EMPLOYEE_EMAIL, DEV_SEED_PASSWORD)
    missing = client.post(
        "/api/v1/employee/attendance/clock-in-face",
        data={
            "latitude": str(DEV_LATITUDE),
            "longitude": str(DEV_LONGITUDE),
            "is_demo": "true",
            "mode": "demo",
        },
        headers=_auth_header(token),
    )
    assert missing.status_code == 400
    assert missing.json()["detail"]["code"] == "liveness_required"

    no_file = client.post(
        "/api/v1/employee/attendance/clock-in-face",
        data={
            "latitude": str(DEV_LATITUDE),
            "longitude": str(DEV_LONGITUDE),
            "liveness_gesture": "blink",
        },
        headers=_auth_header(token),
    )
    assert no_file.status_code == 400
    assert no_file.json()["detail"]["code"] == "face_required"


def test_devtest_far_gps_still_fails_geofence():
    seed_internal_test()
    db = SessionLocal()
    try:
        employee = _dev_employee(db)
        with pytest.raises(GeofenceValidationError) as exc:
            clock_in_employee(
                db,
                employee,
                latitude=_FAR_LAT,
                longitude=_FAR_LNG,
                business_timezone="Asia/Manila",
            )
        assert exc.value.status_code == 403
        assert exc.value.detail["code"] == "outside_geofence"
        db.rollback()
    finally:
        db.close()


def test_ordinary_business_enrollment_lock_does_not_apply():
    raise_if_demo_enrollment_locked(
        SimpleNamespace(is_demo=False, is_internal_test=False)
    )
    db = SessionLocal()
    try:
        with pytest.raises(HTTPException) as exc:
            enroll_face_sample_bytes(
                db,
                SimpleNamespace(id=None, business_id=None),
                [],
                enrolled_by=None,
            )
        assert exc.value.status_code == 400
        assert exc.value.detail != DEMO_ENROLLMENT_LOCKED
        assert "Upload between" in str(exc.value.detail)
    finally:
        db.close()
