"""Incomplete attendance workflow: notifications + payroll finalize gate."""

from datetime import date
from unittest.mock import MagicMock, patch
from uuid import uuid4

import pytest
from fastapi import HTTPException

from app.models.attendance import AttendanceRecord
from app.models.employee import Employee
from app.models.enums import AttendanceStatus, UserRole
from app.models.scheduling import Shift, ShiftAssignment
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
    assert "forgot to time out" in emp_kwargs["message"].lower()

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
    filt = db.query.return_value.filter.return_value
    filt.first.return_value = None
    filt.all.return_value = []
    filt.order_by.return_value.all.return_value = []

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
        patch(
            "app.api.owner_reports.count_unresolved_scheduled_assignments_in_period",
            return_value=0,
        ),
    ):
        result = finalize_payroll(db=db, user=user, as_of=date(2026, 8, 10))

    assert result["status"] == "finalized"
    assert db.commit.called
    assert isinstance(captured.get("run"), PayrollRun)


def _shift_pair(start, end, *, name="Shift", work_date=None, employee_id=None):
    from datetime import time as time_cls

    if not isinstance(start, time_cls):
        raise TypeError(start)
    shift = Shift(
        id=uuid4(),
        business_id=uuid4(),
        name=name,
        start_time=start,
        end_time=end,
        break_minutes=0,
    )
    assignment = ShiftAssignment(
        id=uuid4(),
        shift_id=shift.id,
        employee_id=employee_id or uuid4(),
        work_date=work_date or date(2026, 8, 4),
        is_rest_day_work=False,
    )
    return shift, assignment


def _attendance(assignment, time_in, time_out, status=AttendanceStatus.complete):
    return AttendanceRecord(
        id=uuid4(),
        business_id=uuid4(),
        employee_id=assignment.employee_id,
        shift_assignment_id=assignment.id,
        time_in=time_in,
        time_out=time_out,
        status=status,
    )


def _count_unresolved(*, scheduled, records, now, today, grace=10):
    from types import SimpleNamespace

    from app.services.payroll_incomplete_gate import (
        count_unresolved_scheduled_assignments_in_period,
    )

    db = MagicMock()
    db.get.return_value = SimpleNamespace(on_time_grace_minutes=grace)
    scheduled_query = MagicMock()
    scheduled_query.join.return_value.join.return_value.filter.return_value.all.return_value = (
        scheduled
    )
    records_query = MagicMock()
    records_query.filter.return_value.all.return_value = records

    def query(*models):
        if models and models[0] is ShiftAssignment:
            return scheduled_query
        if models and models[0] is AttendanceRecord:
            return records_query
        return MagicMock()

    db.query.side_effect = query
    with patch(
        "app.services.payroll_incomplete_gate.ensure_incomplete_for_business"
    ):
        return count_unresolved_scheduled_assignments_in_period(
            db,
            business_id=uuid4(),
            period_start=date(2026, 8, 1),
            period_end=date(2026, 8, 31),
            business_timezone="Asia/Manila",
            now_local=now,
            today=today,
        )


def _finalize_db():
    from types import SimpleNamespace

    from app.models.attendance_policy import BusinessAttendancePolicy
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

    def get_side_effect(model, key=None):
        if model is BusinessPayrollConfig:
            return config
        if model is Business:
            return business
        if model is BusinessAttendancePolicy:
            return SimpleNamespace(on_time_grace_minutes=10)
        return None

    db.get.side_effect = get_side_effect
    filt = db.query.return_value.filter.return_value
    filt.first.return_value = None
    filt.all.return_value = []
    filt.order_by.return_value.all.return_value = []
    captured = {}

    def add_side_effect(obj):
        captured["run"] = obj
        if isinstance(obj, PayrollRun):
            obj.id = uuid4()

    db.add.side_effect = add_side_effect
    return db, user, captured


def _run_finalize(*, incomplete=0, pending=0):
    from app.api.owner_reports import finalize_payroll
    from app.models.payroll import PayrollRun

    db, user, captured = _finalize_db()
    with (
        patch(
            "app.api.owner_reports.resolve_pay_period",
            return_value=(date(2026, 8, 1), date(2026, 8, 31)),
        ),
        patch(
            "app.api.owner_reports.count_incomplete_attendance_in_period",
            return_value=incomplete,
        ),
        patch(
            "app.api.owner_reports.count_unresolved_scheduled_assignments_in_period",
            return_value=pending,
        ),
    ):
        result = finalize_payroll(db=db, user=user, as_of=date(2026, 8, 4))
    return result, captured, PayrollRun


