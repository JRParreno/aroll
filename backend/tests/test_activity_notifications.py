"""Activity notification triggers, recipients, and duplicate guards."""

from datetime import date, time
from unittest.mock import MagicMock, patch
from uuid import uuid4

from app.models.attendance import AttendanceRecord
from app.models.employee import Employee
from app.models.enums import OvertimeApprovalStatus, UserRole
from app.models.payroll_adjustment import PayrollAdjustment
from app.models.scheduling import Shift, ShiftAssignment
from app.models.user import User
from app.services.activity_notifications import (
    notify_overtime_pending_if_needed,
    notify_overtime_reviewed,
    notify_payroll_adjustment_event,
    notify_schedule_assigned,
    notify_schedule_cancelled,
    notify_schedule_changed,
    notify_schedule_reuse_applied,
)


def _employee(business_id, user_id):
    return Employee(
        id=uuid4(),
        business_id=business_id,
        user_id=user_id,
        full_name="Kate Santos",
        is_active=True,
    )


def _user(user_id, business_id, role=UserRole.employee):
    return User(
        id=user_id,
        business_id=business_id,
        role=role,
        is_active=True,
    )


def _db(get_map, owners=None):
    db = MagicMock()

    def getter(model, key):
        return get_map.get((model, key))

    db.get.side_effect = getter
    db.query.return_value.filter.return_value.all.return_value = owners or []
    return db


def test_overtime_pending_notifies_employee_and_owner():
    business_id = uuid4()
    emp_user_id = uuid4()
    employee = _employee(business_id, emp_user_id)
    emp_user = _user(emp_user_id, business_id)
    owner = _user(uuid4(), business_id, UserRole.owner)
    assignment = ShiftAssignment(
        id=uuid4(),
        shift_id=uuid4(),
        employee_id=employee.id,
        work_date=date(2026, 10, 20),
    )
    shift = Shift(
        id=assignment.shift_id,
        business_id=business_id,
        name="Evening",
        start_time=time(18, 30),
        end_time=time(22, 0),
    )
    record = AttendanceRecord(
        id=uuid4(),
        business_id=business_id,
        employee_id=employee.id,
        shift_assignment_id=assignment.id,
        ot_approval_status=OvertimeApprovalStatus.pending,
    )
    db = _db(
        {
            (Employee, employee.id): employee,
            (User, emp_user_id): emp_user,
            (ShiftAssignment, assignment.id): assignment,
            (Shift, shift.id): shift,
        },
        owners=[owner],
    )
    with (
        patch(
            "app.services.activity_notifications.notify_user_once"
        ) as notify_once,
        patch(
            "app.services.activity_notifications.notify_owners_once"
        ) as notify_owners,
    ):
        notify_overtime_pending_if_needed(db, record)

    assert notify_once.called
    emp = notify_once.call_args.kwargs
    assert emp["type"] == "overtime_submitted"
    assert emp["user"] is emp_user
    assert "awaiting approval" in emp["message"].lower()
    assert "approved" not in emp["message"].lower().replace("awaiting approval", "")
    assert notify_owners.called
    owner_kwargs = notify_owners.call_args.kwargs
    assert owner_kwargs["type"] == "overtime_submitted"
    assert "Kate Santos" in owner_kwargs["message"]


def test_overtime_pending_skips_when_not_pending():
    record = AttendanceRecord(
        id=uuid4(),
        business_id=uuid4(),
        employee_id=uuid4(),
        ot_approval_status=None,
    )
    with patch("app.services.activity_notifications.notify_user_once") as notify_once:
        notify_overtime_pending_if_needed(MagicMock(), record)
    assert not notify_once.called


def test_overtime_approved_includes_duration_when_available():
    business_id = uuid4()
    emp_user_id = uuid4()
    employee = _employee(business_id, emp_user_id)
    emp_user = _user(emp_user_id, business_id)
    record = AttendanceRecord(
        id=uuid4(),
        business_id=business_id,
        employee_id=employee.id,
        ot_approval_status=OvertimeApprovalStatus.approved,
    )
    db = _db({(Employee, employee.id): employee, (User, emp_user_id): emp_user})
    with (
        patch(
            "app.services.activity_notifications.overtime_identifying_label",
            return_value="Oct 20, 2026 (Evening)",
        ),
        patch(
            "app.services.activity_notifications._qualifying_ot_minutes",
            return_value=45.0,
        ),
        patch("app.services.activity_notifications.notify_user_once") as notify_once,
    ):
        notify_overtime_reviewed(db, record, approved=True)
    kwargs = notify_once.call_args.kwargs
    assert kwargs["type"] == "overtime_approved"
    assert "approved" in kwargs["message"].lower()
    assert "45 minutes" in kwargs["message"]


def test_overtime_rejected_does_not_invent_reason():
    business_id = uuid4()
    emp_user_id = uuid4()
    employee = _employee(business_id, emp_user_id)
    emp_user = _user(emp_user_id, business_id)
    record = AttendanceRecord(
        id=uuid4(),
        business_id=business_id,
        employee_id=employee.id,
        ot_approval_status=OvertimeApprovalStatus.rejected,
    )
    db = _db({(Employee, employee.id): employee, (User, emp_user_id): emp_user})
    with (
        patch(
            "app.services.activity_notifications.overtime_identifying_label",
            return_value="Oct 20, 2026",
        ),
        patch(
            "app.services.activity_notifications._qualifying_ot_minutes",
            return_value=30.0,
        ),
        patch("app.services.activity_notifications.notify_user_once") as notify_once,
    ):
        notify_overtime_reviewed(db, record, approved=False)
    kwargs = notify_once.call_args.kwargs
    assert kwargs["type"] == "overtime_rejected"
    assert "not approved" in kwargs["message"].lower()
    assert "because" not in kwargs["message"].lower()


