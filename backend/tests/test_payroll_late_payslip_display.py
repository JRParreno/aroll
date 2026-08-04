"""Payslip late display: hide late when scheduled hours were completed."""

from datetime import date, datetime, time, timezone
from types import SimpleNamespace
from unittest.mock import MagicMock, patch
from uuid import uuid4

from app.api.owner_reports import _calculate_employee_payslip
from app.models.attendance import AttendanceRecord
from app.models.attendance_policy import BusinessAttendancePolicy
from app.models.business import Business
from app.models.enums import AttendanceStatus, EmploymentType
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


def _run_payslip(*, status, time_in, time_out, shift_start, shift_end, daily_rate=2500.0):
    business_id = uuid4()
    employee_id = uuid4()
    position_id = uuid4()
    work_date = date(2026, 8, 2)

    employee = SimpleNamespace(
        id=employee_id,
        business_id=business_id,
        full_name="Yan A",
        position_title="Bartender",
        position_id=position_id,
        employment_type=EmploymentType.full_time,
    )
    position = SimpleNamespace(daily_rate=daily_rate)
    business = SimpleNamespace(timezone="Asia/Manila")
    att_policy = _att_policy(business_id)
    config = SimpleNamespace(
        overtime_per_minute=1.0,
        late_deduction_per_minute=1.0,
        late_deduction_enabled=True,
        overtime_enabled=True,
        holiday_rules_mode=None,
    )

    shift = Shift(
        id=uuid4(),
        business_id=business_id,
        name="Day",
        start_time=shift_start,
        end_time=shift_end,
    )
    assignment = ShiftAssignment(
        id=uuid4(),
        shift_id=shift.id,
        employee_id=employee_id,
        work_date=work_date,
        is_rest_day_work=False,
    )
    record = AttendanceRecord(
        id=uuid4(),
        business_id=business_id,
        employee_id=employee_id,
        shift_assignment_id=assignment.id,
        time_in=time_in,
        time_out=time_out,
        status=status,
    )

    db = MagicMock()

    def db_get(model, key=None):
        if model is BusinessPayrollConfig:
            return config
        if model is BusinessAttendancePolicy:
            return att_policy
        if model is Business:
            return business
        if model is BusinessRestDayPolicy:
            return None
        if model is Position:
            return position
        return None

    db.get.side_effect = db_get

    attendance_query = MagicMock()
    attendance_query.outerjoin.return_value.outerjoin.return_value.filter.return_value.all.return_value = [
        (record, assignment, shift)
    ]
    scheduled_query = MagicMock()
    scheduled_query.join.return_value.filter.return_value.all.return_value = [
        (assignment, shift)
    ]
    holiday_query = MagicMock()
    holiday_query.filter.return_value.all.return_value = []

    def real_query(*models):
        if models[0] is AttendanceRecord:
            return attendance_query
        if models[0] is ShiftAssignment:
            return scheduled_query
        if models[0] is Holiday:
            return holiday_query
        return MagicMock()

    db.query.side_effect = real_query

    with (
        patch(
            "app.api.owner_reports.ensure_incomplete_for_employee",
            return_value=None,
        ),
        patch(
            "app.api.owner_reports.employee_on_approved_leave",
            return_value=False,
        ),
        patch(
            "app.api.owner_reports.approved_leave_dates_for_employee",
            return_value=[],
        ),
        patch(
            "app.api.owner_reports.business_today",
            return_value=date(2026, 8, 4),
        ),
        patch(
            "app.api.owner_reports.business_now",
            return_value=datetime(2026, 8, 4, 12, 0),
        ),
        patch(
            "app.api.owner_reports.resolve_holiday_rules_mode",
            return_value="philippine_labor",
        ),
    ):
        slip = _calculate_employee_payslip(
            db, employee, date(2026, 8, 1), date(2026, 8, 31)
        )

    return slip, record


def test_late_but_completed_scheduled_hours_hides_late_on_payslip():
    """Arrived late, stayed longer, completed scheduled hours → no late on slip."""
    # Shift 16:00–00:00 (480 min). In 18:09 local (late), out 12:00 next day.
    # Matches Yan A-style make-up: worked >> scheduled.
    time_in = datetime(2026, 8, 2, 10, 9, tzinfo=timezone.utc)  # 18:09 PH
    time_out = datetime(2026, 8, 3, 4, 0, tzinfo=timezone.utc)  # 12:00 PH

    slip, record = _run_payslip(
        status=AttendanceStatus.late,
        time_in=time_in,
        time_out=time_out,
        shift_start=time(16, 0),
        shift_end=time(0, 0),
    )

    row = next(r for r in slip["attendance_records"] if r["date"] == "2026-08-02")
    assert row["status"] == "late"  # attendance status still late on slip row
    assert row["late_minutes"] == 0.0
    assert row["late_deduction"] == 0.0
    assert row["shortfall_deduction"] == 0.0
    assert slip["late_minutes"] == 0.0
    assert slip["late_deductions"] == 0.0
    assert slip["deductions"] == 0.0
    assert slip["net_pay"] == slip["gross_pay"]
    # Attendance record object unchanged
    assert record.status == AttendanceStatus.late


def test_late_without_completing_scheduled_hours_shows_late_on_payslip():
    """Arrived late and left at shift end → late shown and shortfall deducted."""
    # Shift 08:00–17:00 (540 min). Grace 10 → late after 08:10.
    # In 10:10 local (2h late after grace? 10:10-08:10=120 min), out 17:00.
    time_in = datetime(2026, 8, 2, 2, 10, tzinfo=timezone.utc)  # 10:10 PH
    time_out = datetime(2026, 8, 2, 9, 0, tzinfo=timezone.utc)  # 17:00 PH

    slip, record = _run_payslip(
        status=AttendanceStatus.late,
        time_in=time_in,
        time_out=time_out,
        shift_start=time(8, 0),
        shift_end=time(17, 0),
        daily_rate=2700.0,
    )

    row = next(r for r in slip["attendance_records"] if r["date"] == "2026-08-02")
    assert row["status"] == "late"
    assert row["late_minutes"] == 120.0
    assert row["late_deduction"] > 0
    assert row["shortfall_deduction"] > 0
    assert slip["late_minutes"] == 120.0
    assert slip["late_deductions"] > 0
    assert slip["deductions"] == row["shortfall_deduction"]
    assert slip["net_pay"] < slip["gross_pay"]
    assert record.status == AttendanceStatus.late


def test_late_makeup_net_pay_unchanged_from_zero_shortfall_rule():
    """Display change must not alter deductions/net when shortfall is zero."""
    time_in = datetime(2026, 8, 2, 10, 9, tzinfo=timezone.utc)
    time_out = datetime(2026, 8, 3, 4, 0, tzinfo=timezone.utc)

    slip, _record = _run_payslip(
        status=AttendanceStatus.late,
        time_in=time_in,
        time_out=time_out,
        shift_start=time(16, 0),
        shift_end=time(0, 0),
        daily_rate=2500.0,
    )

    assert slip["deductions"] == 0.0
    assert slip["net_pay"] == slip["gross_pay"]
    # Daily rate credited; OT may add on top — net still equals gross (no late cut).
    assert slip["gross_pay"] >= 2500.0
