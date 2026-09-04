"""Idempotent seed for AROLL+ Dev Lab (DEVTEST).

Internal development/testing tenant only. Not used for defense or research
evaluation. No demo faces, demo attendance, or demo payroll rows.
"""

from __future__ import annotations

import logging
from datetime import datetime, timezone

from sqlalchemy import func
from sqlalchemy.orm import Session

from app.core.security import hash_password
from app.db.session import SessionLocal
from app.models.attendance_policy import BusinessAttendancePolicy
from app.models.business import Business, BusinessLocation
from app.models.employee import Employee
from app.models.enums import (
    BusinessStatus,
    EmployeeStatus,
    EmploymentType,
    PayBasis,
    PayPeriodType,
    UserRole,
    Weekday,
)
from app.models.leave_policy import BusinessLeavePolicy
from app.models.payroll import BusinessPayrollConfig, Position
from app.models.rest_day_policy import BusinessRestDayPolicy
from app.models.user import User
from app.services.leave_policy import default_treatments

logger = logging.getLogger("aroll.seed.internal_test")

DEV_BUSINESS_CODE = "DEVTEST"
DEV_BUSINESS_NAME = "AROLL+ Dev Lab"
DEV_TIMEZONE = "Asia/Manila"
DEV_OWNER_EMAIL = "owner.dev@example.com"
DEV_EMPLOYEE_EMAIL = "employee.dev@example.com"
DEV_SEED_PASSWORD = "DevLab!23"

# Placeholder pin the team can replace in Location settings. Not Demo Café.
DEV_LATITUDE = 14.6500000
DEV_LONGITUDE = 121.0300000
DEV_ADDRESS = "Dev Lab test pin — replace with your controlled test site"


def seed_internal_test(db: Session | None = None) -> Business:
    own_session = db is None
    if own_session:
        db = SessionLocal()
    try:
        business = _upsert_business(db)
        _upsert_policies(db, business)
        _upsert_location(db, business)
        position = _upsert_position(db, business)
        _upsert_user(
            db,
            business,
            email=DEV_OWNER_EMAIL,
            role=UserRole.owner,
        )
        _upsert_employee(db, business, position=position)
        db.commit()
        db.refresh(business)
        logger.info(
            "Seeded internal-test tenant %s (%s)",
            business.name,
            business.business_code,
        )
        return business
    except Exception:
        db.rollback()
        raise
    finally:
        if own_session:
            db.close()


def _upsert_business(db: Session) -> Business:
    business = (
        db.query(Business)
        .filter(func.upper(Business.business_code) == DEV_BUSINESS_CODE)
        .first()
    )
    now = datetime.now(timezone.utc)
    if business is None:
        business = Business(
            business_code=DEV_BUSINESS_CODE,
            name=DEV_BUSINESS_NAME,
            status=BusinessStatus.active,
            timezone=DEV_TIMEZONE,
            business_type="Internal development",
            setup_completed_at=now,
            is_demo=False,
            is_internal_test=True,
        )
        db.add(business)
        db.flush()
        return business
    business.name = DEV_BUSINESS_NAME
    business.status = BusinessStatus.active
    business.timezone = DEV_TIMEZONE
    business.is_demo = False
    business.is_internal_test = True
    if business.setup_completed_at is None:
        business.setup_completed_at = now
    db.flush()
    return business


def _upsert_policies(db: Session, business: Business) -> None:
    if db.get(BusinessPayrollConfig, business.id) is None:
        db.add(
            BusinessPayrollConfig(
                business_id=business.id,
                pay_period_type=PayPeriodType.monthly,
                monthly_payday_day=30,
            )
        )
    if db.get(BusinessAttendancePolicy, business.id) is None:
        db.add(BusinessAttendancePolicy(business_id=business.id))
    if db.get(BusinessRestDayPolicy, business.id) is None:
        db.add(
            BusinessRestDayPolicy(
                business_id=business.id,
                weekly_rest_day=Weekday.sunday,
            )
        )
    if db.get(BusinessLeavePolicy, business.id) is None:
        db.add(
            BusinessLeavePolicy(
                business_id=business.id,
                treatments=default_treatments(),
                config_json={},
            )
        )
    db.flush()


def _upsert_location(db: Session, business: Business) -> BusinessLocation:
    location = (
        db.query(BusinessLocation)
        .filter(
            BusinessLocation.business_id == business.id,
            BusinessLocation.is_primary.is_(True),
        )
        .first()
    )
    if location is None:
        location = BusinessLocation(
            business_id=business.id,
            label="Dev Lab",
            address=DEV_ADDRESS,
            latitude=DEV_LATITUDE,
            longitude=DEV_LONGITUDE,
            geofence_radius_m=75,
            is_primary=True,
        )
        db.add(location)
        db.flush()
        return location
    db.flush()
    return location


def _upsert_position(db: Session, business: Business) -> Position:
    row = (
        db.query(Position)
        .filter(Position.business_id == business.id, Position.title == "QA Tester")
        .first()
    )
    if row is None:
        row = Position(
            business_id=business.id,
            title="QA Tester",
            daily_rate=500.00,
            hourly_rate=None,
            description="Internal test employee role",
            is_active=True,
        )
        db.add(row)
        db.flush()
    return row


def _upsert_user(
    db: Session,
    business: Business,
    *,
    email: str,
    role: UserRole,
) -> User:
    user = (
        db.query(User)
        .filter(User.business_id == business.id, User.role == role)
        .first()
        if role == UserRole.owner
        else (
            db.query(User)
            .filter(
                User.business_id == business.id,
                func.lower(User.email) == email.lower(),
                User.role == role,
            )
            .first()
        )
    )
    if user is None:
        user = User(
            business_id=business.id,
            email=email.lower(),
            password_hash=hash_password(DEV_SEED_PASSWORD),
            role=role,
            is_active=True,
            must_change_password=False,
            pending_temporary_password=None,
        )
        db.add(user)
        db.flush()
        return user
    user.email = email.lower()
    user.is_active = True
    user.must_change_password = False
    user.pending_temporary_password = None
    db.flush()
    return user


def _upsert_employee(
    db: Session, business: Business, *, position: Position
) -> Employee:
    employee = (
        db.query(Employee)
        .filter(
            Employee.business_id == business.id,
            Employee.employee_code == "DEV-01",
        )
        .first()
    )
    if employee is None:
        user = _upsert_user(
            db, business, email=DEV_EMPLOYEE_EMAIL, role=UserRole.employee
        )
        employee = db.query(Employee).filter(Employee.user_id == user.id).first()
    else:
        user = db.get(User, employee.user_id)
        if user is not None:
            user.email = DEV_EMPLOYEE_EMAIL.lower()
            user.is_active = True
            user.must_change_password = False
            user.pending_temporary_password = None
    if employee is None:
        employee = Employee(
            business_id=business.id,
            user_id=user.id,
            position_id=position.id,
            employee_code="DEV-01",
            full_name="Dev Test Employee",
            position_title=position.title,
            employment_type=EmploymentType.full_time,
            pay_basis=PayBasis.daily,
            daily_rate=500.00,
            hourly_rate=None,
            status=EmployeeStatus.active,
            is_active=True,
            face_registration_status="not_registered",
            face_registered_at=None,
        )
        db.add(employee)
        db.flush()
        return employee
    if employee.face_registration_status != "completed":
        employee.face_registration_status = "not_registered"
        employee.face_registered_at = None
    employee.status = EmployeeStatus.active
    employee.is_active = True
    db.flush()
    return employee
