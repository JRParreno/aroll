"""Unit tests for missed attendance correction workflow."""

from datetime import date, datetime, time, timezone
from unittest.mock import MagicMock, patch
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
from app.services.payroll_engine import monetary_late_minutes


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


def test_create_allows_correction_when_both_punches_exist():
    """A closed shift can correct Time Out. Recorded Time In is kept."""
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
    db.query.return_value.filter.return_value.order_by.return_value.first.return_value = (
        record
    )
    db.query.return_value.filter.return_value.first.return_value = None

    result = create_correction_request(
        db,
        employee=employee,
        business=business,
        shift_assignment_id=assignment.id,
        requested_time_in=datetime(2026, 7, 18, 9, 0, tzinfo=TZ),
        requested_time_out=datetime(2026, 7, 18, 17, 0, tzinfo=TZ),
        reason="Wrong recorded times",
    )
    assert result["status"] == "pending"
    added = db.add.call_args[0][0]
    assert added.requested_time_in == record.time_in
    assert db.commit.called


def test_create_requires_both_corrected_times():
    business, employee = _employee_business()
    assignment, shift = _assignment(employee.id, business.id)
    db = MagicMock()
    db.query.return_value.join.return_value.filter.return_value.first.return_value = (
        assignment,
        shift,
    )
    db.query.return_value.filter.return_value.order_by.return_value.first.return_value = (
        None
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
            reason="Forgot to time in",
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

    with patch(
        "app.services.payroll_snapshot.find_finalized_run_for_period",
        return_value=None,
    ), patch(
        "app.services.ot_approval.sync_ot_approval_after_close",
    ):
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


def test_incomplete_allows_clock_out_only_correction():
    """Incomplete attendance: employee may submit clock-out (+ reason) only."""
    business, employee = _employee_business()
    assignment, shift = _assignment(employee.id, business.id)
    official_in = datetime(2026, 7, 18, 1, 0, tzinfo=timezone.utc)
    record = AttendanceRecord(
        id=uuid4(),
        business_id=business.id,
        employee_id=employee.id,
        shift_assignment_id=assignment.id,
        time_in=official_in,
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
        requested_time_out=datetime(2026, 7, 18, 17, 0, tzinfo=TZ),
        reason="Forgot to time out after my shift",
    )
    assert result["status"] == "pending"
    added = db.add.call_args[0][0]
    assert added.requested_time_in == official_in
    assert added.requested_time_out is not None
    assert db.commit.called


def test_incomplete_rejects_changed_clock_in():
    """Official clock-in cannot be modified via employee incomplete correction."""
    business, employee = _employee_business()
    assignment, shift = _assignment(employee.id, business.id)
    official_in = datetime(2026, 7, 18, 1, 0, tzinfo=timezone.utc)
    record = AttendanceRecord(
        id=uuid4(),
        business_id=business.id,
        employee_id=employee.id,
        shift_assignment_id=assignment.id,
        time_in=official_in,
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

    with pytest.raises(HTTPException) as exc:
        create_correction_request(
            db,
            employee=employee,
            business=business,
            shift_assignment_id=assignment.id,
            requested_time_in=datetime(2026, 7, 18, 10, 0, tzinfo=TZ),
            requested_time_out=datetime(2026, 7, 18, 17, 0, tzinfo=TZ),
            reason="Trying to change clock-in",
        )
    assert exc.value.status_code == 400
    assert "Time In cannot be changed" in str(exc.value.detail)


def test_approve_incomplete_keeps_official_clock_in():
    business, employee = _employee_business()
    assignment, shift = _assignment(employee.id, business.id)
    official_in = datetime(2026, 7, 18, 1, 5, tzinfo=timezone.utc)
    record = AttendanceRecord(
        id=uuid4(),
        business_id=business.id,
        employee_id=employee.id,
        shift_assignment_id=assignment.id,
        time_in=official_in,
        time_out=None,
        status=AttendanceStatus.incomplete,
    )
    request = AttendanceCorrectionRequest(
        id=uuid4(),
        business_id=business.id,
        employee_id=employee.id,
        shift_assignment_id=assignment.id,
        attendance_record_id=record.id,
        requested_time_in=datetime(2026, 7, 18, 10, 0, tzinfo=TZ).astimezone(
            timezone.utc
        ),
        requested_time_out=datetime(2026, 7, 18, 17, 0, tzinfo=TZ).astimezone(
            timezone.utc
        ),
        reason="Forgot to time out",
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
            return BusinessAttendancePolicy(
                business_id=business.id,
                on_time_grace_minutes=10,
                half_day_threshold_minutes=240,
                absent_threshold_minutes=120,
            )
        return None

    db.get.side_effect = get_side_effect

    with patch(
        "app.services.payroll_snapshot.find_finalized_run_for_period",
        return_value=None,
    ), patch(
        "app.services.ot_approval.sync_ot_approval_after_close",
    ):
        result = approve_correction(
            db,
            request_id=request.id,
            reviewer=reviewer,
            business=business,
        )
    assert result["status"] == "approved"
    assert record.time_in == official_in
    assert record.time_out is not None
    assert record.status != AttendanceStatus.incomplete
    assert db.commit.called


def _wire_db(db, assignment, shift, record):
    db.query.return_value.join.return_value.filter.return_value.first.return_value = (
        assignment,
        shift,
    )
    db.query.return_value.filter.return_value.order_by.return_value.first.return_value = (
        record
    )
    db.query.return_value.filter.return_value.first.return_value = None


def test_closed_attendance_rejects_changed_time_in():
    """A modified API request cannot replace a recorded Time In."""
    business, employee = _employee_business()
    assignment, shift = _assignment(employee.id, business.id, date(2026, 10, 21))
    shift.start_time = time(8, 0)
    shift.end_time = time(12, 0)
    official_in = datetime(2026, 10, 21, 8, 10, 6, tzinfo=TZ).astimezone(timezone.utc)
    record = AttendanceRecord(
        id=uuid4(),
        business_id=business.id,
        employee_id=employee.id,
        shift_assignment_id=assignment.id,
        time_in=official_in,
        time_out=datetime(2026, 10, 21, 12, 0, tzinfo=TZ).astimezone(timezone.utc),
        status=AttendanceStatus.late,
    )
    db = MagicMock()
    _wire_db(db, assignment, shift, record)

    with pytest.raises(HTTPException) as exc:
        create_correction_request(
            db,
            employee=employee,
            business=business,
            shift_assignment_id=assignment.id,
            requested_time_in=datetime(2026, 10, 21, 8, 11, tzinfo=TZ),
            requested_time_out=datetime(2026, 10, 21, 12, 4, tzinfo=TZ),
            reason="Trying to change the recorded clock-in",
        )
    assert exc.value.status_code == 400
    assert "Time In cannot be changed" in str(exc.value.detail)
    assert db.commit.called is False


def test_closed_attendance_accepts_unchanged_time_in_and_new_time_out():
    business, employee = _employee_business()
    assignment, shift = _assignment(employee.id, business.id, date(2026, 10, 21))
    shift.start_time = time(8, 0)
    shift.end_time = time(12, 0)
    official_in = datetime(2026, 10, 21, 8, 10, 6, tzinfo=TZ).astimezone(timezone.utc)
    record = AttendanceRecord(
        id=uuid4(),
        business_id=business.id,
        employee_id=employee.id,
        shift_assignment_id=assignment.id,
        time_in=official_in,
        time_out=datetime(2026, 10, 21, 12, 0, tzinfo=TZ).astimezone(timezone.utc),
        status=AttendanceStatus.late,
    )
    db = MagicMock()
    _wire_db(db, assignment, shift, record)

    result = create_correction_request(
        db,
        employee=employee,
        business=business,
        shift_assignment_id=assignment.id,
        requested_time_in=datetime(2026, 10, 21, 8, 10, tzinfo=TZ),
        requested_time_out=datetime(2026, 10, 21, 12, 4, tzinfo=TZ),
        reason="Correcting the recorded time out",
    )
    assert result["status"] == "pending"
    added = db.add.call_args[0][0]
    assert added.requested_time_in == official_in
    assert added.requested_time_out is not None


def test_approve_keeps_time_in_and_recalculates_on_time_status():
    """Approval applies Time Out only. 8:10 with a 10-minute grace stays on time."""
    business, employee = _employee_business()
    assignment, shift = _assignment(employee.id, business.id, date(2026, 10, 21))
    shift.start_time = time(8, 0)
    shift.end_time = time(12, 0)
    official_in = datetime(2026, 10, 21, 8, 10, 6, tzinfo=TZ).astimezone(timezone.utc)
    corrected_out = datetime(2026, 10, 21, 12, 4, tzinfo=TZ).astimezone(timezone.utc)
    record = AttendanceRecord(
        id=uuid4(),
        business_id=business.id,
        employee_id=employee.id,
        shift_assignment_id=assignment.id,
        time_in=official_in,
        time_out=datetime(2026, 10, 21, 12, 0, tzinfo=TZ).astimezone(timezone.utc),
        status=AttendanceStatus.late,
    )
    request = AttendanceCorrectionRequest(
        id=uuid4(),
        business_id=business.id,
        employee_id=employee.id,
        shift_assignment_id=assignment.id,
        attendance_record_id=record.id,
        requested_time_in=datetime(2026, 10, 21, 8, 0, tzinfo=TZ).astimezone(
            timezone.utc
        ),
        requested_time_out=corrected_out,
        reason="Correct time out only",
        status=AttendanceCorrectionStatus.pending,
    )
    reviewer = User(id=uuid4())
    db = MagicMock()
    _wire_db(db, assignment, shift, record)

    def get_side_effect(model, key):
        if model is AttendanceCorrectionRequest:
            return request
        if model is Employee:
            return employee
        if model is BusinessAttendancePolicy:
            return BusinessAttendancePolicy(
                business_id=business.id,
                on_time_grace_minutes=10,
                half_day_threshold_minutes=120,
                absent_threshold_minutes=240,
                absent_threshold_percent=25,
            )
        return None

    db.get.side_effect = get_side_effect

    with patch(
        "app.services.payroll_snapshot.find_finalized_run_for_period",
        return_value=None,
    ), patch(
        "app.services.ot_approval.sync_ot_approval_after_close",
    ):
        result = approve_correction(
            db,
            request_id=request.id,
            reviewer=reviewer,
            business=business,
        )

    assert result["status"] == "approved"
    assert record.time_in == official_in
    assert record.time_out == corrected_out
    assert record.status == AttendanceStatus.complete
    assert (
        monetary_late_minutes(
            time_in=datetime(2026, 10, 21, 8, 10, 6),
            scheduled_start=datetime(2026, 10, 21, 8, 0),
            grace_minutes=10,
        )
        == 0
    )


def _bind_assignment(db, assignment, shift, record=None, *, early_minutes=15):
    db.query.return_value.join.return_value.filter.return_value.first.return_value = (
        assignment,
        shift,
    )
    db.query.return_value.filter.return_value.order_by.return_value.first.return_value = (
        record
    )
    db.query.return_value.filter.return_value.first.return_value = None

    def get_side_effect(model, key):
        if model is BusinessAttendancePolicy:
            return BusinessAttendancePolicy(
                business_id=key,
                early_clock_in_minutes=early_minutes,
                on_time_grace_minutes=10,
                half_day_threshold_minutes=240,
                absent_threshold_minutes=120,
            )
        return None

    db.get.side_effect = get_side_effect
    return db


def _night_shift(employee_id, business_id, work_date=date(2026, 7, 18)):
    assignment, shift = _assignment(employee_id, business_id, work_date)
    shift.name = "Night"
    shift.start_time = time(17, 0)
    shift.end_time = time(23, 0)
    return assignment, shift


def test_night_shift_rejects_time_in_twelve_hours_from_start():
    """5:00 AM is outside the clock-in window for a 5:00 PM–11:00 PM shift."""
    business, employee = _employee_business()
    assignment, shift = _night_shift(employee.id, business.id)
    db = _bind_assignment(MagicMock(), assignment, shift)
    submitted_in = datetime(2026, 7, 18, 5, 0, tzinfo=TZ)

    with pytest.raises(HTTPException) as exc:
        create_correction_request(
            db,
            employee=employee,
            business=business,
            shift_assignment_id=assignment.id,
            requested_time_in=submitted_in,
            requested_time_out=datetime(2026, 7, 18, 23, 0, tzinfo=TZ),
            reason="Forgot to time in",
        )

    assert exc.value.status_code == 400
    detail = str(exc.value.detail)
    assert "5:00 AM" in detail
    assert "5:00 PM" in detail
    db.add.assert_not_called()
    db.commit.assert_not_called()


def test_night_shift_accepts_time_in_at_scheduled_start():
    business, employee = _employee_business()
    assignment, shift = _night_shift(employee.id, business.id)
    db = _bind_assignment(MagicMock(), assignment, shift)
    submitted_in = datetime(2026, 7, 18, 17, 0, tzinfo=TZ)

    result = create_correction_request(
        db,
        employee=employee,
        business=business,
        shift_assignment_id=assignment.id,
        requested_time_in=submitted_in,
        requested_time_out=datetime(2026, 7, 18, 23, 0, tzinfo=TZ),
        reason="Forgot to time in",
    )

    assert result["status"] == "pending"
    added = db.add.call_args[0][0]
    assert added.requested_time_in == submitted_in.astimezone(timezone.utc)
    assert added.requested_time_out == datetime(
        2026, 7, 18, 23, 0, tzinfo=TZ
    ).astimezone(timezone.utc)

    late_in = datetime(2026, 7, 18, 18, 0, tzinfo=TZ)
    late = create_correction_request(
        db,
        employee=employee,
        business=business,
        shift_assignment_id=assignment.id,
        requested_time_in=late_in,
        requested_time_out=datetime(2026, 7, 18, 23, 0, tzinfo=TZ),
        reason="Arrived during the shift",
    )
    assert late["status"] == "pending"
    assert db.add.call_args[0][0].requested_time_in == late_in.astimezone(timezone.utc)


def test_night_shift_accepts_early_clock_in_and_rejects_one_minute_before():
    business, employee = _employee_business()
    assignment, shift = _night_shift(employee.id, business.id)
    db = _bind_assignment(MagicMock(), assignment, shift, early_minutes=15)

    accepted = create_correction_request(
        db,
        employee=employee,
        business=business,
        shift_assignment_id=assignment.id,
        requested_time_in=datetime(2026, 7, 18, 16, 45, tzinfo=TZ),
        requested_time_out=datetime(2026, 7, 18, 23, 0, tzinfo=TZ),
        reason="Arrived at the early window",
    )
    assert accepted["status"] == "pending"

    with pytest.raises(HTTPException) as exc:
        create_correction_request(
            db,
            employee=employee,
            business=business,
            shift_assignment_id=assignment.id,
            requested_time_in=datetime(2026, 7, 18, 16, 44, tzinfo=TZ),
            requested_time_out=datetime(2026, 7, 18, 23, 0, tzinfo=TZ),
            reason="One minute before the window",
        )
    detail = str(exc.value.detail)
    assert "4:44 PM" in detail
    assert "5:00 PM" in detail


def test_overnight_shift_accepts_time_in_before_midnight_and_after():
    business, employee = _employee_business()
    assignment, shift = _assignment(employee.id, business.id)
    shift.name = "Overnight"
    shift.start_time = time(22, 0)
    shift.end_time = time(6, 0)
    db = _bind_assignment(MagicMock(), assignment, shift)

    before_midnight = create_correction_request(
        db,
        employee=employee,
        business=business,
        shift_assignment_id=assignment.id,
        requested_time_in=datetime(2026, 7, 18, 22, 0, tzinfo=TZ),
        requested_time_out=datetime(2026, 7, 19, 6, 0, tzinfo=TZ),
        reason="Overnight shift",
    )
    assert before_midnight["status"] == "pending"
    added = db.add.call_args[0][0]
    assert added.requested_time_in == datetime(
        2026, 7, 18, 22, 0, tzinfo=TZ
    ).astimezone(timezone.utc)

    after_midnight = create_correction_request(
        db,
        employee=employee,
        business=business,
        shift_assignment_id=assignment.id,
        requested_time_in=datetime(2026, 7, 19, 1, 0, tzinfo=TZ),
        requested_time_out=datetime(2026, 7, 19, 6, 0, tzinfo=TZ),
        reason="Clocked in after midnight",
    )
    assert after_midnight["status"] == "pending"


def test_locked_time_in_still_allows_time_out_correction_on_night_shift():
    business, employee = _employee_business()
    assignment, shift = _night_shift(employee.id, business.id)
    official_in = datetime(2026, 7, 18, 17, 5, tzinfo=TZ).astimezone(timezone.utc)
    record = AttendanceRecord(
        id=uuid4(),
        business_id=business.id,
        employee_id=employee.id,
        shift_assignment_id=assignment.id,
        time_in=official_in,
        time_out=datetime(2026, 7, 18, 22, 0, tzinfo=TZ).astimezone(timezone.utc),
        status=AttendanceStatus.complete,
    )
    db = _bind_assignment(MagicMock(), assignment, shift, record)

    result = create_correction_request(
        db,
        employee=employee,
        business=business,
        shift_assignment_id=assignment.id,
        requested_time_in=official_in,
        requested_time_out=datetime(2026, 7, 18, 23, 0, tzinfo=TZ),
        reason="Correcting the recorded time out",
    )

    assert result["status"] == "pending"
    added = db.add.call_args[0][0]
    assert added.requested_time_in == official_in


def test_invalid_time_in_cannot_be_approved():
    business, employee = _employee_business()
    assignment, shift = _night_shift(employee.id, business.id)
    submitted_in = datetime(2026, 7, 18, 5, 0, tzinfo=TZ).astimezone(timezone.utc)
    request = AttendanceCorrectionRequest(
        id=uuid4(),
        business_id=business.id,
        employee_id=employee.id,
        shift_assignment_id=assignment.id,
        attendance_record_id=None,
        requested_time_in=submitted_in,
        requested_time_out=datetime(2026, 7, 18, 23, 0, tzinfo=TZ).astimezone(
            timezone.utc
        ),
        reason="Forgot both punches",
        status=AttendanceCorrectionStatus.pending,
    )
    reviewer = User(id=uuid4())
    db = _bind_assignment(MagicMock(), assignment, shift)

    def get_side_effect(model, key):
        if model is AttendanceCorrectionRequest:
            return request
        if model is Employee:
            return employee
        if model is BusinessAttendancePolicy:
            return BusinessAttendancePolicy(
                business_id=business.id,
                early_clock_in_minutes=15,
                on_time_grace_minutes=10,
                half_day_threshold_minutes=240,
                absent_threshold_minutes=120,
            )
        return None

    db.get.side_effect = get_side_effect

    with patch(
        "app.services.payroll_snapshot.find_finalized_run_for_period",
        return_value=None,
    ), pytest.raises(HTTPException) as exc:
        approve_correction(
            db,
            request_id=request.id,
            reviewer=reviewer,
            business=business,
        )

    assert exc.value.status_code == 400
    detail = str(exc.value.detail)
    assert "5:00 AM" in detail
    assert "5:00 PM" in detail
    assert request.status == AttendanceCorrectionStatus.pending
    assert request.requested_time_in == submitted_in
    db.add.assert_not_called()
    db.commit.assert_not_called()
