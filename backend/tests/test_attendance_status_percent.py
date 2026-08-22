"""Scheduled-relative attendance status (percent of shift duration)."""

from datetime import date, datetime, time, timezone
from unittest.mock import MagicMock, patch
from uuid import uuid4
from zoneinfo import ZoneInfo

from app.models.attendance import AttendanceRecord
from app.models.attendance_correction import AttendanceCorrectionRequest
from app.models.attendance_policy import BusinessAttendancePolicy
from app.models.business import Business
from app.models.employee import Employee
from app.models.enums import AttendanceCorrectionStatus, AttendanceStatus
from app.models.scheduling import Shift, ShiftAssignment
from app.models.user import User
from app.services.attendance_correction import (
    _recompute_status,
    approve_correction,
    create_correction_request,
)
from app.services.attendance_status import (
    absent_worked_minutes_bar,
    resolve_closed_attendance_status,
    scheduled_shift_minutes,
)
from app.services.missing_clock_out import complete_incomplete_attendance


TZ = ZoneInfo("Asia/Manila")


def _policy(**overrides) -> BusinessAttendancePolicy:
    values = {
        "business_id": uuid4(),
        "on_time_grace_minutes": 10,
        "half_day_threshold_minutes": 120,
        "absent_threshold_minutes": 240,
        "absent_threshold_percent": 25,
        "half_day_threshold_percent": 50,
    }
    values.update(overrides)
    return BusinessAttendancePolicy(**values)


def _short_shift(employee_id, business_id, work_date=date(2026, 8, 3)):
    shift_id = uuid4()
    assignment = ShiftAssignment(
        id=uuid4(),
        shift_id=shift_id,
        employee_id=employee_id,
        work_date=work_date,
        is_rest_day_work=False,
    )
    shift = Shift(
        id=shift_id,
        business_id=business_id,
        name="Short",
        start_time=time(13, 10),
        end_time=time(14, 0),
    )
    return assignment, shift


def _long_shift(employee_id, business_id, work_date=date(2026, 8, 3)):
    shift_id = uuid4()
    assignment = ShiftAssignment(
        id=uuid4(),
        shift_id=shift_id,
        employee_id=employee_id,
        work_date=work_date,
        is_rest_day_work=False,
    )
    shift = Shift(
        id=shift_id,
        business_id=business_id,
        name="Day",
        start_time=time(9, 0),
        end_time=time(17, 0),
    )
    return assignment, shift


def test_scheduled_shift_minutes_short_shift():
    assignment, shift = _short_shift(uuid4(), uuid4())
    assert scheduled_shift_minutes(
        work_date=assignment.work_date, shift=shift
    ) == 50


def test_absent_bar_is_percent_of_scheduled():
    policy = _policy(absent_threshold_percent=25)
    # 25% of 50 minutes = 12.5
    assert absent_worked_minutes_bar(scheduled_minutes=50, policy=policy) == 12.5
    # 25% of 480 minutes = 120
    assert absent_worked_minutes_bar(scheduled_minutes=480, policy=policy) == 120.0


def test_short_shift_worked_completely_is_complete():
    """50-minute shift fully worked must not be absent under fixed 120-min rule."""
    employee_id = uuid4()
    business_id = uuid4()
    assignment, shift = _short_shift(employee_id, business_id)
    policy = _policy(business_id=business_id)
    time_in = datetime(2026, 8, 3, 13, 10, tzinfo=TZ).astimezone(timezone.utc)
    time_out = datetime(2026, 8, 3, 14, 0, tzinfo=TZ).astimezone(timezone.utc)

    status = resolve_closed_attendance_status(
        time_in=time_in,
        time_out=time_out,
        assignment=assignment,
        shift=shift,
        policy=policy,
        business_timezone="Asia/Manila",
    )
    assert status == AttendanceStatus.complete


