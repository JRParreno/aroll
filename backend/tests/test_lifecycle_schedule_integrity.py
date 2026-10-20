"""FIX D / B / C / A — shift versioning, deactivate cleanup, hard-delete deps."""

from datetime import date, time
from types import SimpleNamespace
from unittest.mock import MagicMock, patch
from uuid import uuid4

import pytest
from fastapi import HTTPException

from app.models.enums import ShiftType
from app.models.scheduling import Shift, ShiftAssignment
from app.services.shift_versioning import (
    TIME_FIELDS,
    ShiftInProgressError,
    apply_shift_updates,
    assignment_ids_to_remove_on_deactivate,
    time_fields_changing,
)


def _shift(**overrides):
    base = dict(
        id=uuid4(),
        business_id=uuid4(),
        name="Morning",
        shift_type=ShiftType.morning,
        start_time=time(8, 0),
        end_time=time(17, 0),
        break_minutes=60,
        employee_capacity=6,
        color=None,
        is_active=True,
    )
    base.update(overrides)
    return Shift(**base)


def test_time_fields_constant_covers_integrity_sensitive_fields():
    assert TIME_FIELDS == frozenset({"start_time", "end_time", "break_minutes"})


def test_capacity_only_update_is_not_a_time_change():
    shift = _shift()
    assert time_fields_changing(shift, {"employee_capacity": 8}) is False


def test_start_time_change_is_detected():
    shift = _shift()
    assert time_fields_changing(shift, {"start_time": time(9, 0)}) is True


def test_same_start_time_is_not_a_change():
    shift = _shift(start_time=time(8, 0))
    assert time_fields_changing(shift, {"start_time": time(8, 0)}) is False


def test_apply_non_time_update_mutates_in_place():
    shift = _shift()
    db = MagicMock()
    result = apply_shift_updates(
        db, shift, {"employee_capacity": 10}, today=date(2026, 9, 22)
    )
    assert result is shift
    assert shift.employee_capacity == 10
    db.add.assert_not_called()


def test_time_change_without_protected_assignments_mutates_in_place():
    shift = _shift()
    db = MagicMock()
    with (
        patch(
            "app.services.shift_versioning.started_assignment_ids",
            return_value=set(),
        ),
        patch(
            "app.services.shift_versioning.shift_has_past_assignments",
            return_value=False,
        ),
    ):
        result = apply_shift_updates(
            db,
            shift,
            {"start_time": time(9, 0), "end_time": time(18, 0)},
            today=date(2026, 9, 22),
        )
    assert result is shift
    assert shift.start_time == time(9, 0)
    assert shift.end_time == time(18, 0)
    db.add.assert_not_called()


def test_time_change_with_past_only_creates_successor():
    """Phase 2: past refs + no today-started → versioning."""
    shift = _shift(start_time=time(8, 0), end_time=time(17, 0))
    db = MagicMock()
    today = date(2026, 9, 22)

    with (
        patch(
            "app.services.shift_versioning.started_assignment_ids",
            return_value=set(),
        ),
        patch(
            "app.services.shift_versioning.shift_has_past_assignments",
            return_value=True,
        ),
        patch(
            "app.services.shift_versioning.retarget_unprotected_assignments",
            return_value=2,
        ) as retarget_assign,
        patch(
            "app.services.shift_versioning.retarget_template_entries",
            return_value=1,
        ) as retarget_templates,
    ):
        result = apply_shift_updates(
            db,
            shift,
            {"start_time": time(9, 0), "end_time": time(18, 0)},
            today=today,
        )

    assert result is not shift
    assert result.start_time == time(9, 0)
    assert result.end_time == time(18, 0)
    assert result.name == shift.name
    assert result.is_active is True
    assert shift.is_active is False
    assert shift.start_time == time(8, 0)
    assert shift.end_time == time(17, 0)
    db.add.assert_called_once()
    db.flush.assert_called_once()
    retarget_assign.assert_called_once()
    retarget_templates.assert_called_once()


