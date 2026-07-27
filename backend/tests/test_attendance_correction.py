"""Unit tests for missed attendance correction workflow."""

from datetime import date, datetime, time, timezone
from unittest.mock import MagicMock
from uuid import uuid4
from zoneinfo import ZoneInfo

import pytest
from fastapi import HTTPException

from app.models.attendance import AttendanceRecord
from app.models.attendance_correction import AttendanceCorrectionRequest
from app.models.attendance_policy import BusinessAttendancePolicy
from app.models.business import Business
from app.models.employee import Employee
from app.models.enums import AttendanceCorrectionStatus, AttendanceStatus
from app.models.scheduling import Shift, ShiftAssignment
from app.models.user import User
from app.services.attendance_correction import (
    approve_correction,
    create_correction_request,
    reject_correction,
    _recompute_status,
)


TZ = ZoneInfo("Asia/Manila")


def _employee_business():
    business_id = uuid4()
    employee_id = uuid4()
    business = Business(id=business_id, timezone="Asia/Manila")
    employee = Employee(
        id=employee_id,
        business_id=business_id,
        full_name="Juan Dela Cruz",
        is_active=True,
    )
    return business, employee


def _assignment(employee_id, business_id, work_date=date(2026, 7, 18)):
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
        name="Morning",
        start_time=time(9, 0),
        end_time=time(17, 0),
    )
    return assignment, shift


def test_recompute_status_late_then_complete():
    policy = BusinessAttendancePolicy(
        business_id=uuid4(),
        on_time_grace_minutes=10,
        half_day_threshold_minutes=240,
        absent_threshold_minutes=120,
    )
    assignment, shift = _assignment(uuid4(), uuid4())
    time_in = datetime(2026, 7, 18, 9, 20, tzinfo=TZ).astimezone(timezone.utc)
    time_out = datetime(2026, 7, 18, 17, 0, tzinfo=TZ).astimezone(timezone.utc)
    assert (
        _recompute_status(
            time_in=time_in,
            time_out=time_out,
            assignment=assignment,
            shift=shift,
            policy=policy,
            business_timezone="Asia/Manila",
        )
        == AttendanceStatus.late
    )


def test_create_rejects_when_both_punches_exist():
    business, employee = _employee_business()
    assignment, shift = _assignment(employee.id, business.id)
    record = AttendanceRecord(
        id=uuid4(),
        business_id=business.id,
        employee_id=employee.id,
        shift_assignment_id=assignment.id,
        time_in=datetime(2026, 7, 18, 1, 0, tzinfo=timezone.utc),
        time_out=datetime(2026, 7, 18, 9, 0, tzinfo=timezone.utc),
        status=AttendanceStatus.complete,
    )
    db = MagicMock()
    db.query.return_value.join.return_value.filter.return_value.first.return_value = (
        assignment,
        shift,
    )
    # Second query for attendance record
    def _query(model):
        q = MagicMock()
        if model is ShiftAssignment or model.__name__ == "ShiftAssignment":
            pass
        return q

    # Simpler: patch _load_assignment_bundle path via query chain for join
    db.query.return_value.join.return_value.filter.return_value.first.return_value = (
        assignment,
        shift,
    )
    db.query.return_value.filter.return_value.order_by.return_value.first.return_value = (
        record
    )
    db.query.return_value.filter.return_value.first.return_value = None

    with pytest.raises(HTTPException) as exc:
        create_correction_request(
            db,
            employee=employee,
            business=business,
            shift_assignment_id=assignment.id,
            requested_time_in=datetime(2026, 7, 18, 9, 0, tzinfo=TZ),
            requested_time_out=None,
            reason="Forgot to clock in",
        )
    assert exc.value.status_code == 400


def test_approve_creates_attendance_record():
    business, employee = _employee_business()
    assignment, shift = _assignment(employee.id, business.id)
    request = AttendanceCorrectionRequest(
        id=uuid4(),
        business_id=business.id,
        employee_id=employee.id,
        shift_assignment_id=assignment.id,
        attendance_record_id=None,
        requested_time_in=datetime(2026, 7, 18, 9, 5, tzinfo=TZ).astimezone(
            timezone.utc
        ),
        requested_time_out=datetime(2026, 7, 18, 17, 0, tzinfo=TZ).astimezone(
            timezone.utc
        ),
        reason="Forgot both punches",
        status=AttendanceCorrectionStatus.pending,
    )
    reviewer = User(id=uuid4())
    db = MagicMock()
    db.get.side_effect = lambda model, key: {
        (AttendanceCorrectionRequest, request.id): request,
        (Employee, employee.id): employee,
    }.get((model, key))
    db.query.return_value.join.return_value.filter.return_value.first.return_value = (
        assignment,
        shift,
    )
    db.query.return_value.filter.return_value.order_by.return_value.first.return_value = (
        None
    )
    db.get.side_effect = lambda model, key: {
        (AttendanceCorrectionRequest, request.id): request,
        (Employee, employee.id): employee,
        (BusinessAttendancePolicy, business.id): BusinessAttendancePolicy(
            business_id=business.id,
            on_time_grace_minutes=10,
            half_day_threshold_minutes=240,
            absent_threshold_minutes=120,
        ),
    }.get((model, key))

    # attendance policy via db.get(BusinessAttendancePolicy, ...)
    def get_side_effect(model, key):
        if model is AttendanceCorrectionRequest:
            return request
        if model is Employee:
            return employee
        if model is BusinessAttendancePolicy:
            return BusinessAttendancePolicy(
                business_id=business.id,
                on_time_grace_minutes=10,
                half_day_threshold_minutes=240,
                absent_threshold_minutes=120,
            )
        return None

    db.get.side_effect = get_side_effect

    result = approve_correction(
        db,
        request_id=request.id,
        reviewer=reviewer,
        business=business,
    )
    assert request.status == AttendanceCorrectionStatus.approved
    assert result["status"] == "approved"
    assert db.add.called
    assert db.commit.called


def test_reject_requires_pending():
    business, employee = _employee_business()
    request = AttendanceCorrectionRequest(
        id=uuid4(),
        business_id=business.id,
        employee_id=employee.id,
        shift_assignment_id=uuid4(),
        reason="Forgot",
        status=AttendanceCorrectionStatus.approved,
    )
    reviewer = User(id=uuid4())
    db = MagicMock()
    db.get.return_value = request
    with pytest.raises(HTTPException) as exc:
        reject_correction(
            db,
            request_id=request.id,
            reviewer=reviewer,
            business_id=business.id,
            review_note="Already reviewed",
        )
    assert exc.value.status_code == 400
