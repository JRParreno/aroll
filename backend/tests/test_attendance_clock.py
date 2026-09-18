import uuid
from datetime import date, datetime, time, timezone
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
    is_open_for_time_in,
    pick_assignment_for_time_in,
    select_open_time_in_assignment,
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


def _evening_overnight(
    *,
    work_date: date = date(2026, 9, 16),
) -> tuple[ShiftAssignment, Shift]:
    shift = Shift(
        id=uuid.uuid4(),
        business_id=uuid.uuid4(),
        name="evening",
        start_time=time(22, 0),
        end_time=time(1, 0),
    )
    assignment = ShiftAssignment(
        id=uuid.uuid4(),
        shift_id=shift.id,
        employee_id=uuid.uuid4(),
        work_date=work_date,
    )
    return assignment, shift


def _early_morning(
    *,
    work_date: date = date(2026, 9, 17),
) -> tuple[ShiftAssignment, Shift]:
    shift = Shift(
        id=uuid.uuid4(),
        business_id=uuid.uuid4(),
        name="early morning",
        start_time=time(0, 15),
        end_time=time(8, 0),
    )
    assignment = ShiftAssignment(
        id=uuid.uuid4(),
        shift_id=shift.id,
        employee_id=uuid.uuid4(),
        work_date=work_date,
    )
    return assignment, shift


def _assert_pick_ok(assignment, shift, now_local):
    picked, _ = pick_assignment_for_time_in(
        [(assignment, shift)],
        {},
        now_local=now_local,
        early_clock_in_minutes=15,
    )
    assert picked.id == assignment.id
    assert is_open_for_time_in(assignment.work_date, shift, now_local)


def _assert_pick_ended(assignment, shift, now_local):
    with pytest.raises(HTTPException) as exc:
        pick_assignment_for_time_in(
            [(assignment, shift)],
            {},
            now_local=now_local,
            early_clock_in_minutes=15,
        )
    assert exc.value.status_code == 400
    assert "already ended" in exc.value.detail
    assert not is_open_for_time_in(assignment.work_date, shift, now_local)


def test_pick_early_morning_same_day_is_not_overnight():
    assignment, shift = _early_morning()
    assert shift.end_time > shift.start_time
    assert is_open_for_time_in(
        assignment.work_date, shift, datetime(2026, 9, 17, 0, 14)
    )
    assert not is_open_for_time_in(
        assignment.work_date, shift, datetime(2026, 9, 17, 8, 0)
    )


@pytest.mark.parametrize(
    "now_local",
    [
        datetime(2026, 9, 17, 0, 0),
        datetime(2026, 9, 17, 0, 14),
        datetime(2026, 9, 17, 0, 15),
        datetime(2026, 9, 17, 0, 16),
        datetime(2026, 9, 17, 0, 25),
        datetime(2026, 9, 17, 0, 41),
        datetime(2026, 9, 17, 7, 59),
    ],
)
def test_pick_early_morning_accepts_before_scheduled_end(now_local):
    assignment, shift = _early_morning()
    _assert_pick_ok(assignment, shift, now_local)


def test_pick_early_morning_status_uses_existing_grace():
    """00:15 is on-time; 00:16 stays on-time under the default 10-minute grace."""
    assert (
        _clock_in_status(
            now_local=datetime(2026, 9, 17, 0, 15),
            scheduled_start=datetime(2026, 9, 17, 0, 15),
            grace_minutes=10,
        )
        == AttendanceStatus.in_progress
    )
    assert (
        _clock_in_status(
            now_local=datetime(2026, 9, 17, 0, 16),
            scheduled_start=datetime(2026, 9, 17, 0, 15),
            grace_minutes=10,
        )
        == AttendanceStatus.in_progress
    )
    assert (
        _clock_in_status(
            now_local=datetime(2026, 9, 17, 0, 26),
            scheduled_start=datetime(2026, 9, 17, 0, 15),
            grace_minutes=10,
        )
        == AttendanceStatus.late
    )


def test_same_day_early_morning_shift_remains_time_in_available_before_end():
    assignment, shift = _early_morning()
    now_local = datetime(2026, 9, 17, 0, 41)
    assert is_open_for_time_in(assignment.work_date, shift, now_local)
    selected = select_open_time_in_assignment(
        [(assignment, shift)],
        {},
        now_local,
    )
    assert selected is not None
    assert selected[0].id == assignment.id
    _assert_pick_ok(assignment, shift, now_local)
    assert (
        _clock_in_status(
            now_local=now_local,
            scheduled_start=datetime(2026, 9, 17, 0, 15),
            grace_minutes=10,
        )
        == AttendanceStatus.late
    )


