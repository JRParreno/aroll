import uuid
from datetime import date, datetime, time
from unittest.mock import MagicMock, patch
from zoneinfo import ZoneInfo

import pytest
from fastapi import HTTPException

from app.models.attendance import AttendanceRecord
from app.models.business import BusinessLocation
from app.models.enums import AttendanceStatus
from app.models.scheduling import Shift, ShiftAssignment
from app.services.attendance_clock import (
    GeofenceValidationError,
    _clock_in_status,
    clock_in_employee,
    pick_assignment_for_time_in,
)


def _sample_location(**overrides) -> BusinessLocation:
    values = {
        "business_id": uuid.uuid4(),
        "label": "Main Office",
        "address": "Test address",
        "latitude": 14.6760,
        "longitude": 121.0437,
        "geofence_radius_m": 100,
        "is_primary": True,
    }
    values.update(overrides)
    return BusinessLocation(**values)


def _sample_assignment_and_shift(
    *,
    employee_id: uuid.UUID,
    business_id: uuid.UUID,
    work_date: date,
) -> tuple[ShiftAssignment, Shift]:
    shift_id = uuid.uuid4()
    assignment = ShiftAssignment(
        id=uuid.uuid4(),
        shift_id=shift_id,
        employee_id=employee_id,
        work_date=work_date,
    )
    shift = Shift(
        id=shift_id,
        business_id=business_id,
        name="Morning",
        start_time=time(9, 0),
        end_time=time(17, 0),
    )
    return assignment, shift


def test_clock_in_status_on_time_within_grace():
    scheduled = datetime(2026, 7, 14, 9, 0)
    now_local = datetime(2026, 7, 14, 9, 8)
    assert (
        _clock_in_status(
            now_local=now_local,
            scheduled_start=scheduled,
            grace_minutes=10,
        )
        == AttendanceStatus.in_progress
    )


def test_clock_in_status_late_after_grace():
    scheduled = datetime(2026, 7, 14, 9, 0)
    now_local = datetime(2026, 7, 14, 9, 11)
    assert (
        _clock_in_status(
            now_local=now_local,
            scheduled_start=scheduled,
            grace_minutes=10,
        )
        == AttendanceStatus.late
    )


@patch("app.services.missing_clock_out.ensure_incomplete_for_employee")
@patch("app.services.leave_requests.raise_if_on_approved_leave")
@patch("app.services.attendance_clock._existing_assignment_record")
@patch("app.services.attendance_clock._attendance_policy")
@patch("app.services.attendance_clock._resolve_assignment")
@patch("app.services.attendance_clock._active_record")
@patch("app.services.attendance_clock._primary_location")
@patch("app.services.attendance_clock.business_today")
@patch("app.services.attendance_clock.business_now")
def test_clock_in_rejects_early_before_window(
    mock_business_now,
    mock_business_today,
    mock_primary_location,
    mock_active_record,
    mock_resolve_assignment,
    mock_attendance_policy,
    mock_existing_record,
    _mock_leave,
    _mock_incomplete,
):
    db = MagicMock()
    business_id = uuid.uuid4()
    employee_id = uuid.uuid4()
    employee = MagicMock()
    employee.id = employee_id
    employee.business_id = business_id

    work_date = date(2026, 7, 14)
    assignment, shift = _sample_assignment_and_shift(
        employee_id=employee_id,
        business_id=business_id,
        work_date=work_date,
    )

    mock_business_today.return_value = work_date
    mock_business_now.return_value = datetime(
        2026, 7, 14, 8, 30, tzinfo=ZoneInfo("Asia/Manila")
    )
    mock_primary_location.return_value = _sample_location(business_id=business_id)
    mock_active_record.return_value = None
    mock_resolve_assignment.return_value = (assignment, shift)

    policy = MagicMock()
    policy.early_clock_in_minutes = 15
    policy.on_time_grace_minutes = 10
    mock_attendance_policy.return_value = policy
    mock_existing_record.return_value = None

    with pytest.raises(HTTPException) as exc:
        clock_in_employee(
            db,
            employee,
            latitude=14.6760,
            longitude=121.0437,
            business_timezone="Asia/Manila",
        )

    assert exc.value.status_code == 400
    assert "Time In opens" in exc.value.detail


