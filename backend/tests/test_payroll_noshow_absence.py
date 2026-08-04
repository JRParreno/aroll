"""No-show absences: scheduled shifts without attendance count as absent."""

from datetime import date, datetime, time
from types import SimpleNamespace
from unittest.mock import MagicMock, patch
from uuid import uuid4

from app.api.owner_reports import _absent_day_payslip_row, _calculate_employee_payslip
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


def test_absent_day_payslip_row_shape():
    row = _absent_day_payslip_row(
        work_date=date(2026, 7, 28),
        holiday=None,
        is_rest_day=False,
    )
    assert row["status"] == AttendanceStatus.absent.value
    assert row["earned"] == 0.0
    assert row["time_in"] is None
    assert row["time_out"] is None
    assert row["payroll_status"] == "finalized"


def test_noshow_scheduled_assignment_increments_absent_days():
    business_id = uuid4()
    employee_id = uuid4()
    position_id = uuid4()
    work_date = date(2026, 7, 28)

    employee = SimpleNamespace(
        id=employee_id,
        business_id=business_id,
        full_name="No Show",
        position_title="Crew",
        position_id=position_id,
        employment_type=EmploymentType.full_time,
    )
    position = SimpleNamespace(daily_rate=800.0)
    business = SimpleNamespace(timezone="Asia/Manila")
    att_policy = _att_policy(business_id)

    shift = Shift(
        id=uuid4(),
        business_id=business_id,
        name="Morning",
        start_time=time(8, 0),
        end_time=time(16, 0),
    )
    assignment = ShiftAssignment(
        id=uuid4(),
        shift_id=shift.id,
        employee_id=employee_id,
        work_date=work_date,
        is_rest_day_work=False,
    )

    db = MagicMock()

    def db_get(model, key=None):
        if model is BusinessPayrollConfig:
            return None
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
    attendance_query.outerjoin.return_value.outerjoin.return_value.filter.return_value.all.return_value = (
        []
    )

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
            return_value=date(2026, 7, 30),
        ),
        patch(
            "app.api.owner_reports.business_now",
            return_value=datetime(2026, 7, 30, 12, 0),
        ),
    ):
        slip = _calculate_employee_payslip(
            db, employee, date(2026, 7, 1), date(2026, 7, 31)
        )

    assert slip["absent_days"] == 1
    assert slip["worked_days"] == 0.0
    assert slip["gross_pay"] == 0.0
    assert slip["net_pay"] == 0.0
    absent_rows = [
        r for r in slip["attendance_records"] if r["status"] == "absent"
    ]
    assert len(absent_rows) == 1
    assert absent_rows[0]["date"] == work_date.isoformat()
    assert absent_rows[0]["earned"] == 0.0


def test_noshow_skipped_when_attendance_already_exists():
    business_id = uuid4()
    employee_id = uuid4()
    position_id = uuid4()
    work_date = date(2026, 7, 28)

    employee = SimpleNamespace(
        id=employee_id,
        business_id=business_id,
        full_name="Present",
        position_title="Crew",
        position_id=position_id,
        employment_type=EmploymentType.full_time,
    )
    position = SimpleNamespace(daily_rate=800.0)
    business = SimpleNamespace(timezone="Asia/Manila")
    att_policy = _att_policy(business_id)

    shift = Shift(
        id=uuid4(),
        business_id=business_id,
        name="Morning",
        start_time=time(8, 0),
        end_time=time(16, 0),
    )
    assignment = ShiftAssignment(
        id=uuid4(),
        shift_id=shift.id,
        employee_id=employee_id,
        work_date=work_date,
        is_rest_day_work=False,
    )
    record = SimpleNamespace(
        shift_assignment_id=assignment.id,
        status=AttendanceStatus.complete,
        time_in=datetime(2026, 7, 28, 8, 0),
        time_out=datetime(2026, 7, 28, 16, 0),
        created_at=datetime(2026, 7, 28, 8, 0),
    )

    db = MagicMock()

    def db_get(model, key=None):
        if model is BusinessPayrollConfig:
            return None
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
            return_value=date(2026, 7, 30),
        ),
        patch(
            "app.api.owner_reports.business_now",
            return_value=datetime(2026, 7, 30, 12, 0),
        ),
    ):
        slip = _calculate_employee_payslip(
            db, employee, date(2026, 7, 1), date(2026, 7, 31)
        )

    assert slip["absent_days"] == 0
    assert slip["worked_days"] == 1.0
    assert round(slip["gross_pay"], 2) == 800.0
    assert round(slip["net_pay"], 2) == 800.0
