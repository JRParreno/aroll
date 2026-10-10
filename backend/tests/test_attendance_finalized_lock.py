"""Finalized payroll locks attendance mutations (approve + complete)."""

from datetime import date, datetime, time, timezone
from types import SimpleNamespace
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
from app.models.enums import (
    AttendanceCorrectionStatus,
    AttendanceStatus,
    OvertimeApprovalStatus,
    PayrollRunStatus,
)
from app.models.scheduling import Shift, ShiftAssignment
from app.models.user import User
from app.services.attendance_correction import approve_correction
from app.services.missing_clock_out import complete_incomplete_attendance
from app.services.payroll_snapshot import mark_payroll_run_unfinalized


TZ = ZoneInfo("Asia/Manila")
WORK_DATE = date(2026, 7, 18)
PERIOD_START = date(2026, 7, 1)
PERIOD_END = date(2026, 7, 31)


def _business_employee():
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


def _assignment_shift(employee_id, business_id, work_date=WORK_DATE):
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


def _policy(business_id):
    return BusinessAttendancePolicy(
        business_id=business_id,
        on_time_grace_minutes=10,
        half_day_threshold_minutes=240,
        absent_threshold_minutes=120,
        maximum_overtime_minutes=240,
    )


def _pending_request(*, business, employee, assignment, record):
    return AttendanceCorrectionRequest(
        id=uuid4(),
        business_id=business.id,
        employee_id=employee.id,
        shift_assignment_id=assignment.id,
        attendance_record_id=record.id if record else None,
        requested_time_in=datetime(2026, 7, 18, 9, 0, tzinfo=TZ).astimezone(
            timezone.utc
        ),
        requested_time_out=datetime(2026, 7, 18, 18, 0, tzinfo=TZ).astimezone(
            timezone.utc
        ),
        reason="Corrected Time Out",
        status=AttendanceCorrectionStatus.pending,
    )


def _wire_approve_db(*, db, business, employee, assignment, shift, record, request):
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
            return _policy(business.id)
        return None

    db.get.side_effect = get_side_effect


def test_approve_correction_before_finalization_succeeds():
    business, employee = _business_employee()
    assignment, shift = _assignment_shift(employee.id, business.id)
    original_in = datetime(2026, 7, 18, 1, 0, tzinfo=timezone.utc)
    original_out = datetime(2026, 7, 18, 9, 0, tzinfo=timezone.utc)
    record = AttendanceRecord(
        id=uuid4(),
        business_id=business.id,
        employee_id=employee.id,
        shift_assignment_id=assignment.id,
        time_in=original_in,
        time_out=original_out,
        status=AttendanceStatus.complete,
        ot_approval_status=None,
    )
    request = _pending_request(
        business=business, employee=employee, assignment=assignment, record=record
    )
    reviewer = User(id=uuid4())
    db = MagicMock()
    _wire_approve_db(
        db=db,
        business=business,
        employee=employee,
        assignment=assignment,
        shift=shift,
        record=record,
        request=request,
    )

    with patch(
        "app.services.payroll_snapshot.find_finalized_run_for_period",
        return_value=None,
    ) as find_finalized, patch(
        "app.services.ot_approval.sync_ot_approval_after_close",
    ) as sync_ot:
        result = approve_correction(
            db,
            request_id=request.id,
            reviewer=reviewer,
            business=business,
        )

    assert find_finalized.called
    assert result["status"] == "approved"
    assert request.status == AttendanceCorrectionStatus.approved
    assert record.time_out is not None
    assert record.time_out != original_out
    assert sync_ot.called
    assert db.commit.called