@patch("app.services.missing_clock_out.ensure_incomplete_for_employee")
@patch("app.services.leave_requests.raise_if_on_approved_leave")
@patch("app.services.attendance_clock._existing_assignment_record")
@patch("app.services.attendance_clock._resolve_assignment")
@patch("app.services.attendance_clock._active_record")
@patch("app.services.attendance_clock._primary_location")
@patch("app.services.attendance_clock.business_today")
def test_clock_in_rejects_completed_assignment(
    mock_business_today,
    mock_primary_location,
    mock_active_record,
    mock_resolve_assignment,
    mock_existing_record,
    _mock_leave,
    _mock_incomplete,
):
    db = MagicMock()
    business_id = uuid.uuid4()
    employee_id = uuid.uuid4()
    employee = MagicMock()
    employee.id = employee_id
    employee.business_id = business_id

    work_date = date(2026, 7, 14)
    assignment, shift = _sample_assignment_and_shift(
        employee_id=employee_id,
        business_id=business_id,
        work_date=work_date,
    )

    mock_business_today.return_value = work_date
    mock_primary_location.return_value = _sample_location(business_id=business_id)
    mock_active_record.return_value = None
    mock_resolve_assignment.return_value = (assignment, shift)
    mock_existing_record.return_value = AttendanceRecord(
        business_id=business_id,
        employee_id=employee_id,
        shift_assignment_id=assignment.id,
        status=AttendanceStatus.complete,
        time_in=datetime(2026, 7, 14, 9, 0, tzinfo=ZoneInfo("UTC")),
        time_out=datetime(2026, 7, 14, 17, 0, tzinfo=ZoneInfo("UTC")),
    )

    with pytest.raises(HTTPException) as exc:
        clock_in_employee(
            db,
            employee,
            latitude=14.6760,
            longitude=121.0437,
            business_timezone="Asia/Manila",
        )

    assert exc.value.status_code == 400
    assert "already complete" in exc.value.detail


@patch("app.services.missing_clock_out.ensure_incomplete_for_employee")
@patch("app.services.leave_requests.raise_if_on_approved_leave")
@patch("app.services.attendance_clock._primary_location")
def test_clock_in_outside_geofence_returns_403(
    mock_primary_location,
    _mock_leave,
    _mock_incomplete,
):
    db = MagicMock()
    employee = MagicMock()
    employee.id = uuid.uuid4()
    employee.business_id = uuid.uuid4()
    mock_primary_location.return_value = _sample_location(
        business_id=employee.business_id
    )

    with pytest.raises(GeofenceValidationError) as exc:
        clock_in_employee(
            db,
            employee,
            latitude=15.0,
            longitude=122.0,
            business_timezone="Asia/Manila",
        )

    assert exc.value.status_code == 403
    assert exc.value.detail["code"] == "outside_geofence"


def _split_day_assignments(
    *,
    employee_id: uuid.UUID,
    business_id: uuid.UUID,
    work_date: date,
) -> tuple[tuple[ShiftAssignment, Shift], tuple[ShiftAssignment, Shift]]:
    morning_shift = Shift(
        id=uuid.uuid4(),
        business_id=business_id,
        name="Morning",
        start_time=time(8, 30),
        end_time=time(12, 30),
    )
    evening_shift = Shift(
        id=uuid.uuid4(),
        business_id=business_id,
        name="Evening",
        start_time=time(18, 0),
        end_time=time(23, 0),
    )
    morning = ShiftAssignment(
        id=uuid.uuid4(),
        shift_id=morning_shift.id,
        employee_id=employee_id,
        work_date=work_date,
    )
    evening = ShiftAssignment(
        id=uuid.uuid4(),
        shift_id=evening_shift.id,
        employee_id=employee_id,
        work_date=work_date,
    )
    return (morning, morning_shift), (evening, evening_shift)


def test_pick_single_shift_during_window():
    work_date = date(2026, 8, 28)
    assignment, shift = _sample_assignment_and_shift(
        employee_id=uuid.uuid4(),
        business_id=uuid.uuid4(),
        work_date=work_date,
    )
    picked, picked_shift = pick_assignment_for_time_in(
        [(assignment, shift)],
        {},
        now_local=datetime(2026, 8, 28, 9, 0),
        early_clock_in_minutes=15,
    )
    assert picked.id == assignment.id
    assert picked_shift.id == shift.id


def test_pick_morning_then_evening_after_morning_complete():
    work_date = date(2026, 8, 28)
    (morning, morning_shift), (evening, evening_shift) = _split_day_assignments(
        employee_id=uuid.uuid4(),
        business_id=uuid.uuid4(),
        work_date=work_date,
    )
    rows = [(morning, morning_shift), (evening, evening_shift)]

    first, _ = pick_assignment_for_time_in(
        rows,
        {},
        now_local=datetime(2026, 8, 28, 8, 30),
        early_clock_in_minutes=15,
    )
    assert first.id == morning.id

    morning_record = AttendanceRecord(
        employee_id=morning.employee_id,
        shift_assignment_id=morning.id,
        status=AttendanceStatus.complete,
        time_in=datetime(2026, 8, 28, 8, 30, tzinfo=ZoneInfo("UTC")),
        time_out=datetime(2026, 8, 28, 12, 30, tzinfo=ZoneInfo("UTC")),
    )
    second, second_shift = pick_assignment_for_time_in(
        rows,
        {morning.id: morning_record},
        now_local=datetime(2026, 8, 28, 18, 0),
        early_clock_in_minutes=15,
        preferred_assignment_id=morning.id,
    )
    assert second.id == evening.id
    assert second_shift.name == "Evening"


