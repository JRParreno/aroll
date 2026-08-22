"""Approved leave payroll: attendance-backed and leave-only paths."""

from datetime import date, datetime, time
from types import SimpleNamespace
from unittest.mock import MagicMock, patch
from uuid import uuid4

from app.api.owner_reports import _calculate_employee_payslip
from app.models.attendance import AttendanceRecord
from app.models.attendance_policy import BusinessAttendancePolicy
from app.models.business import Business
from app.models.enums import (
    AttendanceStatus,
    EmploymentType,
    HolidayRulesMode,
    HolidayType,
)
from app.models.holiday import Holiday
from app.models.payroll import BusinessPayrollConfig, Position
from app.models.rest_day_policy import BusinessRestDayPolicy
from app.models.scheduling import Shift, ShiftAssignment


def _att_policy(business_id):
    return SimpleNamespace(
        business_id=business_id,
        on_time_grace_minutes=10,
        overtime_minimum_minutes=30,
        half_day_threshold_minutes=240,
        overtime_enabled=True,
    )


def _payroll_config(mode=HolidayRulesMode.philippine_labor):
    return SimpleNamespace(
        overtime_per_minute=2.0,
        late_deduction_per_minute=1.0,
        overtime_enabled=True,
        late_deduction_enabled=True,
        holiday_rules_mode=mode,
    )


def _run(
    *,
    attendance_rows,
    scheduled,
    leave_dates,
    leave_paid,
    holiday=None,
    today=date(2026, 7, 30),
    employee_on_leave=None,
):
    business_id = uuid4()
    position_id = uuid4()
    employee = SimpleNamespace(
        id=uuid4(),
        business_id=business_id,
        full_name="Leave Emp",
        position_title="Crew",
        position_id=position_id,
        employment_type=EmploymentType.full_time,
    )
    if holiday is not None:
        holiday.business_id = business_id

    position = SimpleNamespace(daily_rate=800.0)
    business = SimpleNamespace(timezone="Asia/Manila")
    db = MagicMock()

    def db_get(model, key=None):
        if model is BusinessPayrollConfig:
            return _payroll_config()
        if model is BusinessAttendancePolicy:
            return _att_policy(business_id)
        if model is Business:
            return business
        if model is BusinessRestDayPolicy:
            return None
        if model is Position:
            return position
        return None

    db.get.side_effect = db_get

    attendance_query = MagicMock()
    attendance_query.outerjoin.return_value.outerjoin.return_value.filter.return_value.all.return_value = (
        attendance_rows
    )
    scheduled_query = MagicMock()
    scheduled_query.join.return_value.filter.return_value.all.return_value = scheduled
    holiday_query = MagicMock()
    holiday_query.filter.return_value.all.return_value = (
        [holiday] if holiday is not None else []
    )

    def real_query(*models):
        if models[0] is AttendanceRecord:
            return attendance_query
        if models[0] is ShiftAssignment:
            return scheduled_query
        if models[0] is Holiday:
            return holiday_query
        return MagicMock()

    db.query.side_effect = real_query

    on_leave = (
        employee_on_leave
        if employee_on_leave is not None
        else (lambda *a, **k: False)
    )

    with (
        patch("app.api.owner_reports.ensure_incomplete_for_employee"),
        patch(
            "app.api.owner_reports.employee_on_approved_leave",
            side_effect=on_leave,
        ),
        patch(
            "app.api.owner_reports.approved_leave_dates_for_employee",
            return_value=list(leave_dates),
        ),
        patch(
            "app.api.owner_reports.leave_is_paid_for_attendance_day",
            return_value=leave_paid,
        ),
        patch("app.api.owner_reports.business_today", return_value=today),
        patch(
            "app.api.owner_reports.business_now",
            return_value=datetime(today.year, today.month, today.day, 12, 0),
        ),
    ):
        return _calculate_employee_payslip(
            db, employee, date(2026, 7, 1), date(2026, 7, 31)
        )


def _shift():
    return Shift(
        id=uuid4(),
        business_id=uuid4(),
        name="Morning",
        start_time=time(8, 0),
        end_time=time(16, 0),
    )