def test_short_shift_partial_below_absent_percent_is_absent():
    employee_id = uuid4()
    business_id = uuid4()
    assignment, shift = _short_shift(employee_id, business_id)
    policy = _policy(business_id=business_id, absent_threshold_percent=25)
    # 10 of 50 minutes = 20% < 25% → absent
    time_in = datetime(2026, 8, 3, 13, 10, tzinfo=TZ).astimezone(timezone.utc)
    time_out = datetime(2026, 8, 3, 13, 20, tzinfo=TZ).astimezone(timezone.utc)

    status = resolve_closed_attendance_status(
        time_in=time_in,
        time_out=time_out,
        assignment=assignment,
        shift=shift,
        policy=policy,
        business_timezone="Asia/Manila",
    )
    assert status == AttendanceStatus.absent


def test_short_shift_partial_above_absent_percent_is_complete():
    employee_id = uuid4()
    business_id = uuid4()
    assignment, shift = _short_shift(employee_id, business_id)
    policy = _policy(business_id=business_id, absent_threshold_percent=25)
    # 20 of 50 minutes = 40% >= 25% → complete (not late; on-time in)
    time_in = datetime(2026, 8, 3, 13, 10, tzinfo=TZ).astimezone(timezone.utc)
    time_out = datetime(2026, 8, 3, 13, 30, tzinfo=TZ).astimezone(timezone.utc)

    status = resolve_closed_attendance_status(
        time_in=time_in,
        time_out=time_out,
        assignment=assignment,
        shift=shift,
        policy=policy,
        business_timezone="Asia/Manila",
    )
    assert status == AttendanceStatus.complete


def test_eight_hour_shift_still_behaves():
    employee_id = uuid4()
    business_id = uuid4()
    assignment, shift = _long_shift(employee_id, business_id)
    policy = _policy(business_id=business_id, absent_threshold_percent=25)
    # Full day → complete
    time_in = datetime(2026, 8, 3, 9, 0, tzinfo=TZ).astimezone(timezone.utc)
    time_out = datetime(2026, 8, 3, 17, 0, tzinfo=TZ).astimezone(timezone.utc)
    assert (
        resolve_closed_attendance_status(
            time_in=time_in,
            time_out=time_out,
            assignment=assignment,
            shift=shift,
            policy=policy,
            business_timezone="Asia/Manila",
        )
        == AttendanceStatus.complete
    )
    # Under 25% of 480 (= 120 min) → absent
    short_out = datetime(2026, 8, 3, 10, 0, tzinfo=TZ).astimezone(timezone.utc)
    assert (
        resolve_closed_attendance_status(
            time_in=time_in,
            time_out=short_out,
            assignment=assignment,
            shift=shift,
            policy=policy,
            business_timezone="Asia/Manila",
        )
        == AttendanceStatus.absent
    )
    # Late arrival but full worked day → late
    late_in = datetime(2026, 8, 3, 9, 30, tzinfo=TZ).astimezone(timezone.utc)
    assert (
        resolve_closed_attendance_status(
            time_in=late_in,
            time_out=time_out,
            assignment=assignment,
            shift=shift,
            policy=policy,
            business_timezone="Asia/Manila",
        )
        == AttendanceStatus.late
    )


def test_recompute_status_uses_percent_for_short_shift():
    employee_id = uuid4()
    business_id = uuid4()
    assignment, shift = _short_shift(employee_id, business_id)
    policy = _policy(business_id=business_id)
    time_in = datetime(2026, 8, 3, 13, 10, tzinfo=TZ).astimezone(timezone.utc)
    time_out = datetime(2026, 8, 3, 14, 0, tzinfo=TZ).astimezone(timezone.utc)
    assert (
        _recompute_status(
            time_in=time_in,
            time_out=time_out,
            assignment=assignment,
            shift=shift,
            policy=policy,
            business_timezone="Asia/Manila",
        )
        == AttendanceStatus.complete
    )