def test_approve_correction_after_finalization_rejected_unchanged():
    business, employee = _business_employee()
    assignment, shift = _assignment_shift(employee.id, business.id)
    original_in = datetime(2026, 7, 18, 1, 0, tzinfo=timezone.utc)
    original_out = datetime(2026, 7, 18, 9, 0, tzinfo=timezone.utc)
    record = AttendanceRecord(
        id=uuid4(),
        business_id=business.id,
        employee_id=employee.id,
        shift_assignment_id=assignment.id,
        time_in=original_in,
        time_out=original_out,
        status=AttendanceStatus.complete,
        ot_approval_status=OvertimeApprovalStatus.approved,
        ot_reviewed_by=uuid4(),
        ot_reviewed_at=datetime(2026, 7, 19, 0, 0, tzinfo=timezone.utc),
    )
    request = _pending_request(
        business=business, employee=employee, assignment=assignment, record=record
    )
    reviewer = User(id=uuid4())
    db = MagicMock()
    _wire_approve_db(
        db=db,
        business=business,
        employee=employee,
        assignment=assignment,
        shift=shift,
        record=record,
        request=request,
    )
    snapshot_before = {
        "time_in": record.time_in,
        "time_out": record.time_out,
        "status": record.status,
        "ot_approval_status": record.ot_approval_status,
        "ot_reviewed_by": record.ot_reviewed_by,
        "ot_reviewed_at": record.ot_reviewed_at,
        "request_status": request.status,
    }

    with patch(
        "app.services.pay_period.resolve_pay_period",
        return_value=(PERIOD_START, PERIOD_END),
    ), patch(
        "app.services.payroll_snapshot.find_finalized_run_for_period",
        return_value=SimpleNamespace(id=uuid4(), status=PayrollRunStatus.finalized),
    ), patch(
        "app.services.ot_approval.sync_ot_approval_after_close",
    ) as sync_ot:
        with pytest.raises(HTTPException) as exc:
            approve_correction(
                db,
                request_id=request.id,
                reviewer=reviewer,
                business=business,
            )

    assert exc.value.status_code == 409
    assert exc.value.detail["code"] == "payroll_finalized"
    assert record.time_in == snapshot_before["time_in"]
    assert record.time_out == snapshot_before["time_out"]
    assert record.status == snapshot_before["status"]
    assert record.ot_approval_status == snapshot_before["ot_approval_status"]
    assert record.ot_reviewed_by == snapshot_before["ot_reviewed_by"]
    assert record.ot_reviewed_at == snapshot_before["ot_reviewed_at"]
    assert request.status == snapshot_before["request_status"]
    assert not sync_ot.called
    assert not db.commit.called


def test_complete_incomplete_before_finalization_succeeds():
    business, employee = _business_employee()
    assignment, shift = _assignment_shift(employee.id, business.id)
    record = AttendanceRecord(
        id=uuid4(),
        business_id=business.id,
        employee_id=employee.id,
        shift_assignment_id=assignment.id,
        time_in=datetime(2026, 7, 18, 1, 0, tzinfo=timezone.utc),
        time_out=None,
        status=AttendanceStatus.incomplete,
    )
    reviewer = User(id=uuid4(), business_id=business.id)
    db = MagicMock()
    db.query.return_value.filter.return_value.first.return_value = record
    db.query.return_value.join.return_value.filter.return_value.first.return_value = (
        assignment,
        shift,
    )

    def get_side_effect(model, key):
        if model is BusinessAttendancePolicy:
            return _policy(business.id)
        if model is Employee:
            return employee
        return None

    db.get.side_effect = get_side_effect

    with patch(
        "app.services.payroll_snapshot.find_finalized_run_for_period",
        return_value=None,
    ), patch(
        "app.services.ot_approval.sync_ot_approval_after_close",
    ) as sync_ot, patch(
        "app.services.missing_clock_out.create_log",
    ):
        updated = complete_incomplete_attendance(
            db,
            record_id=record.id,
            reviewer=reviewer,
            business=business,
            time_out=datetime(2026, 7, 18, 17, 0, tzinfo=TZ).astimezone(timezone.utc),
            reason="Forgot to clock out",
        )

    assert updated.time_out is not None
    assert updated.status != AttendanceStatus.incomplete
    assert sync_ot.called
    assert db.commit.called


def test_complete_incomplete_after_finalization_rejected_unchanged():
    business, employee = _business_employee()
    assignment, shift = _assignment_shift(employee.id, business.id)
    record = AttendanceRecord(
        id=uuid4(),
        business_id=business.id,
        employee_id=employee.id,
        shift_assignment_id=assignment.id,
        time_in=datetime(2026, 7, 18, 1, 0, tzinfo=timezone.utc),
        time_out=None,
        status=AttendanceStatus.incomplete,
        ot_approval_status=None,
    )
    reviewer = User(id=uuid4(), business_id=business.id)
    db = MagicMock()
    db.query.return_value.filter.return_value.first.return_value = record
    db.query.return_value.join.return_value.filter.return_value.first.return_value = (
        assignment,
        shift,
    )

    def get_side_effect(model, key):
        if model is BusinessAttendancePolicy:
            return _policy(business.id)
        if model is Employee:
            return employee
        return None

    db.get.side_effect = get_side_effect
    before = {
        "time_in": record.time_in,
        "time_out": record.time_out,
        "status": record.status,
        "ot_approval_status": record.ot_approval_status,
    }

    with patch(
        "app.services.pay_period.resolve_pay_period",
        return_value=(PERIOD_START, PERIOD_END),
    ), patch(
        "app.services.payroll_snapshot.find_finalized_run_for_period",
        return_value=SimpleNamespace(id=uuid4(), status=PayrollRunStatus.finalized),
    ), patch(
        "app.services.ot_approval.sync_ot_approval_after_close",
    ) as sync_ot, patch(
        "app.services.missing_clock_out.create_log",
    ) as create_log:
        with pytest.raises(HTTPException) as exc:
            complete_incomplete_attendance(
                db,
                record_id=record.id,
                reviewer=reviewer,
                business=business,
                time_out=datetime(2026, 7, 18, 17, 0, tzinfo=TZ).astimezone(
                    timezone.utc
                ),
                reason="Should be blocked",
            )

    assert exc.value.status_code == 409
    assert exc.value.detail["code"] == "payroll_finalized"
    assert record.time_in == before["time_in"]
    assert record.time_out == before["time_out"]
    assert record.status == before["status"]
    assert record.ot_approval_status == before["ot_approval_status"]
    assert not sync_ot.called
    assert not create_log.called
    assert not db.commit.called