def test_pick_rejects_duplicate_for_same_shift():
    work_date = date(2026, 8, 28)
    assignment, shift = _sample_assignment_and_shift(
        employee_id=uuid.uuid4(),
        business_id=uuid.uuid4(),
        work_date=work_date,
    )
    record = AttendanceRecord(
        employee_id=assignment.employee_id,
        shift_assignment_id=assignment.id,
        status=AttendanceStatus.complete,
        time_in=datetime(2026, 8, 28, 9, 0, tzinfo=ZoneInfo("UTC")),
        time_out=datetime(2026, 8, 28, 17, 0, tzinfo=ZoneInfo("UTC")),
    )
    with pytest.raises(HTTPException) as exc:
        pick_assignment_for_time_in(
            [(assignment, shift)],
            {assignment.id: record},
            now_local=datetime(2026, 8, 28, 10, 0),
            early_clock_in_minutes=15,
        )
    assert "already complete" in exc.value.detail


def test_pick_blocks_time_in_before_evening_window():
    work_date = date(2026, 8, 28)
    (morning, morning_shift), (evening, evening_shift) = _split_day_assignments(
        employee_id=uuid.uuid4(),
        business_id=uuid.uuid4(),
        work_date=work_date,
    )
    morning_record = AttendanceRecord(
        employee_id=morning.employee_id,
        shift_assignment_id=morning.id,
        status=AttendanceStatus.complete,
        time_in=datetime(2026, 8, 28, 8, 30, tzinfo=ZoneInfo("UTC")),
        time_out=datetime(2026, 8, 28, 12, 30, tzinfo=ZoneInfo("UTC")),
    )
    with pytest.raises(HTTPException) as exc:
        pick_assignment_for_time_in(
            [(morning, morning_shift), (evening, evening_shift)],
            {morning.id: morning_record},
            now_local=datetime(2026, 8, 28, 14, 0),
            early_clock_in_minutes=15,
        )
    assert "Time In opens" in exc.value.detail


@patch("app.services.missing_clock_out.ensure_incomplete_for_employee")
@patch("app.services.leave_requests.raise_if_on_approved_leave")
@patch("app.services.attendance_clock._primary_location")
@patch("app.services.attendance_clock.business_today")
def test_clock_in_rejects_second_time_in_while_session_open(
    mock_business_today,
    mock_primary_location,
    _mock_leave,
    _mock_incomplete,
):
    db = MagicMock()
    employee = MagicMock()
    employee.id = uuid.uuid4()
    employee.business_id = uuid.uuid4()
    mock_business_today.return_value = date(2026, 8, 28)
    mock_primary_location.return_value = _sample_location(
        business_id=employee.business_id
    )
    open_record = AttendanceRecord(
        business_id=employee.business_id,
        employee_id=employee.id,
        status=AttendanceStatus.in_progress,
        time_in=datetime(2026, 8, 28, 0, 30, tzinfo=ZoneInfo("UTC")),
    )
    db.query.return_value.filter.return_value.order_by.return_value.first.return_value = (
        open_record
    )

    with pytest.raises(HTTPException) as exc:
        clock_in_employee(
            db,
            employee,
            latitude=14.6760,
            longitude=121.0437,
            business_timezone="Asia/Manila",
        )

    assert exc.value.status_code == 400
    assert "already timed in" in exc.value.detail


def test_pick_overnight_after_midnight_not_morning():
    employee_id = uuid.uuid4()
    business_id = uuid.uuid4()
    overnight_shift = Shift(
        id=uuid.uuid4(),
        business_id=business_id,
        name="Night",
        start_time=time(22, 0),
        end_time=time(6, 0),
    )
    morning_shift = Shift(
        id=uuid.uuid4(),
        business_id=business_id,
        name="Morning",
        start_time=time(8, 30),
        end_time=time(12, 30),
    )
    overnight = ShiftAssignment(
        id=uuid.uuid4(),
        shift_id=overnight_shift.id,
        employee_id=employee_id,
        work_date=date(2026, 8, 27),
    )
    morning = ShiftAssignment(
        id=uuid.uuid4(),
        shift_id=morning_shift.id,
        employee_id=employee_id,
        work_date=date(2026, 8, 28),
    )
    picked, picked_shift = pick_assignment_for_time_in(
        [(overnight, overnight_shift), (morning, morning_shift)],
        {},
        now_local=datetime(2026, 8, 28, 1, 0),
        early_clock_in_minutes=15,
    )
    assert picked.id == overnight.id
    assert picked_shift.name == "Night"

