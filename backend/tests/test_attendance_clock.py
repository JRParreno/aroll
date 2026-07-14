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


@patch("app.services.attendance_clock._existing_assignment_record")
@patch("app.services.attendance_clock._attendance_policy")
@patch("app.services.attendance_clock._resolve_assignment")
@patch("app.services.attendance_clock._primary_location")
@patch("app.services.attendance_clock.business_today")
@patch("app.services.attendance_clock.business_now")
def test_clock_in_rejects_early_before_window(
    mock_business_now,
    mock_business_today,
    mock_primary_location,
    mock_resolve_assignment,
    mock_attendance_policy,
    mock_existing_record,
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
    assert "Clock-in opens" in exc.value.detail


@patch("app.services.attendance_clock._existing_assignment_record")
@patch("app.services.attendance_clock._resolve_assignment")
@patch("app.services.attendance_clock._primary_location")
@patch("app.services.attendance_clock.business_today")
def test_clock_in_rejects_completed_assignment(
    mock_business_today,
    mock_primary_location,
    mock_resolve_assignment,
    mock_existing_record,
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


@patch("app.services.attendance_clock._primary_location")
def test_clock_in_outside_geofence_returns_403(mock_primary_location):
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