def test_correction_approve_recomputes_short_shift_complete():
    business_id = uuid4()
    employee_id = uuid4()
    business = Business(id=business_id, timezone="Asia/Manila")
    employee = Employee(
        id=employee_id,
        business_id=business_id,
        full_name="Short Shift Worker",
        is_active=True,
    )
    assignment, shift = _short_shift(employee_id, business_id)
    official_in = datetime(2026, 8, 3, 5, 10, tzinfo=timezone.utc)  # 1:10 PM PH
    record = AttendanceRecord(
        id=uuid4(),
        business_id=business_id,
        employee_id=employee_id,
        shift_assignment_id=assignment.id,
        time_in=official_in,
        time_out=None,
        status=AttendanceStatus.incomplete,
    )
    request = AttendanceCorrectionRequest(
        id=uuid4(),
        business_id=business_id,
        employee_id=employee_id,
        shift_assignment_id=assignment.id,
        attendance_record_id=record.id,
        requested_time_in=official_in,
        requested_time_out=datetime(2026, 8, 3, 14, 0, tzinfo=TZ).astimezone(
            timezone.utc
        ),
        reason="Forgot to clock out after short shift",
        status=AttendanceCorrectionStatus.pending,
    )
    reviewer = User(id=uuid4())
    db = MagicMock()
    db.query.return_value.join.return_value.filter.return_value.first.return_value = (
        assignment,
        shift,
    )
    db.query.return_value.filter.return_value.order_by.return_value.first.return_value = (
        record
    )

    def get_side_effect(model, key):
        if model is AttendanceCorrectionRequest:
            return request
        if model is Employee:
            return employee
        if model is BusinessAttendancePolicy:
            return _policy(business_id=business_id)
        return None

    db.get.side_effect = get_side_effect

    result = approve_correction(
        db,
        request_id=request.id,
        reviewer=reviewer,
        business=business,
    )
    assert result["status"] == "approved"
    assert record.status == AttendanceStatus.complete
    assert record.time_out is not None


def test_owner_complete_attendance_recomputes_short_shift():
    business_id = uuid4()
    employee_id = uuid4()
    business = Business(id=business_id, timezone="Asia/Manila")
    assignment, shift = _short_shift(employee_id, business_id)
    record = AttendanceRecord(
        id=uuid4(),
        business_id=business_id,
        employee_id=employee_id,
        shift_assignment_id=assignment.id,
        time_in=datetime(2026, 8, 3, 5, 10, tzinfo=timezone.utc),
        time_out=None,
        status=AttendanceStatus.incomplete,
    )
    reviewer = User(id=uuid4(), business_id=business_id)
    db = MagicMock()
    db.query.return_value.filter.return_value.first.return_value = record
    db.query.return_value.join.return_value.filter.return_value.first.return_value = (
        assignment,
        shift,
    )

    def get_side_effect(model, key):
        if model is BusinessAttendancePolicy:
            return _policy(business_id=business_id)
        if model is Employee:
            return Employee(
                id=employee_id,
                business_id=business_id,
                full_name="Worker",
                is_active=True,
            )
        return None

    db.get.side_effect = get_side_effect

    with patch("app.services.missing_clock_out.create_log"):
        updated = complete_incomplete_attendance(
            db,
            record_id=record.id,
            reviewer=reviewer,
            business=business,
            time_out=datetime(2026, 8, 3, 14, 0, tzinfo=TZ).astimezone(timezone.utc),
            reason="Completed short shift",
        )

    assert updated.status == AttendanceStatus.complete


def test_correction_create_short_shift_clock_out_only():
    business_id = uuid4()
    employee_id = uuid4()
    business = Business(id=business_id, timezone="Asia/Manila")
    employee = Employee(
        id=employee_id,
        business_id=business_id,
        full_name="Worker",
        is_active=True,
    )
    assignment, shift = _short_shift(employee_id, business_id)
    record = AttendanceRecord(
        id=uuid4(),
        business_id=business_id,
        employee_id=employee_id,
        shift_assignment_id=assignment.id,
        time_in=datetime(2026, 8, 3, 5, 10, tzinfo=timezone.utc),
        time_out=None,
        status=AttendanceStatus.incomplete,
    )
    db = MagicMock()
    db.query.return_value.join.return_value.filter.return_value.first.return_value = (
        assignment,
        shift,
    )
    db.query.return_value.filter.return_value.order_by.return_value.first.return_value = (
        record
    )
    db.query.return_value.filter.return_value.first.return_value = None

    result = create_correction_request(
        db,
        employee=employee,
        business=business,
        shift_assignment_id=assignment.id,
        requested_time_in=None,
        requested_time_out=datetime(2026, 8, 3, 14, 0, tzinfo=TZ),
        reason="Forgot clock-out on short shift",
    )
    assert result["status"] == "pending"
    assert db.add.called