def test_finalize_blocked_when_later_shift_unresolved():
    from datetime import datetime, time

    morning, morning_asg = _shift_pair(time(0, 15), time(8, 0), name="morning")
    afternoon, afternoon_asg = _shift_pair(
        time(13, 0), time(16, 0), name="afternoon", employee_id=morning_asg.employee_id
    )
    morning_rec = _attendance(
        morning_asg,
        datetime(2026, 8, 4, 0, 15),
        datetime(2026, 8, 4, 8, 0),
    )
    assert (
        _count_unresolved(
            scheduled=[(morning_asg, morning), (afternoon_asg, afternoon)],
            records=[morning_rec],
            now=datetime(2026, 8, 4, 12, 0),
            today=date(2026, 8, 4),
        )
        == 1
    )
    with pytest.raises(HTTPException) as exc:
        _run_finalize(incomplete=0, pending=1)
    assert exc.value.status_code == 400
    assert exc.value.detail["code"] == "pending_attendance"
    assert exc.value.detail["pending_attendance_count"] == 1
    assert "pending scheduled assignments" in exc.value.detail["message"].lower()


def test_finalize_allowed_when_both_shifts_complete():
    from datetime import datetime, time

    morning, morning_asg = _shift_pair(time(0, 15), time(8, 0), name="morning")
    afternoon, afternoon_asg = _shift_pair(
        time(13, 0), time(16, 0), name="afternoon", employee_id=morning_asg.employee_id
    )
    records = [
        _attendance(
            morning_asg,
            datetime(2026, 8, 4, 0, 15),
            datetime(2026, 8, 4, 8, 0),
        ),
        _attendance(
            afternoon_asg,
            datetime(2026, 8, 4, 13, 0),
            datetime(2026, 8, 4, 16, 0),
        ),
    ]
    assert (
        _count_unresolved(
            scheduled=[(morning_asg, morning), (afternoon_asg, afternoon)],
            records=records,
            now=datetime(2026, 8, 4, 17, 0),
            today=date(2026, 8, 4),
        )
        == 0
    )
    result, captured, payroll_run_cls = _run_finalize(incomplete=0, pending=0)
    assert result["status"] == "finalized"
    assert isinstance(captured.get("run"), payroll_run_cls)


def test_finalize_allowed_when_later_shift_absent_after_noshow():
    from datetime import datetime, time

    morning, morning_asg = _shift_pair(time(0, 15), time(8, 0), name="morning")
    afternoon, afternoon_asg = _shift_pair(
        time(13, 0), time(16, 0), name="afternoon", employee_id=morning_asg.employee_id
    )
    morning_rec = _attendance(
        morning_asg,
        datetime(2026, 8, 4, 0, 15),
        datetime(2026, 8, 4, 8, 0),
    )
    afternoon_rec = _attendance(
        afternoon_asg, None, None, status=AttendanceStatus.absent
    )
    assert (
        _count_unresolved(
            scheduled=[(morning_asg, morning), (afternoon_asg, afternoon)],
            records=[morning_rec, afternoon_rec],
            now=datetime(2026, 8, 4, 17, 0),
            today=date(2026, 8, 4),
        )
        == 0
    )
    # Unpunched after scheduled end + grace is also resolved (no-show).
    assert (
        _count_unresolved(
            scheduled=[(morning_asg, morning), (afternoon_asg, afternoon)],
            records=[morning_rec],
            now=datetime(2026, 8, 4, 16, 11),
            today=date(2026, 8, 4),
        )
        == 0
    )
    result, _captured, _cls = _run_finalize(incomplete=0, pending=0)
    assert result["status"] == "finalized"


def test_finalize_later_shift_incomplete_is_resolved_for_pending_gate():
    from datetime import datetime, time

    morning, morning_asg = _shift_pair(time(0, 15), time(8, 0), name="morning")
    afternoon, afternoon_asg = _shift_pair(
        time(13, 0), time(16, 0), name="afternoon", employee_id=morning_asg.employee_id
    )
    morning_rec = _attendance(
        morning_asg,
        datetime(2026, 8, 4, 0, 15),
        datetime(2026, 8, 4, 8, 0),
    )
    afternoon_rec = _attendance(
        afternoon_asg,
        datetime(2026, 8, 4, 13, 0),
        None,
        status=AttendanceStatus.incomplete,
    )
    assert (
        _count_unresolved(
            scheduled=[(morning_asg, morning), (afternoon_asg, afternoon)],
            records=[morning_rec, afternoon_rec],
            now=datetime(2026, 8, 4, 20, 0),
            today=date(2026, 8, 4),
        )
        == 0
    )
    # Existing incomplete gate still blocks the period until corrections exist.
    with pytest.raises(HTTPException) as incomplete_exc:
        _run_finalize(incomplete=1, pending=0)
    assert incomplete_exc.value.detail["code"] == "incomplete_attendance"
    # Once incomplete rows are resolved, the pending-assignment gate allows it.
    result, _captured, _cls = _run_finalize(incomplete=0, pending=0)
    assert result["status"] == "finalized"


