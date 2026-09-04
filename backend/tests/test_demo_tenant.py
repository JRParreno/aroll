"""Tests for AROLL+ Demo Café (DEMO01) tenant isolation and session flags."""

from fastapi.testclient import TestClient

from app.core.security import hash_password
from app.db.session import SessionLocal
from app.main import app
from app.models.attendance import AttendanceRecord
from app.models.business import Business
from app.models.employee import Employee
from app.models.enums import UserRole
from app.models.face_embedding import EmployeeFaceEmbedding
from app.models.payroll_adjustment import PayrollAdjustment
from app.models.user import User
from app.seed_demo import (
    DEMO_BUSINESS_CODE,
    DEMO_BUSINESS_NAME,
    DEMO_EMPLOYEE_01_EMAIL,
    DEMO_EMPLOYEE_02_EMAIL,
    DEMO_MANAGER_EMAIL,
    DEMO_OWNER_EMAIL,
    DEMO_SEED_PASSWORD,
    seed_demo,
)
from app.seed_internal_test import (
    DEV_BUSINESS_CODE,
    DEV_EMPLOYEE_EMAIL,
    seed_internal_test,
)


def _business(db, code: str) -> Business:
    row = db.query(Business).filter(Business.business_code == code).one()
    return row


def test_new_business_defaults_is_demo_false():
    db = SessionLocal()
    try:
        business = Business(
            business_code="T-DEFAULT1",
            name="Default Flag Biz",
        )
        db.add(business)
        db.flush()
        assert business.is_demo is False
        assert business.is_internal_test is False
    finally:
        db.rollback()
        db.close()


def test_demo_tenant_flags_and_membership():
    seed_demo()
    db = SessionLocal()
    try:
        business = _business(db, DEMO_BUSINESS_CODE)
        assert business.name == DEMO_BUSINESS_NAME
        assert business.is_demo is True
        assert business.is_internal_test is False
        assert business.setup_completed_at is not None

        owner = (
            db.query(User)
            .filter(User.email == DEMO_OWNER_EMAIL, User.role == UserRole.owner)
            .one()
        )
        manager = (
            db.query(User)
            .filter(User.email == DEMO_MANAGER_EMAIL, User.role == UserRole.manager)
            .one()
        )
        assert owner.business_id == business.id
        assert manager.business_id == business.id
        assert owner.must_change_password is False
        assert manager.must_change_password is False

        employees = (
            db.query(Employee).filter(Employee.business_id == business.id).all()
        )
        names = {row.full_name for row in employees}
        emails = {
            db.get(User, row.user_id).email
            for row in employees
        }
        assert "Hannah Cruz" in names
        assert "Luis Mercado" in names
        assert DEMO_EMPLOYEE_01_EMAIL in emails
        assert DEMO_EMPLOYEE_02_EMAIL in emails
        assert all(row.business_id == business.id for row in employees)
    finally:
        db.close()


def test_demo_attendance_payroll_and_faces_belong_to_demo():
    seed_demo()
    db = SessionLocal()
    try:
        business = _business(db, DEMO_BUSINESS_CODE)
        employees = (
            db.query(Employee).filter(Employee.business_id == business.id).all()
        )
        employee_ids = {row.id for row in employees}
        assert employee_ids

        attendance = (
            db.query(AttendanceRecord)
            .filter(AttendanceRecord.business_id == business.id)
            .all()
        )
        assert attendance
        assert all(row.business_id == business.id for row in attendance)
        assert all(row.employee_id in employee_ids for row in attendance)

        adjustments = (
            db.query(PayrollAdjustment)
            .filter(PayrollAdjustment.business_id == business.id)
            .all()
        )
        assert adjustments
        assert all(row.business_id == business.id for row in adjustments)
        assert all(row.employee_id in employee_ids for row in adjustments)

        embeddings = (
            db.query(EmployeeFaceEmbedding)
            .filter(EmployeeFaceEmbedding.employee_id.in_(employee_ids))
            .all()
        )
        assert embeddings
        assert all(row.employee_id in employee_ids for row in embeddings)
        for employee in employees:
            assert employee.face_registration_status == "completed"
    finally:
        db.close()


def test_demo_seed_is_idempotent():
    seed_demo()
    db = SessionLocal()
    try:
        business = _business(db, DEMO_BUSINESS_CODE)
        users = db.query(User).filter(User.business_id == business.id).count()
        employees = (
            db.query(Employee).filter(Employee.business_id == business.id).count()
        )
        attendance = (
            db.query(AttendanceRecord)
            .filter(AttendanceRecord.business_id == business.id)
            .count()
        )
    finally:
        db.close()

    seed_demo()
    db = SessionLocal()
    try:
        business = _business(db, DEMO_BUSINESS_CODE)
        assert db.query(Business).filter(Business.business_code == DEMO_BUSINESS_CODE).count() == 1
        assert db.query(User).filter(User.business_id == business.id).count() == users
        assert (
            db.query(Employee).filter(Employee.business_id == business.id).count()
            == employees
        )
        assert (
            db.query(AttendanceRecord)
            .filter(AttendanceRecord.business_id == business.id)
            .count()
            == attendance
        )
    finally:
        db.close()


