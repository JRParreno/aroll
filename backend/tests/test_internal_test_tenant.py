"""Tests for AROLL+ Dev Lab (DEVTEST) — separate from Demo Café."""

from fastapi.testclient import TestClient

from app.db.session import SessionLocal
from app.main import app
from app.models.attendance import AttendanceRecord
from app.models.business import Business
from app.models.employee import Employee
from app.models.enums import UserRole
from app.models.face_embedding import EmployeeFaceEmbedding
from app.models.payroll_adjustment import PayrollAdjustment
from app.models.user import User
from app.seed_demo import DEMO_BUSINESS_CODE, seed_demo
from app.seed_internal_test import (
    DEV_BUSINESS_CODE,
    DEV_BUSINESS_NAME,
    DEV_EMPLOYEE_EMAIL,
    DEV_OWNER_EMAIL,
    DEV_SEED_PASSWORD,
    seed_internal_test,
)


def test_internal_test_tenant_is_not_demo():
    seed_internal_test()
    db = SessionLocal()
    try:
        lab = db.query(Business).filter(Business.business_code == DEV_BUSINESS_CODE).one()
        assert lab.name == DEV_BUSINESS_NAME
        assert lab.is_demo is False
        assert lab.is_internal_test is True
        assert lab.business_code != DEMO_BUSINESS_CODE

        owner = (
            db.query(User)
            .filter(User.email == DEV_OWNER_EMAIL, User.role == UserRole.owner)
            .one()
        )
        assert owner.business_id == lab.id
        assert owner.must_change_password is False

        employee = (
            db.query(Employee)
            .join(User, Employee.user_id == User.id)
            .filter(User.email == DEV_EMPLOYEE_EMAIL)
            .one()
        )
        assert employee.business_id == lab.id
        assert employee.full_name == "Dev Test Employee"
        assert employee.face_registration_status == "not_registered"
        assert employee.face_registered_at is None
        assert (
            db.query(EmployeeFaceEmbedding)
            .filter(EmployeeFaceEmbedding.employee_id == employee.id)
            .count()
            == 0
        )
        assert (
            db.query(AttendanceRecord)
            .filter(AttendanceRecord.business_id == lab.id)
            .count()
            == 0
        )
        assert (
            db.query(PayrollAdjustment)
            .filter(PayrollAdjustment.business_id == lab.id)
            .count()
            == 0
        )
    finally:
        db.close()


def test_internal_test_seed_is_idempotent():
    seed_internal_test()
    db = SessionLocal()
    try:
        lab = db.query(Business).filter(Business.business_code == DEV_BUSINESS_CODE).one()
        users = db.query(User).filter(User.business_id == lab.id).count()
        employees = db.query(Employee).filter(Employee.business_id == lab.id).count()
    finally:
        db.close()

    seed_internal_test()
    db = SessionLocal()
    try:
        assert (
            db.query(Business).filter(Business.business_code == DEV_BUSINESS_CODE).count()
            == 1
        )
        lab = db.query(Business).filter(Business.business_code == DEV_BUSINESS_CODE).one()
        assert db.query(User).filter(User.business_id == lab.id).count() == users
        assert db.query(Employee).filter(Employee.business_id == lab.id).count() == employees
    finally:
        db.close()


def test_internal_test_auth_me_exposes_flags():
    seed_internal_test()
    client = TestClient(app)
    login = client.post(
        "/api/v1/auth/business-owner-login",
        json={
            "business_code": DEV_BUSINESS_CODE,
            "email": DEV_OWNER_EMAIL,
            "password": DEV_SEED_PASSWORD,
        },
    )
    assert login.status_code == 200
    body = login.json()
    assert body["is_demo"] is False
    assert body["is_internal_test"] is True

    me = client.get(
        "/api/v1/auth/me",
        headers={"Authorization": f"Bearer {body['access_token']}"},
    )
    assert me.status_code == 200
    payload = me.json()
    assert payload["is_demo"] is False
    assert payload["is_internal_test"] is True
    assert payload["business_code"] == DEV_BUSINESS_CODE


def test_devtest_is_not_demo01_and_has_no_demo_rows():
    seed_demo()
    seed_internal_test()
    db = SessionLocal()
    try:
        demo = db.query(Business).filter(Business.business_code == DEMO_BUSINESS_CODE).one()
        lab = db.query(Business).filter(Business.business_code == DEV_BUSINESS_CODE).one()
        assert demo.id != lab.id
        assert lab.is_demo is False
        assert demo.is_demo is True

        demo_employee_ids = [
            row.id
            for row in db.query(Employee).filter(Employee.business_id == demo.id)
        ]
        for employee_id in demo_employee_ids:
            emp = db.get(Employee, employee_id)
            assert emp.business_id != lab.id

        assert (
            db.query(AttendanceRecord)
            .filter(
                AttendanceRecord.business_id == lab.id,
                AttendanceRecord.employee_id.in_(demo_employee_ids or [lab.id]),
            )
            .count()
            == 0
        )
        assert (
            db.query(PayrollAdjustment)
            .filter(PayrollAdjustment.business_id == lab.id)
            .count()
            == 0
        )
    finally:
        db.close()


def test_platform_admin_is_neither_demo_nor_internal_test():
    client = TestClient(app)
    login = client.post(
        "/api/v1/auth/login",
        json={"email": "admin@example.com", "password": "changeme123"},
    )
    if login.status_code != 200:
        return
    body = login.json()
    assert body.get("is_demo") is False
    assert body.get("is_internal_test") is False
    me = client.get(
        "/api/v1/auth/me",
        headers={"Authorization": f"Bearer {body['access_token']}"},
    )
    assert me.status_code == 200
    assert me.json()["is_demo"] is False
    assert me.json()["is_internal_test"] is False
    assert me.json()["business_id"] is None