def test_finalize_blocked_when_later_shift_has_open_punch():
    from datetime import datetime, time

    morning, morning_asg = _shift_pair(time(0, 15), time(8, 0), name="morning")
    afternoon, afternoon_asg = _shift_pair(
        time(13, 0), time(16, 0), name="afternoon", employee_id=morning_asg.employee_id
    )
    records = [
        _attendance(
            morning_asg,
            datetime(2026, 8, 4, 0, 15),
            datetime(2026, 8, 4, 8, 0),
        ),
        _attendance(
            afternoon_asg,
            datetime(2026, 8, 4, 13, 0),
            None,
            status=AttendanceStatus.in_progress,
        ),
    ]
    assert (
        _count_unresolved(
            scheduled=[(morning_asg, morning), (afternoon_asg, afternoon)],
            records=records,
            now=datetime(2026, 8, 4, 14, 0),
            today=date(2026, 8, 4),
        )
        == 1
    )
    with pytest.raises(HTTPException) as exc:
        _run_finalize(incomplete=0, pending=1)
    assert exc.value.detail["code"] == "pending_attendance"


def test_finalize_allowed_for_completed_single_shift():
    from datetime import datetime, time

    shift, assignment = _shift_pair(time(8, 0), time(17, 0), name="day")
    rec = _attendance(
        assignment, datetime(2026, 8, 4, 8, 0), datetime(2026, 8, 4, 17, 0)
    )
    assert (
        _count_unresolved(
            scheduled=[(assignment, shift)],
            records=[rec],
            now=datetime(2026, 8, 4, 18, 0),
            today=date(2026, 8, 4),
        )
        == 0
    )
    result, _captured, _cls = _run_finalize(incomplete=0, pending=0)
    assert result["status"] == "finalized"


def test_future_assignment_does_not_block_finalize():
    from datetime import datetime, time

    future_date = date(2026, 8, 20)
    shift, assignment = _shift_pair(
        time(8, 0), time(17, 0), name="future", work_date=future_date
    )
    assert (
        _count_unresolved(
            scheduled=[(assignment, shift)],
            records=[],
            now=datetime(2026, 8, 4, 12, 0),
            today=date(2026, 8, 4),
        )
        == 0
    )
    result, _captured, _cls = _run_finalize(incomplete=0, pending=0)
    assert result["status"] == "finalized"


def test_overnight_assignment_uses_next_day_end_and_grace():
    from datetime import datetime, time

    from app.services.payroll_engine import scheduled_shift_end_at

    work_date = date(2026, 8, 4)
    overnight, overnight_asg = _shift_pair(
        time(22, 0), time(6, 0), name="overnight", work_date=work_date
    )
    assert scheduled_shift_end_at(work_date, overnight) == datetime(2026, 8, 5, 6, 0)
    assert (
        _count_unresolved(
            scheduled=[(overnight_asg, overnight)],
            records=[],
            now=datetime(2026, 8, 4, 23, 0),
            today=date(2026, 8, 4),
        )
        == 1
    )
    with pytest.raises(HTTPException) as blocked:
        _run_finalize(incomplete=0, pending=1)
    assert blocked.value.detail["code"] == "pending_attendance"
    assert (
        _count_unresolved(
            scheduled=[(overnight_asg, overnight)],
            records=[],
            now=datetime(2026, 8, 5, 6, 11),
            today=date(2026, 8, 5),
        )
        == 0
    )
    result, _captured, _cls = _run_finalize(incomplete=0, pending=0)
    assert result["status"] == "finalized"


def test_one_employee_unresolved_blocks_period_not_other_employees_count():
    from datetime import datetime, time

    emp_a = uuid4()
    emp_b = uuid4()
    a_shift, a_asg = _shift_pair(
        time(8, 0), time(12, 0), name="a", employee_id=emp_a
    )
    b_morning, b_morning_asg = _shift_pair(
        time(0, 15), time(8, 0), name="b-morning", employee_id=emp_b
    )
    b_afternoon, b_afternoon_asg = _shift_pair(
        time(13, 0), time(16, 0), name="b-afternoon", employee_id=emp_b
    )
    records = [
        _attendance(a_asg, datetime(2026, 8, 4, 8, 0), datetime(2026, 8, 4, 12, 0)),
        _attendance(
            b_morning_asg,
            datetime(2026, 8, 4, 0, 15),
            datetime(2026, 8, 4, 8, 0),
        ),
    ]
    assert (
        _count_unresolved(
            scheduled=[
                (a_asg, a_shift),
                (b_morning_asg, b_morning),
                (b_afternoon_asg, b_afternoon),
            ],
            records=records,
            now=datetime(2026, 8, 4, 12, 0),
            today=date(2026, 8, 4),
        )
        == 1
    )
    with pytest.raises(HTTPException) as exc:
        _run_finalize(incomplete=0, pending=1)
    assert exc.value.detail["code"] == "pending_attendance"
    assert exc.value.detail["pending_attendance_count"] == 1
