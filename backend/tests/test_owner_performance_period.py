"""Owner performance analytics — calendar month vs rolling days."""

from datetime import date, datetime, time, timedelta
from types import SimpleNamespace
from unittest.mock import MagicMock
from uuid import uuid4

from app.api.owner_performance import get_owner_performance
from app.models.enums import AttendanceStatus, EmployeeStatus, EmploymentType


def _employee(business_id):
    return SimpleNamespace(
        id=uuid4(),
        business_id=business_id,
        full_name="Test Employee",
        position_title="Barista",
        phone=None,
        employment_type=EmploymentType.full_time,
        status=EmployeeStatus.active,
    )


def _assignment(employee_id, work_date, shift):
    return SimpleNamespace(
        id=uuid4(),
        employee_id=employee_id,
        work_date=work_date,
        shift_id=shift.id,
    )


def _shift(business_id, start=time(8, 0), end=time(16, 0)):
    return SimpleNamespace(
        id=uuid4(),
        business_id=business_id,
        start_time=start,
        end_time=end,
    )


def _record(business_id, assignment_id, time_in, time_out=None, status=AttendanceStatus.in_progress):
    return SimpleNamespace(
        business_id=business_id,
        shift_assignment_id=assignment_id,
        time_in=time_in,
        time_out=time_out,
        status=status,
    )


def test_punctuality_counts_late_as_not_punctual():
    business_id = uuid4()
    user = SimpleNamespace(business_id=business_id, role="owner")
    employee = _employee(business_id)
    shift = _shift(business_id)
    day = date(2026, 7, 10)
    assignment = _assignment(employee.id, day, shift)
    # 42 minutes late past 8:00 with 10-minute grace → late
    record = _record(
        business_id,
        assignment.id,
        time_in=datetime(2026, 7, 10, 8, 42),
        time_out=datetime(2026, 7, 10, 16, 0),
        status=AttendanceStatus.late,
    )

    db = MagicMock()
    db.get.return_value = SimpleNamespace(
        on_time_grace_minutes=10,
        overtime_minimum_minutes=30,
    )

    employee_query = MagicMock()
    employee_query.filter.return_value.order_by.return_value.all.return_value = [
        employee
    ]

    assignment_query = MagicMock()
    assignment_query.join.return_value.filter.return_value.all.return_value = [
        (assignment, shift)
    ]

    attendance_query = MagicMock()
    attendance_query.filter.return_value.all.return_value = [record]

    def query_side_effect(model, *args):
        name = getattr(model, "__name__", str(model))
        if "Employee" in name and not args:
            return employee_query
        if args or "ShiftAssignment" in name:
            return assignment_query
        return attendance_query

    # SQLAlchemy style: db.query(Employee) vs db.query(ShiftAssignment, Shift)
    def query(*models):
        if len(models) == 1 and models[0].__name__ == "Employee":
            return employee_query
        if len(models) >= 1 and models[0].__name__ == "ShiftAssignment":
            return assignment_query
        return attendance_query

    # Use type names via SimpleNamespace wrappers matching model classes
    from app.models.attendance import AttendanceRecord
    from app.models.employee import Employee
    from app.models.scheduling import Shift, ShiftAssignment

    def real_query(*models):
        if models == (Employee,):
            return employee_query
        if models[0] is ShiftAssignment:
            return assignment_query
        if models == (AttendanceRecord,):
            return attendance_query
        return MagicMock()

    db.query.side_effect = real_query

    result = get_owner_performance(
        db=db,
        user=user,
        days=30,
        year=2026,
        month=7,
    )

    assert result.summary.punctuality_rate == 0.0
    assert result.summary.late_clock_ins == 1
    assert result.summary.on_time_clock_ins == 0
    assert result.summary.attendance_rate == 100.0  # completed / assigned
    assert result.employees[0].punctuality_rate == 0.0


def test_month_filter_uses_calendar_bounds_not_rolling_days():
    """Selecting a month should not pull assignments outside that month."""
    business_id = uuid4()
    user = SimpleNamespace(business_id=business_id, role="owner")
    employee = _employee(business_id)
    shift = _shift(business_id)

    june_day = date(2026, 6, 15)
    july_day = date(2026, 7, 15)
    june_assignment = _assignment(employee.id, june_day, shift)
    july_assignment = _assignment(employee.id, july_day, shift)

    june_record = _record(
        business_id,
        june_assignment.id,
        time_in=datetime(2026, 6, 15, 8, 0),
        time_out=datetime(2026, 6, 15, 16, 0),
        status=AttendanceStatus.complete,
    )
    july_record = _record(
        business_id,
        july_assignment.id,
        time_in=datetime(2026, 7, 15, 8, 0),
        time_out=datetime(2026, 7, 15, 16, 0),
        status=AttendanceStatus.complete,
    )

    db = MagicMock()
    db.get.return_value = SimpleNamespace(
        on_time_grace_minutes=10,
        overtime_minimum_minutes=30,
    )

    employee_query = MagicMock()
    employee_query.filter.return_value.order_by.return_value.all.return_value = [
        employee
    ]

    captured_filters = {}

    assignment_query = MagicMock()

    def assignment_filter(*args, **kwargs):
        captured_filters["assignment"] = args
        filtered = MagicMock()
        filtered.all.return_value = [(july_assignment, shift)]
        return filtered

    assignment_query.join.return_value.filter.side_effect = assignment_filter

    attendance_query = MagicMock()
    attendance_query.filter.return_value.all.return_value = [july_record]

    from app.models.attendance import AttendanceRecord
    from app.models.employee import Employee
    from app.models.scheduling import ShiftAssignment

    def real_query(*models):
        if models == (Employee,):
            return employee_query
        if models[0] is ShiftAssignment:
            return assignment_query
        if models == (AttendanceRecord,):
            return attendance_query
        return MagicMock()

    db.query.side_effect = real_query

    result = get_owner_performance(
        db=db,
        user=user,
        year=2026,
        month=7,
    )

    assert result.summary.assigned_shifts == 1
    assert result.summary.on_time_clock_ins == 1
    assert result.summary.punctuality_rate == 100.0
    assert len(result.employees) == 1