def test_demo_auth_me_exposes_is_demo():
    seed_demo()
    client = TestClient(app)
    login = client.post(
        "/api/v1/auth/business-owner-login",
        json={
            "business_code": DEMO_BUSINESS_CODE,
            "email": DEMO_OWNER_EMAIL,
            "password": DEMO_SEED_PASSWORD,
        },
    )
    assert login.status_code == 200
    body = login.json()
    assert body["is_demo"] is True
    assert body["is_internal_test"] is False

    me = client.get(
        "/api/v1/auth/me",
        headers={"Authorization": f"Bearer {body['access_token']}"},
    )
    assert me.status_code == 200
    payload = me.json()
    assert payload["is_demo"] is True
    assert payload["is_internal_test"] is False
    assert payload["business_code"] == DEMO_BUSINESS_CODE

    employee_login = client.post(
        "/api/v1/auth/login",
        json={"email": DEMO_EMPLOYEE_01_EMAIL, "password": DEMO_SEED_PASSWORD},
    )
    assert employee_login.status_code == 200
    assert employee_login.json()["is_demo"] is True
    assert employee_login.json()["is_internal_test"] is False


def test_demo_and_dev_tenants_are_isolated():
    seed_demo()
    seed_internal_test()
    db = SessionLocal()
    try:
        demo = _business(db, DEMO_BUSINESS_CODE)
        lab = _business(db, DEV_BUSINESS_CODE)
        assert demo.id != lab.id
        assert demo.business_code != lab.business_code

        demo_employee_ids = {
            row.id
            for row in db.query(Employee).filter(Employee.business_id == demo.id)
        }
        lab_employee_ids = {
            row.id
            for row in db.query(Employee).filter(Employee.business_id == lab.id)
        }
        assert demo_employee_ids
        assert lab_employee_ids
        assert demo_employee_ids.isdisjoint(lab_employee_ids)

        lab_attendance = (
            db.query(AttendanceRecord)
            .filter(AttendanceRecord.business_id == lab.id)
            .count()
        )
        assert lab_attendance == 0
        demo_attendance = (
            db.query(AttendanceRecord)
            .filter(AttendanceRecord.business_id == demo.id)
            .count()
        )
        assert demo_attendance > 0

        lab_payroll = (
            db.query(PayrollAdjustment)
            .filter(PayrollAdjustment.business_id == lab.id)
            .count()
        )
        assert lab_payroll == 0

        lab_employee = (
            db.query(Employee)
            .join(User, Employee.user_id == User.id)
            .filter(User.email == DEV_EMPLOYEE_EMAIL)
            .one()
        )
        lab_faces = (
            db.query(EmployeeFaceEmbedding)
            .filter(EmployeeFaceEmbedding.employee_id == lab_employee.id)
            .count()
        )
        assert lab_faces == 0
        assert lab_employee.face_registration_status == "not_registered"
    finally:
        db.close()


def test_admin_business_list_exposes_read_only_tenant_flags():
    """Platform admin directory labels DEMO01 / DEVTEST from the business record."""
    seed_demo()
    seed_internal_test()
    email = "admin.tenantflags@example.com"
    password = "AdminFlags!23"
    db = SessionLocal()
    try:
        existing = db.query(User).filter(User.email == email).first()
        if existing is None:
            db.add(
                User(
                    email=email,
                    password_hash=hash_password(password),
                    role=UserRole.platform_admin,
                    must_change_password=False,
                    is_active=True,
                )
            )
            db.commit()
    finally:
        db.close()
    client = TestClient(app)
    login = client.post(
        "/api/v1/auth/login",
        json={"email": email, "password": password},
    )
    assert login.status_code == 200
    token = login.json()["access_token"]
    listing = client.get(
        "/api/v1/admin/businesses",
        headers={"Authorization": f"Bearer {token}"},
    )
    assert listing.status_code == 200
    by_code = {row["business_code"]: row for row in listing.json()}
    demo = by_code[DEMO_BUSINESS_CODE]
    lab = by_code[DEV_BUSINESS_CODE]
    assert demo["is_demo"] is True
    assert demo["is_internal_test"] is False
    assert lab["is_demo"] is False
    assert lab["is_internal_test"] is True

    detail = client.get(
        f"/api/v1/admin/businesses/{demo['id']}",
        headers={"Authorization": f"Bearer {token}"},
    )
    assert detail.status_code == 200
    assert detail.json()["is_demo"] is True
    assert detail.json()["is_internal_test"] is False
    assert detail.json()["name"] == DEMO_BUSINESS_NAME