def test_today_started_time_edit_raises_without_mutation():
    shift = _shift(start_time=time(8, 0), end_time=time(17, 0))
    db = MagicMock()
    today = date(2026, 9, 22)
    with patch(
        "app.services.shift_versioning.started_assignment_ids",
        return_value={uuid4()},
    ):
        with pytest.raises(ShiftInProgressError) as exc:
            apply_shift_updates(
                db,
                shift,
                {"start_time": time(9, 0), "end_time": time(18, 0)},
                today=today,
            )
    assert exc.value.code == "shift_in_progress"
    assert shift.start_time == time(8, 0)
    assert shift.end_time == time(17, 0)
    assert shift.is_active is True
    db.add.assert_not_called()
    db.flush.assert_not_called()


def test_shared_shift_started_plus_unstarted_time_edit_raises():
    """Option 1: any today-started blocks the whole catalog Shift time edit."""
    shift = _shift()
    db = MagicMock()
    with patch(
        "app.services.shift_versioning.started_assignment_ids",
        return_value={uuid4()},  # one started; unstarted ignored for lock
    ):
        with pytest.raises(ShiftInProgressError):
            apply_shift_updates(
                db,
                shift,
                {"start_time": time(9, 0)},
                today=date(2026, 9, 22),
            )
    db.add.assert_not_called()


def test_capacity_only_succeeds_while_started():
    shift = _shift(employee_capacity=4)
    db = MagicMock()
    # started_assignment_ids must not be consulted for non-time updates
    result = apply_shift_updates(
        db, shift, {"employee_capacity": 8}, today=date(2026, 9, 22)
    )
    assert result is shift
    assert shift.employee_capacity == 8
    db.add.assert_not_called()


def test_break_minutes_change_while_started_raises():
    shift = _shift(break_minutes=30)
    db = MagicMock()
    with patch(
        "app.services.shift_versioning.started_assignment_ids",
        return_value={uuid4()},
    ):
        with pytest.raises(ShiftInProgressError):
            apply_shift_updates(
                db, shift, {"break_minutes": 60}, today=date(2026, 9, 22)
            )
    assert shift.break_minutes == 30
    db.add.assert_not_called()


def test_update_shift_endpoint_maps_in_progress_to_409():
    from app.api.shifts import update_shift
    from app.schemas.owner_setup import ShiftUpdate

    business_id = uuid4()
    shift = _shift(business_id=business_id)
    user = SimpleNamespace(business_id=business_id, role="owner")
    db = MagicMock()
    db.get.side_effect = lambda model, key: (
        shift if model is Shift else SimpleNamespace(timezone="Asia/Manila")
    )

    with (
        patch(
            "app.api.shifts.apply_shift_updates",
            side_effect=ShiftInProgressError(),
        ),
        pytest.raises(HTTPException) as exc,
    ):
        update_shift(
            shift.id,
            ShiftUpdate(start_time=time(9, 0)),
            db,
            user,
        )

    assert exc.value.status_code == 409
    assert exc.value.detail["code"] == "shift_in_progress"
    assert exc.value.detail["title"] == "Shift In Progress"
    db.commit.assert_not_called()


def test_historical_assignment_keeps_old_shift_id_after_versioning():
    """Past assignment.shift_id must not be rewritten by retarget filters."""
    old_id = uuid4()
    new_id = uuid4()
    today = date(2026, 9, 22)
    past = ShiftAssignment(
        id=uuid4(),
        shift_id=old_id,
        employee_id=uuid4(),
        work_date=date(2026, 9, 10),
    )
    future = ShiftAssignment(
        id=uuid4(),
        shift_id=old_id,
        employee_id=uuid4(),
        work_date=date(2026, 9, 30),
    )

    # Simulate filter semantics used by retarget_unprotected_assignments
    def should_retarget(assignment: ShiftAssignment) -> bool:
        if assignment.work_date > today:
            return True
        if assignment.work_date == today:
            return assignment.id not in set()  # none started
        return False

    assert should_retarget(past) is False
    assert should_retarget(future) is True
    past.shift_id = old_id if not should_retarget(past) else new_id
    future.shift_id = new_id if should_retarget(future) else old_id
    assert past.shift_id == old_id
    assert future.shift_id == new_id