def _assignment(shift, work_date):
    return ShiftAssignment(
        id=uuid4(),
        shift_id=shift.id,
        employee_id=uuid4(),
        work_date=work_date,
        is_rest_day_work=False,
    )


def test_paid_leave_with_on_leave_attendance():
    work_date = date(2026, 7, 28)
    shift = _shift()
    assignment = _assignment(shift, work_date)
    record = SimpleNamespace(
        shift_assignment_id=assignment.id,
        status=AttendanceStatus.on_leave,
        time_in=None,
        time_out=None,
        created_at=datetime(2026, 7, 28, 8, 0),
    )
    slip = _run(
        attendance_rows=[(record, assignment, shift)],
        scheduled=[(assignment, shift)],
        leave_dates=[work_date],
        leave_paid=True,
        employee_on_leave=lambda *a, **k: True,
    )
    assert slip["paid_leave_days"] == 1
    assert slip["unpaid_leave_days"] == 0
    assert slip["gross_pay"] == 800.0
    assert slip["absent_days"] == 0
    # One attendance-backed row only (no duplicate leave recon credit)
    leave_rows = [r for r in slip["attendance_records"] if r["status"] == "on_leave"]
    assert len(leave_rows) == 1


def test_paid_leave_without_on_leave_attendance():
    work_date = date(2026, 7, 28)
    shift = _shift()
    assignment = _assignment(shift, work_date)
    slip = _run(
        attendance_rows=[],
        scheduled=[(assignment, shift)],
        leave_dates=[work_date],
        leave_paid=True,
        employee_on_leave=lambda *a, **k: True,
    )
    assert slip["paid_leave_days"] == 1
    assert slip["gross_pay"] == 800.0
    assert slip["absent_days"] == 0
    leave_rows = [r for r in slip["attendance_records"] if r["status"] == "on_leave"]
    assert len(leave_rows) == 1
    assert leave_rows[0]["earned"] == 800.0


def test_unpaid_leave_with_on_leave_attendance():
    work_date = date(2026, 7, 28)
    shift = _shift()
    assignment = _assignment(shift, work_date)
    record = SimpleNamespace(
        shift_assignment_id=assignment.id,
        status=AttendanceStatus.on_leave,
        time_in=None,
        time_out=None,
        created_at=datetime(2026, 7, 28, 8, 0),
    )
    slip = _run(
        attendance_rows=[(record, assignment, shift)],
        scheduled=[(assignment, shift)],
        leave_dates=[work_date],
        leave_paid=False,
        employee_on_leave=lambda *a, **k: True,
    )
    assert slip["unpaid_leave_days"] == 1
    assert slip["paid_leave_days"] == 0
    assert slip["gross_pay"] == 0.0
    assert slip["absent_days"] == 0


def test_unpaid_leave_without_on_leave_attendance():
    work_date = date(2026, 7, 28)
    shift = _shift()
    assignment = _assignment(shift, work_date)
    slip = _run(
        attendance_rows=[],
        scheduled=[(assignment, shift)],
        leave_dates=[work_date],
        leave_paid=False,
        employee_on_leave=lambda *a, **k: True,
    )
    assert slip["unpaid_leave_days"] == 1
    assert slip["paid_leave_days"] == 0
    assert slip["gross_pay"] == 0.0
    assert slip["absent_days"] == 0
    leave_rows = [r for r in slip["attendance_records"] if r["status"] == "on_leave"]
    assert len(leave_rows) == 1
    assert leave_rows[0]["earned"] == 0.0


def test_leave_prevents_noshow_absence():
    work_date = date(2026, 7, 28)
    shift = _shift()
    assignment = _assignment(shift, work_date)
    slip = _run(
        attendance_rows=[],
        scheduled=[(assignment, shift)],
        leave_dates=[work_date],
        leave_paid=True,
        employee_on_leave=lambda *a, **k: True,
    )
    assert slip["absent_days"] == 0
    assert slip["paid_leave_days"] == 1


