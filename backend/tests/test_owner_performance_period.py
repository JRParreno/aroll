"""Owner performance analytics — calendar month vs rolling days."""

from datetime import date, datetime, time, timezone
from types import SimpleNamespace
from unittest.mock import MagicMock, patch
from uuid import uuid4
from zoneinfo import ZoneInfo

from app.api.owner_performance import get_owner_performance
from app.models.attendance import AttendanceRecord
from app.models.employee import Employee
from app.models.enums import AttendanceStatus, EmployeeStatus, EmploymentType
from app.models.scheduling import ShiftAssignment


def _employee(business_id):
    return SimpleNamespace(
        id=uuid4(),
        business_id=business_id,
        full_name="Test Employee",
        position_title="Barista",
        phone=None,
        profile_image_url=None,
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


def _shift(business_id, start=time(8, 0), end=time(16, 0), name="shift"):
    return SimpleNamespace(
        id=uuid4(),
        business_id=business_id,
        name=name,
        start_time=start,
        end_time=end,
    )


def _record(
    business_id,
    assignment_id,
    time_in,
    time_out=None,
    status=AttendanceStatus.in_progress,
):
    return SimpleNamespace(
        business_id=business_id,
        shift_assignment_id=assignment_id,
        time_in=time_in,
        time_out=time_out,
        status=status,
    )


def _policy(**overrides):
    data = {
        "timezone": "Asia/Manila",
        "on_time_grace_minutes": 10,
        "overtime_minimum_minutes": 30,
        "absent_threshold_minutes": 120,
    }
    data.update(overrides)
    return SimpleNamespace(**data)


def _mock_performance_db(*, employees, assignment_rows, records, policy=None):
    db = MagicMock()
    db.get.return_value = policy or _policy()

    employee_query = MagicMock()
    employee_query.filter.return_value.order_by.return_value.all.return_value = (
        employees
    )
    assignment_query = MagicMock()
    assignment_query.join.return_value.filter.return_value.all.return_value = (
        assignment_rows
    )
    attendance_query = MagicMock()
    attendance_query.filter.return_value.all.return_value = records

    def real_query(*models):
        if models == (Employee,):
            return employee_query
        if models[0] is ShiftAssignment:
            return assignment_query
        if models == (AttendanceRecord,):
            return attendance_query
        return MagicMock()

    db.query.side_effect = real_query
    return db


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
    db = _mock_performance_db(
        employees=[employee],
        assignment_rows=[(assignment, shift)],
        records=[record],
    )

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

    july_day = date(2026, 7, 15)
    july_assignment = _assignment(employee.id, july_day, shift)

    july_record = _record(
        business_id,
        july_assignment.id,
        time_in=datetime(2026, 7, 15, 8, 0),
        time_out=datetime(2026, 7, 15, 16, 0),
        status=AttendanceStatus.complete,
    )

    db = MagicMock()
    db.get.return_value = _policy()

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


def test_punctuality_converts_utc_time_in_to_business_timezone():
    """UTC punches must be classified in the business timezone, not UTC wall clock.

    9:00 AM Asia/Manila shift, 10-minute grace, Time In 9:20 AM Manila
    is stored as 1:20 AM UTC and must count as late — not on time.
    """
    business_id = uuid4()
    user = SimpleNamespace(business_id=business_id, role="owner")
    employee = _employee(business_id)
    shift = _shift(business_id, start=time(9, 0), end=time(17, 0))
    day = date(2026, 7, 10)
    assignment = _assignment(employee.id, day, shift)
    record = _record(
        business_id,
        assignment.id,
        time_in=datetime(2026, 7, 10, 1, 20, tzinfo=timezone.utc),
        time_out=datetime(2026, 7, 10, 9, 0, tzinfo=timezone.utc),
        status=AttendanceStatus.late,
    )
    db = _mock_performance_db(
        employees=[employee],
        assignment_rows=[(assignment, shift)],
        records=[record],
    )

    result = get_owner_performance(
        db=db,
        user=user,
        days=30,
        year=2026,
        month=7,
    )

    assert result.summary.late_clock_ins == 1
    assert result.summary.on_time_clock_ins == 0
    assert result.summary.punctuality_rate == 0.0
    assert result.employees[0].late_clock_ins == 1
    assert result.employees[0].on_time_clock_ins == 0


def _unpunched_setup(*, now, cutoff_minutes, start=time(13, 0), end=time(15, 0)):
    business_id = uuid4()
    user = SimpleNamespace(business_id=business_id, role="owner")
    employee = _employee(business_id)
    day = now.date()
    shift = _shift(business_id, start=start, end=end, name="afternoon")
    assignment = _assignment(employee.id, day, shift)
    db = _mock_performance_db(
        employees=[employee],
        assignment_rows=[(assignment, shift)],
        records=[],
        policy=_policy(absent_threshold_minutes=cutoff_minutes),
    )
    return user, db


def test_future_unpunched_shift_is_not_absent():
    """1:00 PM shift at 10:00 AM must not count as Absent or assigned."""
    now = datetime(2026, 8, 28, 10, 0, tzinfo=ZoneInfo("Asia/Manila"))
    user, db = _unpunched_setup(now=now, cutoff_minutes=120)

    with (
        patch("app.api.owner_performance.business_now", return_value=now),
        patch("app.api.owner_performance.business_today", return_value=now.date()),
    ):
        result = get_owner_performance(db=db, user=user, days=30)

    assert result.summary.absent_shifts == 0
    assert result.summary.assigned_shifts == 0
    assert result.summary.attendance_rate == 0.0
    assert result.employees == []


def test_started_unpunched_shift_before_cutoff_is_not_absent():
    """Shift started at 1:00 PM, cutoff 120 min, now 1:30 PM → not Absent."""
    now = datetime(2026, 8, 28, 13, 30, tzinfo=ZoneInfo("Asia/Manila"))
    user, db = _unpunched_setup(now=now, cutoff_minutes=120)

    with (
        patch("app.api.owner_performance.business_now", return_value=now),
        patch("app.api.owner_performance.business_today", return_value=now.date()),
    ):
        result = get_owner_performance(db=db, user=user, days=30)

    assert result.summary.absent_shifts == 0
    assert result.summary.assigned_shifts == 0


def test_unpunched_shift_after_configured_cutoff_is_absent():
    """1:00 PM start + 120 min cutoff, now 3:01 PM, no Time In → Absent."""
    now = datetime(2026, 8, 28, 15, 1, tzinfo=ZoneInfo("Asia/Manila"))
    user, db = _unpunched_setup(now=now, cutoff_minutes=120)

    with (
        patch("app.api.owner_performance.business_now", return_value=now),
        patch("app.api.owner_performance.business_today", return_value=now.date()),
    ):
        result = get_owner_performance(db=db, user=user, days=30)

    assert result.summary.absent_shifts == 1
    assert result.summary.assigned_shifts == 1
    assert result.summary.on_time_clock_ins == 0
    assert result.summary.late_clock_ins == 0
    assert result.employees[0].absent_shifts == 1


def test_noshow_cutoff_uses_policy_value_not_a_hardcoded_window():
    """A 60-minute Payroll Absent Cutoff must mark absent at 2:01, not 3:01."""
    now = datetime(2026, 8, 28, 14, 1, tzinfo=ZoneInfo("Asia/Manila"))
    user, db = _unpunched_setup(now=now, cutoff_minutes=60)

    with (
        patch("app.api.owner_performance.business_now", return_value=now),
        patch("app.api.owner_performance.business_today", return_value=now.date()),
    ):
        result = get_owner_performance(db=db, user=user, days=30)

    assert result.summary.absent_shifts == 1


def test_punched_shift_keeps_late_classification():
    """A Time In is classified by grace, not the unpunched no-show cutoff."""
    business_id = uuid4()
    user = SimpleNamespace(business_id=business_id, role="owner")
    employee = _employee(business_id)
    day = date(2026, 8, 28)
    shift = _shift(business_id, start=time(8, 30), end=time(12, 30), name="morning")
    assignment = _assignment(employee.id, day, shift)
    record = _record(
        business_id,
        assignment.id,
        time_in=datetime(2026, 8, 28, 0, 55, tzinfo=timezone.utc),  # 8:55 AM Manila
        time_out=None,
        status=AttendanceStatus.late,
    )
    db = _mock_performance_db(
        employees=[employee],
        assignment_rows=[(assignment, shift)],
        records=[record],
        policy=_policy(absent_threshold_minutes=120, on_time_grace_minutes=10),
    )
    now = datetime(2026, 8, 28, 10, 0, tzinfo=ZoneInfo("Asia/Manila"))

    with (
        patch("app.api.owner_performance.business_now", return_value=now),
        patch("app.api.owner_performance.business_today", return_value=day),
    ):
        result = get_owner_performance(db=db, user=user, days=30)

    assert result.summary.late_clock_ins == 1
    assert result.summary.absent_shifts == 0
    assert result.summary.on_time_clock_ins == 0
    assert result.summary.assigned_shifts == 1


def test_worked_minutes_absent_record_still_counts_as_absent():
    """Existing status=absent after Time In is unchanged by the no-show gate."""
    business_id = uuid4()
    user = SimpleNamespace(business_id=business_id, role="owner")
    employee = _employee(business_id)
    day = date(2026, 8, 28)
    shift = _shift(business_id, start=time(8, 30), end=time(12, 30))
    assignment = _assignment(employee.id, day, shift)
    record = _record(
        business_id,
        assignment.id,
        time_in=datetime(2026, 8, 28, 8, 30),
        time_out=datetime(2026, 8, 28, 8, 40),
        status=AttendanceStatus.absent,
    )
    db = _mock_performance_db(
        employees=[employee],
        assignment_rows=[(assignment, shift)],
        records=[record],
    )
    now = datetime(2026, 8, 28, 10, 0, tzinfo=ZoneInfo("Asia/Manila"))

    with (
        patch("app.api.owner_performance.business_now", return_value=now),
        patch("app.api.owner_performance.business_today", return_value=day),
    ):
        result = get_owner_performance(db=db, user=user, days=30)

    assert result.summary.absent_shifts == 1
    assert result.summary.assigned_shifts == 1
    assert result.summary.late_clock_ins == 0


def test_two_shifts_same_day_are_evaluated_independently():
    """Morning Time In must not make an unreached afternoon shift Absent."""
    business_id = uuid4()
    user = SimpleNamespace(business_id=business_id, role="owner")
    employee = _employee(business_id)
    day = date(2026, 8, 28)
    morning = _shift(business_id, start=time(8, 30), end=time(12, 30), name="morning")
    afternoon = _shift(business_id, start=time(13, 0), end=time(15, 0), name="afternoon")
    morning_asg = _assignment(employee.id, day, morning)
    afternoon_asg = _assignment(employee.id, day, afternoon)
    morning_record = _record(
        business_id,
        morning_asg.id,
        time_in=datetime(2026, 8, 28, 0, 55, tzinfo=timezone.utc),
        status=AttendanceStatus.late,
    )
    db = _mock_performance_db(
        employees=[employee],
        assignment_rows=[(morning_asg, morning), (afternoon_asg, afternoon)],
        records=[morning_record],
        policy=_policy(absent_threshold_minutes=120),
    )
    now = datetime(2026, 8, 28, 10, 0, tzinfo=ZoneInfo("Asia/Manila"))

    with (
        patch("app.api.owner_performance.business_now", return_value=now),
        patch("app.api.owner_performance.business_today", return_value=day),
    ):
        result = get_owner_performance(db=db, user=user, days=30)

    assert result.summary.late_clock_ins == 1
    assert result.summary.absent_shifts == 0
    assert result.summary.assigned_shifts == 1


def test_two_shifts_same_day_afternoon_absent_after_cutoff():
    """After afternoon cutoff, morning stays Late and afternoon becomes Absent."""
    business_id = uuid4()
    user = SimpleNamespace(business_id=business_id, role="owner")
    employee = _employee(business_id)
    day = date(2026, 8, 28)
    morning = _shift(business_id, start=time(8, 30), end=time(12, 30), name="morning")
    afternoon = _shift(business_id, start=time(13, 0), end=time(15, 0), name="afternoon")
    morning_asg = _assignment(employee.id, day, morning)
    afternoon_asg = _assignment(employee.id, day, afternoon)
    morning_record = _record(
        business_id,
        morning_asg.id,
        time_in=datetime(2026, 8, 28, 0, 55, tzinfo=timezone.utc),
        time_out=datetime(2026, 8, 28, 4, 30, tzinfo=timezone.utc),
        status=AttendanceStatus.late,
    )
    db = _mock_performance_db(
        employees=[employee],
        assignment_rows=[(morning_asg, morning), (afternoon_asg, afternoon)],
        records=[morning_record],
        policy=_policy(absent_threshold_minutes=120),
    )
    now = datetime(2026, 8, 28, 15, 1, tzinfo=ZoneInfo("Asia/Manila"))

    with (
        patch("app.api.owner_performance.business_now", return_value=now),
        patch("app.api.owner_performance.business_today", return_value=day),
    ):
        result = get_owner_performance(db=db, user=user, days=30)

    assert result.summary.late_clock_ins == 1
    assert result.summary.absent_shifts == 1
    assert result.summary.assigned_shifts == 2


def test_noshow_cutoff_uses_business_local_now_not_utc_wall_clock():
    """02:10 UTC is 10:10 AM Manila; a 9:00 start + 60 min cutoff is due."""
    business_id = uuid4()
    user = SimpleNamespace(business_id=business_id, role="owner")
    employee = _employee(business_id)
    day = date(2026, 8, 28)
    shift = _shift(business_id, start=time(9, 0), end=time(17, 0))
    assignment = _assignment(employee.id, day, shift)
    db = _mock_performance_db(
        employees=[employee],
        assignment_rows=[(assignment, shift)],
        records=[],
        policy=_policy(timezone="Asia/Manila", absent_threshold_minutes=60),
    )
    # 10:10 AM Manila == 02:10 UTC. Naive UTC 02:10 would miss the 10:00 cutoff.
    now = datetime(2026, 8, 28, 10, 10, tzinfo=ZoneInfo("Asia/Manila"))

    with (
        patch("app.api.owner_performance.business_now", return_value=now),
        patch("app.api.owner_performance.business_today", return_value=day),
    ):
        result = get_owner_performance(db=db, user=user, days=30)

    assert result.summary.absent_shifts == 1
    assert result.summary.assigned_shifts == 1