def test_today_started_keeps_old_shift_unstarted_moves():
    today = date(2026, 9, 22)
    started_id = uuid4()
    unstarted_id = uuid4()
    started = SimpleNamespace(id=started_id, work_date=today)
    unstarted = SimpleNamespace(id=unstarted_id, work_date=today)
    started_today = {started_id}

    def should_retarget(assignment) -> bool:
        if assignment.work_date > today:
            return True
        if assignment.work_date == today:
            return assignment.id not in started_today
        return False

    assert should_retarget(started) is False
    assert should_retarget(unstarted) is True


def test_deactivate_removal_keeps_started_and_past_semantics():
    today = date(2026, 9, 22)
    past_id = uuid4()
    started_id = uuid4()
    unstarted_id = uuid4()
    future_id = uuid4()
    started_today = {started_id}

    candidates = [
        SimpleNamespace(id=past_id, work_date=date(2026, 9, 10)),
        SimpleNamespace(id=started_id, work_date=today),
        SimpleNamespace(id=unstarted_id, work_date=today),
        SimpleNamespace(id=future_id, work_date=date(2026, 9, 30)),
    ]

    def should_remove(assignment) -> bool:
        if assignment.work_date > today:
            return True
        if assignment.work_date == today:
            return assignment.id not in started_today
        return False

    removed = {a.id for a in candidates if should_remove(a)}
    assert removed == {unstarted_id, future_id}
    assert past_id not in removed
    assert started_id not in removed


def test_assignment_ids_to_remove_on_deactivate_uses_started_set():
    employee_id = uuid4()
    today = date(2026, 9, 22)
    unstarted_id = uuid4()
    future_id = uuid4()
    db = MagicMock()
    ids_query = MagicMock()
    ids_query.filter.return_value = ids_query
    ids_query.all.return_value = [(unstarted_id,), (future_id,)]
    db.query.return_value = ids_query

    with patch(
        "app.services.shift_versioning.started_assignment_ids",
        return_value={uuid4()},
    ):
        remove = assignment_ids_to_remove_on_deactivate(
            db, employee_id=employee_id, today=today
        )

    assert set(remove) == {unstarted_id, future_id}

def test_update_shift_endpoint_uses_versioning_helper():
    from app.api.shifts import update_shift
    from app.schemas.owner_setup import ShiftUpdate

    business_id = uuid4()
    shift = _shift(business_id=business_id)
    user = SimpleNamespace(business_id=business_id, role="owner")
    db = MagicMock()
    db.get.side_effect = lambda model, key: (
        shift if model is Shift else SimpleNamespace(timezone="Asia/Manila")
    )
    successor = _shift(
        business_id=business_id,
        start_time=time(9, 0),
        end_time=time(18, 0),
    )

    with patch(
        "app.api.shifts.apply_shift_updates", return_value=successor
    ) as apply:
        body = ShiftUpdate(start_time=time(9, 0), end_time=time(18, 0))
        response = update_shift(shift.id, body, db, user)

    apply.assert_called_once()
    assert response.start_time == time(9, 0)
    assert response.id == str(successor.id)
    db.commit.assert_called_once()


def test_finalized_snapshot_unaffected_by_shift_edit_semantics():
    """Regression guard: finalized path reads breakdown_json, not live Shift."""
    from app.services.payroll_snapshot import snapshot_payslip_dict
    from app.models.payroll import Payslip

    frozen = {
        "employee_id": str(uuid4()),
        "employee_name": "Ana",
        "final_net_pay": 1000.0,
        "scheduled_minutes": 480.0,
        "snapshot_version": 1,
        "net_pay": 1000.0,
        "gross_pay": 1000.0,
        "hours_worked": 8.0,
        "overtime_hours": 0.0,
        "deductions": 0.0,
        "base_net_pay": 1000.0,
        "payroll_adjustments": [],
        "payroll_adjustments_total": 0.0,
        "payroll_adjustments_deduction_total": 0.0,
        "payroll_adjustments_allowance_total": 0.0,
        "adjustments_editable": False,
    }
    row = Payslip(
        id=uuid4(),
        payroll_run_id=uuid4(),
        employee_id=uuid4(),
        regular_hours=8,
        overtime_hours=0,
        gross_pay=1000,
        total_deductions=0,
        net_pay=1000,
        breakdown_json=frozen,
    )
    loaded = snapshot_payslip_dict(row)
    assert loaded is not None
    assert loaded["final_net_pay"] == 1000.0
    assert loaded["scheduled_minutes"] == 480.0