@pytest.mark.parametrize(
    "now_local",
    [
        datetime(2026, 9, 17, 8, 0),
        datetime(2026, 9, 17, 8, 1),
        datetime(2026, 9, 17, 12, 0),
        datetime(2026, 9, 17, 15, 14),
    ],
)
def test_pick_early_morning_rejects_at_or_after_scheduled_end(now_local):
    assignment, shift = _early_morning()
    _assert_pick_ended(assignment, shift, now_local)


def test_pick_early_morning_accepts_true_manila_0014():
    utc = datetime(2026, 9, 16, 16, 14, tzinfo=timezone.utc)
    manila = utc.astimezone(ZoneInfo("Asia/Manila")).replace(tzinfo=None)
    assignment, shift = _early_morning()
    _assert_pick_ok(assignment, shift, manila)


def test_pick_early_morning_rejects_pacific_1214_as_manila_afternoon():
    utc = datetime(2026, 9, 17, 7, 14, tzinfo=timezone.utc)
    manila = utc.astimezone(ZoneInfo("Asia/Manila")).replace(tzinfo=None)
    assert (manila.hour, manila.minute) == (15, 14)
    assignment, shift = _early_morning()
    _assert_pick_ended(assignment, shift, manila)


def test_pick_overnight_early_time_in_at_window_open():
    assignment, shift = _evening_overnight()
    _assert_pick_ok(assignment, shift, datetime(2026, 9, 16, 21, 45))


def test_pick_overnight_time_in_at_scheduled_start():
    assignment, shift = _evening_overnight()
    _assert_pick_ok(assignment, shift, datetime(2026, 9, 16, 22, 0))
    assert (
        _clock_in_status(
            now_local=datetime(2026, 9, 16, 22, 0),
            scheduled_start=datetime(2026, 9, 16, 22, 0),
            grace_minutes=10,
        )
        == AttendanceStatus.in_progress
    )


def test_pick_overnight_early_time_in_before_start():
    assignment, shift = _evening_overnight()
    picked, _ = pick_assignment_for_time_in(
        [(assignment, shift)],
        {},
        now_local=datetime(2026, 9, 16, 21, 58),
        early_clock_in_minutes=15,
    )
    assert picked.id == assignment.id
    assert (
        _clock_in_status(
            now_local=datetime(2026, 9, 16, 21, 58),
            scheduled_start=datetime(2026, 9, 16, 22, 0),
            grace_minutes=10,
        )
        == AttendanceStatus.in_progress
    )


def test_pick_overnight_valid_late_time_in_before_end():
    assignment, shift = _evening_overnight()
    picked, _ = pick_assignment_for_time_in(
        [(assignment, shift)],
        {},
        now_local=datetime(2026, 9, 16, 22, 15),
        early_clock_in_minutes=15,
    )
    assert picked.id == assignment.id
    assert (
        _clock_in_status(
            now_local=datetime(2026, 9, 16, 22, 15),
            scheduled_start=datetime(2026, 9, 16, 22, 0),
            grace_minutes=10,
        )
        == AttendanceStatus.late
    )


def test_pick_overnight_still_open_before_next_day_end():
    assignment, shift = _evening_overnight()
    _assert_pick_ok(assignment, shift, datetime(2026, 9, 17, 0, 59))


def test_pick_overnight_rejects_time_in_at_scheduled_end():
    assignment, shift = _evening_overnight()
    with pytest.raises(HTTPException) as exc:
        pick_assignment_for_time_in(
            [(assignment, shift)],
            {},
            now_local=datetime(2026, 9, 17, 1, 0),
            early_clock_in_minutes=15,
        )
    assert exc.value.status_code == 400
    assert "already ended" in exc.value.detail


def test_pick_overnight_rejects_time_in_after_scheduled_end():
    assignment, shift = _evening_overnight()
    with pytest.raises(HTTPException) as exc:
        pick_assignment_for_time_in(
            [(assignment, shift)],
            {},
            now_local=datetime(2026, 9, 17, 1, 1),
            early_clock_in_minutes=15,
        )
    assert "already ended" in exc.value.detail