def test_blocked_mutation_does_not_change_finalized_snapshot_payload():
    """Guard rejects before mutation; frozen payslip JSON is never touched."""
    business, employee = _business_employee()
    assignment, shift = _assignment_shift(employee.id, business.id)
    record = AttendanceRecord(
        id=uuid4(),
        business_id=business.id,
        employee_id=employee.id,
        shift_assignment_id=assignment.id,
        time_in=datetime(2026, 7, 18, 1, 0, tzinfo=timezone.utc),
        time_out=datetime(2026, 7, 18, 9, 0, tzinfo=timezone.utc),
        status=AttendanceStatus.complete,
    )
    request = _pending_request(
        business=business, employee=employee, assignment=assignment, record=record
    )
    reviewer = User(id=uuid4())
    db = MagicMock()
    _wire_approve_db(
        db=db,
        business=business,
        employee=employee,
        assignment=assignment,
        shift=shift,
        record=record,
        request=request,
    )

    frozen_breakdown = {
        "net_pay": 1000.0,
        "attendance_records": [
            {
                "time_in": "2026-07-18T01:00:00+00:00",
                "time_out": "2026-07-18T09:00:00+00:00",
            }
        ],
    }
    payslip = SimpleNamespace(breakdown_json=dict(frozen_breakdown))

    with patch(
        "app.services.pay_period.resolve_pay_period",
        return_value=(PERIOD_START, PERIOD_END),
    ), patch(
        "app.services.payroll_snapshot.find_finalized_run_for_period",
        return_value=SimpleNamespace(id=uuid4()),
    ):
        with pytest.raises(HTTPException) as exc:
            approve_correction(
                db,
                request_id=request.id,
                reviewer=reviewer,
                business=business,
            )

    assert exc.value.status_code == 409
    assert payslip.breakdown_json == frozen_breakdown
    assert record.time_out == datetime(2026, 7, 18, 9, 0, tzinfo=timezone.utc)


def test_unfinalize_restores_correction_approval():
    """Existing unfinalize (cancelled run) clears the finalize lock for approvals."""
    business, employee = _business_employee()
    assignment, shift = _assignment_shift(employee.id, business.id)
    record = AttendanceRecord(
        id=uuid4(),
        business_id=business.id,
        employee_id=employee.id,
        shift_assignment_id=assignment.id,
        time_in=datetime(2026, 7, 18, 1, 0, tzinfo=timezone.utc),
        time_out=datetime(2026, 7, 18, 9, 0, tzinfo=timezone.utc),
        status=AttendanceStatus.complete,
    )
    request = _pending_request(
        business=business, employee=employee, assignment=assignment, record=record
    )
    reviewer = User(id=uuid4())
    db = MagicMock()
    _wire_approve_db(
        db=db,
        business=business,
        employee=employee,
        assignment=assignment,
        shift=shift,
        record=record,
        request=request,
    )

    run = SimpleNamespace(id=uuid4(), status=PayrollRunStatus.finalized)
    # First call: still finalized → 409. After mark_unfinalized, find returns None.
    find_results = [run, None]

    def find_side_effect(*_args, **_kwargs):
        return find_results.pop(0)

    with patch(
        "app.services.pay_period.resolve_pay_period",
        return_value=(PERIOD_START, PERIOD_END),
    ), patch(
        "app.services.payroll_snapshot.find_finalized_run_for_period",
        side_effect=find_side_effect,
    ), patch(
        "app.services.ot_approval.sync_ot_approval_after_close",
    ):
        with pytest.raises(HTTPException) as blocked:
            approve_correction(
                db,
                request_id=request.id,
                reviewer=reviewer,
                business=business,
            )
        assert blocked.value.status_code == 409

        mark_payroll_run_unfinalized(run)
        assert run.status == PayrollRunStatus.cancelled

        # Reset pending after blocked attempt (request never mutated, still pending).
        assert request.status == AttendanceCorrectionStatus.pending

        result = approve_correction(
            db,
            request_id=request.id,
            reviewer=reviewer,
            business=business,
        )

    assert result["status"] == "approved"
    assert request.status == AttendanceCorrectionStatus.approved