def test_payroll_adjustment_actions_are_distinct():
    business_id = uuid4()
    emp_user_id = uuid4()
    employee = _employee(business_id, emp_user_id)
    emp_user = _user(emp_user_id, business_id)
    row = PayrollAdjustment(
        id=uuid4(),
        business_id=business_id,
        employee_id=employee.id,
        period_start=date(2026, 10, 1),
        period_end=date(2026, 10, 15),
        kind="allowance",
        type_key="meal",
        amount=100,
    )
    db = _db({(Employee, employee.id): employee, (User, emp_user_id): emp_user})
    with (
        patch("app.services.activity_notifications.display_name", return_value="Meal"),
        patch("app.services.activity_notifications.notify_user_once") as once,
        patch("app.services.activity_notifications.notify_user") as notify_user,
    ):
        notify_payroll_adjustment_event(db, row, action="added")
        notify_payroll_adjustment_event(db, row, action="changed")
        notify_payroll_adjustment_event(db, row, action="removed")
    types = [call.kwargs["type"] for call in once.call_args_list]
    assert "payroll_adjustment_added" in types
    assert "payroll_adjustment_removed" in types
    assert notify_user.call_args.kwargs["type"] == "payroll_adjustment_changed"
    assert "updated" in notify_user.call_args.kwargs["message"].lower()
    assert "removed" in once.call_args_list[-1].kwargs["message"].lower()


def test_schedule_assigned_only_notifies_that_employee():
    business_id = uuid4()
    emp_user_id = uuid4()
    employee = _employee(business_id, emp_user_id)
    other = _employee(business_id, uuid4())
    emp_user = _user(emp_user_id, business_id)
    shift = Shift(
        id=uuid4(),
        business_id=business_id,
        name="Morning",
        start_time=time(8, 0),
        end_time=time(17, 0),
    )
    assignment = ShiftAssignment(
        id=uuid4(),
        shift_id=shift.id,
        employee_id=employee.id,
        work_date=date(2026, 10, 21),
    )
    db = _db({(User, emp_user_id): emp_user})
    with patch("app.services.activity_notifications.notify_user_once") as once:
        notify_schedule_assigned(
            db, assignment=assignment, shift=shift, employee=employee
        )
    assert once.call_args.kwargs["user"] is emp_user
    assert once.call_args.kwargs["user"].id != other.user_id
    assert "Oct 21, 2026" in once.call_args.kwargs["message"]
    assert "8:00 AM" in once.call_args.kwargs["message"]


def test_schedule_change_and_cancel_use_distinct_types():
    business_id = uuid4()
    emp_user_id = uuid4()
    employee = _employee(business_id, emp_user_id)
    emp_user = _user(emp_user_id, business_id)
    shift = Shift(
        id=uuid4(),
        business_id=business_id,
        name="Morning",
        start_time=time(8, 0),
        end_time=time(17, 0),
    )
    assignment = ShiftAssignment(
        id=uuid4(),
        shift_id=shift.id,
        employee_id=employee.id,
        work_date=date(2026, 10, 21),
    )
    db = _db({(User, emp_user_id): emp_user})
    with (
        patch("app.services.activity_notifications.notify_user") as notify_user,
        patch("app.services.activity_notifications.notify_user_once") as once,
    ):
        notify_schedule_changed(
            db, assignment=assignment, shift=shift, employee=employee
        )
        notify_schedule_cancelled(
            db,
            employee=employee,
            work_date=assignment.work_date,
            shift=shift,
            assignment_id=assignment.id,
        )
    assert notify_user.call_args.kwargs["type"] == "schedule_changed"
    assert once.call_args.kwargs["type"] == "schedule_cancelled"
    assert "cancelled" in once.call_args.kwargs["message"].lower()


def test_reuse_skips_recreated_same_slot():
    business_id = uuid4()
    employee = _employee(business_id, uuid4())
    shift = Shift(
        id=uuid4(),
        business_id=business_id,
        name="Morning",
        start_time=time(8, 0),
        end_time=time(17, 0),
    )
    assignment = ShiftAssignment(
        id=uuid4(),
        shift_id=shift.id,
        employee_id=employee.id,
        work_date=date(2026, 10, 21),
    )
    db = MagicMock()
    with (
        patch("app.services.activity_notifications.notify_schedule_cancelled") as cancel,
        patch("app.services.activity_notifications.notify_schedule_assigned") as assign,
    ):
        notify_schedule_reuse_applied(
            db,
            removed=[
                {
                    "assignment_id": assignment.id,
                    "employee": employee,
                    "shift": shift,
                    "work_date": date(2026, 10, 21),
                }
            ],
            created=[
                {
                    "assignment": assignment,
                    "employee_id": employee.id,
                    "shift": shift,
                    "work_date": date(2026, 10, 21),
                }
            ],
        )
    assert not cancel.called
    assert not assign.called


def test_helper_failure_does_not_raise():
    record = AttendanceRecord(
        id=uuid4(),
        business_id=uuid4(),
        employee_id=uuid4(),
        ot_approval_status=OvertimeApprovalStatus.pending,
    )
    db = MagicMock()
    db.get.side_effect = RuntimeError("db down")
    notify_overtime_pending_if_needed(db, record)