def test_pick_overnight_rejects_manila_afternoon_after_ended_shift():
    assignment, shift = _evening_overnight()
    with pytest.raises(HTTPException) as exc:
        pick_assignment_for_time_in(
            [(assignment, shift)],
            {},
            now_local=datetime(2026, 9, 17, 12, 58),
            early_clock_in_minutes=15,
        )
    assert "already ended" in exc.value.detail


def test_pacific_device_clock_is_not_treated_as_manila_evening():
    """9:58 PM PDT is 12:58 PM Manila — not a 21:58 Time In for 22:00."""
    utc = datetime(2026, 9, 17, 4, 58, 14, tzinfo=timezone.utc)
    pacific = utc.astimezone(ZoneInfo("America/Los_Angeles"))
    manila = utc.astimezone(ZoneInfo("Asia/Manila")).replace(tzinfo=None)
    assert (pacific.year, pacific.month, pacific.day, pacific.hour, pacific.minute) == (
        2026,
        9,
        16,
        21,
        58,
    )
    assert (manila.year, manila.month, manila.day, manila.hour, manila.minute) == (
        2026,
        9,
        17,
        12,
        58,
    )
    assignment, shift = _evening_overnight()
    with pytest.raises(HTTPException) as exc:
        pick_assignment_for_time_in(
            [(assignment, shift)],
            {},
            now_local=manila,
            early_clock_in_minutes=15,
        )
    assert "already ended" in exc.value.detail