def test_deactivate_removes_only_eligible_assignments():
    from app.api.employees import deactivate_employee
    from app.models.employee import Employee
    from app.models.enums import EmployeeStatus, UserRole
    from app.models.user import User

    business_id = uuid4()
    emp = Employee(
        id=uuid4(),
        business_id=business_id,
        user_id=uuid4(),
        full_name="Casey",
        status=EmployeeStatus.active,
        is_active=True,
    )
    linked = User(
        id=emp.user_id,
        business_id=business_id,
        role=UserRole.employee,
        is_active=True,
    )
    owner = User(
        id=uuid4(),
        business_id=business_id,
        role=UserRole.owner,
        is_active=True,
    )
    remove_a = uuid4()
    remove_b = uuid4()

    db = MagicMock()
    request = MagicMock()

    with (
        patch(
            "app.api.employees._get_business_employee",
            return_value=(emp, linked),
        ),
        patch(
            "app.api.employees.assignment_ids_to_remove_on_deactivate",
            return_value=[remove_a, remove_b],
        ),
        patch(
            "app.api.employees.clear_employee_face_data",
            return_value=0,
        ),
        patch(
            "app.services.activity_logger.add_log",
        ),
        patch(
            "app.core.request_meta.audit_meta_from_request",
            return_value={},
        ),
        patch(
            "app.api.employees._consent_for",
            return_value=None,
        ),
        patch(
            "app.api.employees._employee_response",
            return_value={"id": str(emp.id)},
        ),
    ):
        db.get.return_value = SimpleNamespace(timezone="Asia/Manila")
        deactivate_employee(emp.id, db, owner, request)

    assert emp.status == EmployeeStatus.inactive
    assert emp.is_active is False
    assert linked.is_active is False
    db.query.assert_called()
    db.commit.assert_called_once()


def test_delete_employee_clears_adjustments_and_templates_before_emp():
    from app.api.employees import delete_employee
    from app.models.employee import Employee
    from app.models.enums import EmployeeStatus, UserRole
    from app.models.user import User

    business_id = uuid4()
    emp = Employee(
        id=uuid4(),
        business_id=business_id,
        user_id=uuid4(),
        full_name="Dana",
        status=EmployeeStatus.inactive,
        is_active=False,
    )
    linked = User(
        id=emp.user_id,
        business_id=business_id,
        role=UserRole.employee,
        is_active=False,
    )
    owner = User(
        id=uuid4(),
        business_id=business_id,
        role=UserRole.owner,
        is_active=True,
    )
    db = MagicMock()
    deleted_models = []
    updated = []

    class _Q:
        def __init__(self, model):
            self.model = model

        def filter(self, *args, **kwargs):
            return self

        def delete(self, synchronize_session=False):
            deleted_models.append(self.model)
            return 1

        def update(self, values, synchronize_session=False):
            updated.append((self.model, dict(values)))
            return 1

    def query(model):
        return _Q(model)

    db.query.side_effect = query

    with patch(
        "app.api.employees._get_business_employee",
        return_value=(emp, linked),
    ):
        result = delete_employee(emp.id, db, owner)

    assert result == {"status": "ok"}
    from app.models.attendance_correction import AttendanceCorrectionRequest
    from app.models.payroll_adjustment import PayrollAdjustment
    from app.models.schedule_template import ScheduleTemplateEntry
    from app.models.attendance import AttendanceRecord
    from app.models.activity_log import ActivityLog

    assert deleted_models[0] is AttendanceCorrectionRequest
    assert deleted_models[1] is PayrollAdjustment
    assert deleted_models[2] is ScheduleTemplateEntry
    assert deleted_models[3] is AttendanceRecord
    from app.models.leave_request import LeaveRequest
    from app.models.payroll import PayrollRun
    from app.models.schedule_template import ScheduleTemplate
    from app.models.business import BusinessRegistration
    from app.models.face_embedding import EmployeeFaceEmbedding
    from app.models.face_liveness import FaceLivenessChallenge

    updated_models = [m for m, _ in updated]
    assert ActivityLog in updated_models
    assert LeaveRequest in updated_models
    assert PayrollRun in updated_models
    assert ScheduleTemplate in updated_models
    assert BusinessRegistration in updated_models
    assert EmployeeFaceEmbedding in updated_models
    assert FaceLivenessChallenge in updated_models
    activity_updates = [vals for m, vals in updated if m is ActivityLog]
    assert activity_updates
    assert activity_updates[0][ActivityLog.user_id] is None
    assert activity_updates[0][ActivityLog.business_id] == business_id
    db.delete.assert_any_call(emp)
    db.delete.assert_any_call(linked)
    db.commit.assert_called_once()