def test_leave_overlapping_holiday_no_holiday_premium_double():
    """Leave wins: paid leave daily_rate, no holiday premium / holiday base."""
    work_date = date(2026, 7, 28)
    shift = _shift()
    assignment = _assignment(shift, work_date)
    holiday = Holiday(
        id=uuid4(),
        name="Regular Holiday",
        holiday_date=work_date,
        is_paid=True,
        pay_multiplier=2.0,
        holiday_type=HolidayType.regular,
        is_active=True,
    )
    slip = _run(
        attendance_rows=[],
        scheduled=[(assignment, shift)],
        leave_dates=[work_date],
        leave_paid=True,
        holiday=holiday,
        employee_on_leave=lambda *a, **k: True,
    )
    assert slip["paid_leave_days"] == 1
    assert slip["holiday_pay"] == 0.0
    assert slip["gross_pay"] == 800.0
    assert slip["absent_days"] == 0


def test_attendance_backed_leave_unchanged_with_recon_empty():
    work_date = date(2026, 7, 28)
    shift = _shift()
    assignment = _assignment(shift, work_date)
    record = SimpleNamespace(
        shift_assignment_id=assignment.id,
        status=AttendanceStatus.on_leave,
        time_in=None,
        time_out=None,
        created_at=datetime(2026, 7, 28, 8, 0),
    )
    slip = _run(
        attendance_rows=[(record, assignment, shift)],
        scheduled=[(assignment, shift)],
        leave_dates=[],  # recon finds nothing extra
        leave_paid=True,
        employee_on_leave=lambda *a, **k: True,
    )
    assert slip["paid_leave_days"] == 1
    assert slip["gross_pay"] == 800.0


def test_ordinary_workday_unchanged():
    work_date = date(2026, 7, 28)
    shift = _shift()
    assignment = _assignment(shift, work_date)
    record = SimpleNamespace(
        shift_assignment_id=assignment.id,
        status=AttendanceStatus.complete,
        time_in=datetime(2026, 7, 28, 8, 0),
        time_out=datetime(2026, 7, 28, 16, 0),
        created_at=datetime(2026, 7, 28, 8, 0),
    )
    slip = _run(
        attendance_rows=[(record, assignment, shift)],
        scheduled=[(assignment, shift)],
        leave_dates=[],
        leave_paid=True,
    )
    assert slip["paid_leave_days"] == 0
    assert slip["gross_pay"] == 800.0
    assert slip["holiday_pay"] == 0.0
    assert slip["overtime_pay"] == 0.0


def test_holiday_payroll_unchanged_without_leave():
    work_date = date(2026, 7, 28)
    shift = _shift()
    assignment = _assignment(shift, work_date)
    holiday = Holiday(
        id=uuid4(),
        name="Regular Holiday",
        holiday_date=work_date,
        is_paid=True,
        pay_multiplier=2.0,
        holiday_type=HolidayType.regular,
        is_active=True,
    )
    record = SimpleNamespace(
        shift_assignment_id=assignment.id,
        status=AttendanceStatus.complete,
        time_in=datetime(2026, 7, 28, 8, 0),
        time_out=datetime(2026, 7, 28, 16, 0),
        created_at=datetime(2026, 7, 28, 8, 0),
    )
    slip = _run(
        attendance_rows=[(record, assignment, shift)],
        scheduled=[(assignment, shift)],
        leave_dates=[],
        leave_paid=True,
        holiday=holiday,
    )
    assert slip["holiday_pay"] == 800.0
    assert slip["gross_pay"] == 1600.0


def test_overtime_unchanged_without_leave():
    work_date = date(2026, 7, 28)
    shift = _shift()
    assignment = _assignment(shift, work_date)
    record = SimpleNamespace(
        shift_assignment_id=assignment.id,
        status=AttendanceStatus.complete,
        time_in=datetime(2026, 7, 28, 8, 0),
        time_out=datetime(2026, 7, 28, 17, 0),
        created_at=datetime(2026, 7, 28, 8, 0),
    )
    slip = _run(
        attendance_rows=[(record, assignment, shift)],
        scheduled=[(assignment, shift)],
        leave_dates=[],
        leave_paid=True,
    )
    assert slip["overtime_minutes"] == 60.0
    assert slip["overtime_pay"] == 120.0
    assert slip["gross_pay"] == 920.0