@patch("app.services.missing_clock_out.ensure_incomplete_for_employee")
@patch("app.services.leave_requests.raise_if_on_approved_leave")
@patch("app.services.attendance_clock._existing_assignment_record")
@patch("app.services.attendance_clock._attendance_policy")
@patch("app.services.attendance_clock._resolve_assignment")
@patch("app.services.attendance_clock._active_record")
@patch("app.services.attendance_clock._primary_location")
@patch("app.services.attendance_clock.business_today")
@patch("app.services.attendance_clock.business_now")
def test_clock_in_after_overnight_end_does_not_create_incomplete_record(
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
    employee = MagicMock()
    employee.id = uuid.uuid4()
    employee.business_id = uuid.uuid4()
    assignment, shift = _evening_overnight()
    shift.business_id = employee.business_id

    mock_business_today.return_value = date(2026, 9, 17)
    mock_business_now.return_value = datetime(
        2026, 9, 17, 12, 58, 14, tzinfo=ZoneInfo("Asia/Manila")
    )
    mock_primary_location.return_value = _sample_location(
        business_id=employee.business_id
    )
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
    assert "already ended" in exc.value.detail
    db.add.assert_not_called()
    db.commit.assert_not_called()


@pytest.mark.parametrize(
    "now_local, expected",
    [
        (datetime(2026, 9, 16, 21, 45), True),
        (datetime(2026, 9, 16, 22, 0), True),
        (datetime(2026, 9, 16, 22, 15), True),
        (datetime(2026, 9, 17, 0, 59), True),
        (datetime(2026, 9, 17, 1, 0), False),
        (datetime(2026, 9, 17, 1, 1), False),
    ],
)
def test_overnight_time_in_available_matches_scheduled_end(now_local, expected):
    assignment, shift = _evening_overnight()
    assert is_open_for_time_in(assignment.work_date, shift, now_local) is expected
    selected = select_open_time_in_assignment(
        [(assignment, shift)],
        {},
        now_local,
    )
    if expected:
        assert selected is not None
        assert selected[0].id == assignment.id
    else:
        assert selected is None


def test_true_manila_0041_is_open_pacific_0041_is_ended():
    """Real Manila 00:41 is still inside 00:15-08:00; Pacific 00:41 is 15:41 Manila."""
    assignment, shift = _early_morning()
    manila_utc = datetime(2026, 9, 16, 16, 41, tzinfo=timezone.utc)
    manila = manila_utc.astimezone(ZoneInfo("Asia/Manila")).replace(tzinfo=None)
    assert (manila.hour, manila.minute) == (0, 41)
    assert is_open_for_time_in(assignment.work_date, shift, manila)
    _assert_pick_ok(assignment, shift, manila)

    pacific_utc = datetime(2026, 9, 17, 7, 41, tzinfo=timezone.utc)
    pacific_wall = pacific_utc.astimezone(ZoneInfo("America/Los_Angeles"))
    manila_from_pacific = pacific_utc.astimezone(ZoneInfo("Asia/Manila")).replace(
        tzinfo=None
    )
    assert (pacific_wall.hour, pacific_wall.minute) == (0, 41)
    assert (manila_from_pacific.hour, manila_from_pacific.minute) == (15, 41)
    _assert_pick_ended(assignment, shift, manila_from_pacific)


@patch("app.services.missing_clock_out.ensure_incomplete_for_employee")
@patch("app.services.leave_requests.raise_if_on_approved_leave")
@patch("app.services.attendance_clock._existing_assignment_record")
@patch("app.services.attendance_clock._attendance_policy")
@patch("app.services.attendance_clock._list_assignment_candidates")
@patch("app.services.attendance_clock._records_by_assignment")
@patch("app.services.attendance_clock._active_record")
@patch("app.services.attendance_clock._primary_location")
@patch("app.services.attendance_clock.business_today")
@patch("app.services.attendance_clock.business_now")
def test_clock_in_early_morning_at_0041_does_not_treat_shift_as_ended(
    mock_business_now,
    mock_business_today,
    mock_primary_location,
    mock_active_record,
    mock_records,
    mock_candidates,
    mock_attendance_policy,
    mock_existing_record,
    _mock_leave,
    _mock_incomplete,
):
    db = MagicMock()
    employee = MagicMock()
    employee.id = uuid.uuid4()
    employee.business_id = uuid.uuid4()
    assignment, shift = _early_morning()
    shift.business_id = employee.business_id

    mock_business_today.return_value = date(2026, 9, 17)
    mock_business_now.return_value = datetime(
        2026, 9, 17, 0, 41, tzinfo=ZoneInfo("Asia/Manila")
    )
    mock_primary_location.return_value = _sample_location(
        business_id=employee.business_id
    )
    mock_active_record.return_value = None
    mock_candidates.return_value = [(assignment, shift)]
    mock_records.return_value = {}
    policy = MagicMock()
    policy.early_clock_in_minutes = 15
    policy.on_time_grace_minutes = 10
    mock_attendance_policy.return_value = policy
    mock_existing_record.return_value = None

    payload = clock_in_employee(
        db,
        employee,
        latitude=14.6760,
        longitude=121.0437,
        business_timezone="Asia/Manila",
    )

    assert "already ended" not in str(payload.get("message", "")).lower()
    assert payload["status"] == AttendanceStatus.late.value
    db.add.assert_called_once()
    db.commit.assert_called_once()


@patch("app.api.employee_mobile.ensure_incomplete_for_employee")
@patch("app.api.employee_mobile._records_by_assignment")
@patch("app.api.employee_mobile._list_assignment_candidates")
@patch("app.api.employee_mobile._active_record")
@patch("app.services.leave_requests.employee_on_approved_leave")
@pytest.mark.parametrize(
    "now_local, expected_available",
    [
        (datetime(2026, 9, 17, 0, 0), True),
        (datetime(2026, 9, 17, 0, 14), True),
        (datetime(2026, 9, 17, 0, 15), True),
        (datetime(2026, 9, 17, 0, 16), True),
        (datetime(2026, 9, 17, 0, 25), True),
        (datetime(2026, 9, 17, 0, 41), True),
        (datetime(2026, 9, 17, 7, 59), True),
        (datetime(2026, 9, 17, 8, 0), False),
        (datetime(2026, 9, 17, 8, 1), False),
    ],
)
def test_today_attendance_status_early_morning_time_in_available(
    mock_leave,
    mock_active_record,
    mock_candidates,
    mock_records,
    _mock_incomplete,
    now_local,
    expected_available,
):
    from app.api.employee_mobile import _today_attendance_status

    assignment, shift = _early_morning()
    employee = MagicMock()
    employee.id = assignment.employee_id
    employee.business_id = shift.business_id
    mock_leave.return_value = False
    mock_active_record.return_value = None
    mock_candidates.return_value = [(assignment, shift)]
    mock_records.return_value = {}

    payload = _today_attendance_status(
        MagicMock(),
        employee,
        date(2026, 9, 17),
        business_timezone="Asia/Manila",
        now_local=now_local,
    )
    assert payload["time_in_available"] is expected_available
    assert payload["timezone"] == "Asia/Manila"
    if expected_available:
        assert payload["status"] == "not_started"
        assert payload["shift_assignment_id"] == str(assignment.id)
    else:
        assert payload["time_in_available"] is False