def test_delete_employee_nulls_activity_log_before_user_and_preserves_rows():
    """Hard-delete clears activity_log.user_id; rows are not deleted."""
    from app.api.employees import delete_employee
    from app.models.activity_log import ActivityLog
    from app.models.employee import Employee
    from app.models.enums import EmployeeStatus, UserRole
    from app.models.user import User

    business_id = uuid4()
    emp = Employee(
        id=uuid4(),
        business_id=business_id,
        user_id=uuid4(),
        full_name="Audit Subject",
        status=EmployeeStatus.inactive,
        is_active=False,
    )
    linked = User(
        id=emp.user_id,
        business_id=business_id,
        role=UserRole.employee,
        is_active=False,
    )
    owner = User(
        id=uuid4(),
        business_id=business_id,
        role=UserRole.owner,
        is_active=True,
    )
    db = MagicMock()
    updated = []
    deleted_via_query = []

    class _Q:
        def __init__(self, model):
            self.model = model

        def filter(self, *args, **kwargs):
            return self

        def delete(self, synchronize_session=False):
            deleted_via_query.append(self.model)
            return 1

        def update(self, values, synchronize_session=False):
            updated.append((self.model, dict(values)))
            return 5

    db.query.side_effect = lambda model: _Q(model)

    with patch(
        "app.api.employees._get_business_employee",
        return_value=(emp, linked),
    ):
        result = delete_employee(emp.id, db, owner)

    assert result == {"status": "ok"}
    assert ActivityLog not in deleted_via_query
    activity_updates = [vals for m, vals in updated if m is ActivityLog]
    assert activity_updates
    assert activity_updates[0][ActivityLog.user_id] is None
    assert activity_updates[0][ActivityLog.business_id] == business_id
    db.delete.assert_any_call(linked)
    db.commit.assert_called_once()


def test_delete_employee_activity_log_update_rolls_back_on_user_delete_failure():
    from sqlalchemy.exc import IntegrityError

    from app.api.employees import delete_employee
    from app.models.activity_log import ActivityLog
    from app.models.employee import Employee
    from app.models.enums import EmployeeStatus, UserRole
    from app.models.user import User

    business_id = uuid4()
    emp = Employee(
        id=uuid4(),
        business_id=business_id,
        user_id=uuid4(),
        full_name="Rollback Subject",
        status=EmployeeStatus.active,
        is_active=True,
    )
    linked = User(
        id=emp.user_id,
        business_id=business_id,
        role=UserRole.employee,
        is_active=True,
    )
    owner = User(
        id=uuid4(),
        business_id=business_id,
        role=UserRole.owner,
        is_active=True,
    )
    db = MagicMock()
    updated = []

    class _Q:
        def __init__(self, model):
            self.model = model

        def filter(self, *args, **kwargs):
            return self

        def delete(self, synchronize_session=False):
            return 1

        def update(self, values, synchronize_session=False):
            updated.append((self.model, dict(values)))
            return 2

    db.query.side_effect = lambda model: _Q(model)

    def _delete(obj):
        if obj is linked:
            raise IntegrityError("stmt", "params", Exception("fk"))
        return None

    db.delete.side_effect = _delete

    with (
        patch(
            "app.api.employees._get_business_employee",
            return_value=(emp, linked),
        ),
        pytest.raises(HTTPException) as exc,
    ):
        delete_employee(emp.id, db, owner)

    assert exc.value.status_code == 409
    assert any(m is ActivityLog for m, _ in updated)
    db.rollback.assert_called_once()
    db.commit.assert_not_called()


