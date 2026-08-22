"""Incomplete attendance workflow: notifications + payroll finalize gate."""

from datetime import date
from unittest.mock import MagicMock, patch
from uuid import uuid4

import pytest
from fastapi import HTTPException

from app.models.attendance import AttendanceRecord
from app.models.employee import Employee
from app.models.enums import AttendanceStatus, UserRole
from app.models.scheduling import ShiftAssignment
from app.models.user import User
from app.services.incomplete_attendance_notify import notify_incomplete_attendance
from app.services.payroll_incomplete_gate import count_incomplete_attendance_in_period


def test_notify_incomplete_sends_employee_and_owner():
    business_id = uuid4()
    record_id = uuid4()
    employee_user_id = uuid4()
    owner_id = uuid4()
    assignment_id = uuid4()

    employee = Employee(
        id=uuid4(),
        business_id=business_id,
        user_id=employee_user_id,
        full_name="Juan Dela Cruz",
        is_active=True,
    )
    record = AttendanceRecord(
        id=record_id,
        business_id=business_id,
        employee_id=employee.id,
        shift_assignment_id=assignment_id,
        status=AttendanceStatus.incomplete,
    )
    assignment = ShiftAssignment(
        id=assignment_id,
        shift_id=uuid4(),
        employee_id=employee.id,
        work_date=date(2026, 8, 3),
    )
    emp_user = User(
        id=employee_user_id,
        business_id=business_id,
        role=UserRole.employee,
        is_active=True,
    )
    owner = User(
        id=owner_id,
        business_id=business_id,
        role=UserRole.owner,
        is_active=True,
    )

    db = MagicMock()

    def get_side_effect(model, key):
        if model is Employee:
            return employee
        if model is ShiftAssignment:
            return assignment
        if model is User and key == employee_user_id:
            return emp_user
        return None

    db.get.side_effect = get_side_effect
    db.query.return_value.filter.return_value.all.return_value = [owner]

    with (
        patch(
            "app.services.incomplete_attendance_notify.notification_exists_for_entity",
            return_value=False,
        ) as exists,
        patch(
            "app.services.incomplete_attendance_notify.notify_user"
        ) as notify_user,
        patch(
            "app.services.incomplete_attendance_notify.create_notification"
        ) as create_notification,
    ):
        notify_incomplete_attendance(db, record=record, employee=employee)

    assert notify_user.called
    emp_kwargs = notify_user.call_args.kwargs
    assert emp_kwargs["type"] == "incomplete_attendance"
    assert "forgot to clock out" in emp_kwargs["message"].lower()

    assert create_notification.called
    owner_kwargs = create_notification.call_args.kwargs
    assert owner_kwargs["type"] == "incomplete_attendance"
    assert "Juan Dela Cruz" in owner_kwargs["message"]
    assert "requiring review" in owner_kwargs["message"]
    assert exists.call_count >= 2


def test_notify_incomplete_skips_duplicates():
    business_id = uuid4()
    record_id = uuid4()
    employee_user_id = uuid4()
    employee = Employee(
        id=uuid4(),
        business_id=business_id,
        user_id=employee_user_id,
        full_name="Ana Reyes",
        is_active=True,
    )
    record = AttendanceRecord(
        id=record_id,
        business_id=business_id,
        employee_id=employee.id,
        shift_assignment_id=None,
        status=AttendanceStatus.incomplete,
    )
    emp_user = User(
        id=employee_user_id,
        business_id=business_id,
        role=UserRole.employee,
        is_active=True,
    )
    owner = User(
        id=uuid4(),
        business_id=business_id,
        role=UserRole.manager,
        is_active=True,
    )
    db = MagicMock()
    db.get.side_effect = lambda model, key: {
        (Employee, employee.id): employee,
        (User, employee_user_id): emp_user,
    }.get((model, key))
    db.query.return_value.filter.return_value.all.return_value = [owner]

    with (
        patch(
            "app.services.incomplete_attendance_notify.notification_exists_for_entity",
            return_value=True,
        ),
        patch(
            "app.services.incomplete_attendance_notify.notify_user"
        ) as notify_user,
        patch(
            "app.services.incomplete_attendance_notify.create_notification"
        ) as create_notification,
    ):
        notify_incomplete_attendance(db, record=record, employee=employee)

    assert not notify_user.called
    assert not create_notification.called


def test_count_incomplete_attendance_in_period():
    business_id = uuid4()
    db = MagicMock()
    db.query.return_value.outerjoin.return_value.filter.return_value.count.return_value = (
        3
    )

    with patch(
        "app.services.payroll_incomplete_gate.ensure_incomplete_for_business"
    ) as ensure:
        count = count_incomplete_attendance_in_period(
            db,
            business_id=business_id,
            period_start=date(2026, 8, 1),
            period_end=date(2026, 8, 15),
            business_timezone="Asia/Manila",
        )

    assert count == 3
    ensure.assert_called_once()


def test_finalize_payroll_blocked_when_incomplete_exists():
    from app.api.owner_reports import finalize_payroll
    from app.models.business import Business
    from app.models.payroll import BusinessPayrollConfig

    business_id = uuid4()
    user = User(
        id=uuid4(),
        business_id=business_id,
        role=UserRole.owner,
        is_active=True,
    )
    config = BusinessPayrollConfig(business_id=business_id)
    business = Business(id=business_id, timezone="Asia/Manila")
    db = MagicMock()

    def get_side_effect(model, key):
        if model is BusinessPayrollConfig:
            return config
        if model is Business:
            return business
        return None

    db.get.side_effect = get_side_effect
    db.query.return_value.filter.return_value.first.return_value = None

    with (
        patch(
            "app.api.owner_reports.resolve_pay_period",
            return_value=(date(2026, 8, 1), date(2026, 8, 15)),
        ),
        patch(
            "app.api.owner_reports.count_incomplete_attendance_in_period",
            return_value=2,
        ),
    ):
        with pytest.raises(HTTPException) as exc:
            finalize_payroll(db=db, user=user, as_of=date(2026, 8, 10))

    assert exc.value.status_code == 400
    assert exc.value.detail["code"] == "incomplete_attendance"
    assert "incomplete attendance" in exc.value.detail["message"].lower()


def test_finalize_payroll_succeeds_when_no_incomplete():
    from app.api.owner_reports import finalize_payroll
    from app.models.business import Business
    from app.models.payroll import BusinessPayrollConfig, PayrollRun

    business_id = uuid4()
    user = User(
        id=uuid4(),
        business_id=business_id,
        role=UserRole.owner,
        is_active=True,
    )
    config = BusinessPayrollConfig(business_id=business_id)
    business = Business(id=business_id, timezone="Asia/Manila")
    db = MagicMock()

    def get_side_effect(model, key):
        if model is BusinessPayrollConfig:
            return config
        if model is Business:
            return business
        return None

    db.get.side_effect = get_side_effect
    db.query.return_value.filter.return_value.first.return_value = None

    captured = {}

    def add_side_effect(obj):
        captured["run"] = obj
        if isinstance(obj, PayrollRun):
            obj.id = uuid4()

    db.add.side_effect = add_side_effect

    with (
        patch(
            "app.api.owner_reports.resolve_pay_period",
            return_value=(date(2026, 8, 1), date(2026, 8, 15)),
        ),
        patch(
            "app.api.owner_reports.count_incomplete_attendance_in_period",
            return_value=0,
        ),
    ):
        result = finalize_payroll(db=db, user=user, as_of=date(2026, 8, 10))

    assert result["status"] == "finalized"
    assert db.commit.called
    assert isinstance(captured.get("run"), PayrollRun)