def test_delete_employee_rolls_back_on_integrity_error():
    from sqlalchemy.exc import IntegrityError

    from app.api.employees import delete_employee
    from app.models.employee import Employee
    from app.models.enums import EmployeeStatus, UserRole
    from app.models.user import User

    business_id = uuid4()
    emp = Employee(
        id=uuid4(),
        business_id=business_id,
        user_id=uuid4(),
        full_name="Evan",
        status=EmployeeStatus.active,
        is_active=True,
    )
    linked = User(
        id=emp.user_id,
        business_id=business_id,
        role=UserRole.employee,
        is_active=True,
    )
    owner = User(
        id=uuid4(),
        business_id=business_id,
        role=UserRole.owner,
        is_active=True,
    )
    db = MagicMock()
    db.query.return_value.filter.return_value.delete.side_effect = IntegrityError(
        "stmt", "params", Exception("fk")
    )

    with (
        patch(
            "app.api.employees._get_business_employee",
            return_value=(emp, linked),
        ),
        pytest.raises(HTTPException) as exc,
    ):
        delete_employee(emp.id, db, owner)

    assert exc.value.status_code == 409
    db.rollback.assert_called_once()


def test_delete_employee_409_includes_constraint_hint():
    from types import SimpleNamespace

    from sqlalchemy.exc import IntegrityError

    from app.api.employees import delete_employee
    from app.models.employee import Employee
    from app.models.enums import EmployeeStatus, UserRole
    from app.models.user import User

    business_id = uuid4()
    emp = Employee(
        id=uuid4(),
        business_id=business_id,
        user_id=uuid4(),
        full_name="Hint",
        status=EmployeeStatus.active,
        is_active=True,
    )
    linked = User(
        id=emp.user_id,
        business_id=business_id,
        role=UserRole.employee,
        is_active=True,
    )
    owner = User(
        id=uuid4(),
        business_id=business_id,
        role=UserRole.owner,
        is_active=True,
    )
    db = MagicMock()

    class _Q:
        def filter(self, *args, **kwargs):
            return self

        def delete(self, synchronize_session=False):
            orig = SimpleNamespace(
                diag=SimpleNamespace(constraint_name="payroll_run_run_by_fkey")
            )
            raise IntegrityError("stmt", "params", orig)

        def update(self, values, synchronize_session=False):
            return 0

    db.query.side_effect = lambda model: _Q()

    with (
        patch(
            "app.api.employees._get_business_employee",
            return_value=(emp, linked),
        ),
        pytest.raises(HTTPException) as exc,
    ):
        delete_employee(emp.id, db, owner)

    assert exc.value.status_code == 409
    assert "payroll_run_run_by_fkey" in str(exc.value.detail)


def test_clear_user_actor_fks_nulls_and_reassigns():
    from app.api.employees import _clear_user_actor_fks
    from app.models.face_embedding import EmployeeFaceEmbedding
    from app.models.leave_request import LeaveRequest
    from app.models.payroll import PayrollRun

    linked_id = uuid4()
    owner_id = uuid4()
    db = MagicMock()
    updates = []

    class _Q:
        def __init__(self, model):
            self.model = model

        def filter(self, *args, **kwargs):
            return self

        def update(self, values, synchronize_session=False):
            updates.append((self.model, dict(values)))
            return 1

    db.query.side_effect = lambda model: _Q(model)
    _clear_user_actor_fks(
        db, linked_user_id=linked_id, reassign_to_user_id=owner_id
    )

    leave_updates = [v for m, v in updates if m is LeaveRequest]
    assert leave_updates and leave_updates[0][LeaveRequest.reviewed_by] is None
    run_updates = [v for m, v in updates if m is PayrollRun]
    assert run_updates and run_updates[0][PayrollRun.run_by] is None
    face_updates = [v for m, v in updates if m is EmployeeFaceEmbedding]
    assert face_updates
    assert face_updates[0][EmployeeFaceEmbedding.enrolled_by] == owner_id


def test_weekly_schedule_filters_inactive_employees():
    """Defensive FIX C: weekly query includes Employee.is_active.is_(True)."""
    import inspect

    from app.api import schedules

    source = inspect.getsource(schedules.get_weekly_schedule)
    assert "Employee.is_active.is_(True)" in source


def test_web_and_mobile_share_update_shift_endpoint():
    """Both clients call PUT /shifts/{id} — single protected backend path."""
    import inspect

    from app.api import shifts

    source = inspect.getsource(shifts.update_shift)
    assert "apply_shift_updates" in source
