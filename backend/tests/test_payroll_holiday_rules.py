"""Payroll holiday dual-mode: worked premium + unworked base + no-show gate."""

from datetime import date, datetime, time
from types import SimpleNamespace
from unittest.mock import MagicMock, patch
from uuid import uuid4

from app.api.owner_reports import _calculate_employee_payslip
from app.models.attendance import AttendanceRecord
from app.models.attendance_policy import BusinessAttendancePolicy
from app.models.business import Business
from app.models.enums import AttendanceStatus, EmploymentType, HolidayRulesMode, HolidayType
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


def _payroll_config(mode: HolidayRulesMode):
    return SimpleNamespace(
        overtime_per_minute=2.0,
        late_deduction_per_minute=1.0,
        overtime_enabled=True,
        late_deduction_enabled=True,
        holiday_rules_mode=mode,
    )


def _employee(business_id, position_id):
    return SimpleNamespace(
        id=uuid4(),
        business_id=business_id,
        full_name="Test Emp",
        position_title="Crew",
        position_id=position_id,
        employment_type=EmploymentType.full_time,
    )


def _shift(business_id):
    return Shift(
        id=uuid4(),
        business_id=business_id,
        name="Morning",
        start_time=time(8, 0),
        end_time=time(16, 0),
    )


def _assignment(employee_id, shift, work_date):
    return ShiftAssignment(
        id=uuid4(),
        shift_id=shift.id,
        employee_id=employee_id,
        work_date=work_date,
        is_rest_day_work=False,
    )


def _holiday(business_id, work_date, *, holiday_type, is_paid, pay_multiplier):
    return Holiday(
        id=uuid4(),
        business_id=business_id,
        name="Test Holiday",
        holiday_date=work_date,
        is_paid=is_paid,
        pay_multiplier=pay_multiplier,
        holiday_type=holiday_type,
        is_active=True,
    )


def _run_payslip(
    *,
    mode: HolidayRulesMode,
    work_date: date,
    holiday: Holiday | None,
    attendance_rows: list,
    scheduled: list,
    today: date = date(2026, 7, 30),
):
    business_id = uuid4()
    position_id = uuid4()
    employee = _employee(business_id, position_id)
    if holiday is not None:
        holiday.business_id = business_id

    position = SimpleNamespace(daily_rate=800.0)
    business = SimpleNamespace(timezone="Asia/Manila")
    att_policy = _att_policy(business_id)
    config = _payroll_config(mode)

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

    with (
        patch("app.api.owner_reports.ensure_incomplete_for_employee"),
        patch("app.api.owner_reports.employee_on_approved_leave", return_value=False),
        patch(
            "app.api.owner_reports.approved_leave_dates_for_employee",
            return_value=[],
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


def test_ph_worked_regular_holiday_premium():
    business_id = uuid4()
    work_date = date(2026, 7, 28)
    shift = _shift(business_id)
    employee_id = uuid4()
    assignment = _assignment(employee_id, shift, work_date)
    holiday = _holiday(
        business_id,
        work_date,
        holiday_type=HolidayType.regular,
        is_paid=True,
        pay_multiplier=2.0,
    )
    record = SimpleNamespace(
        shift_assignment_id=assignment.id,
        status=AttendanceStatus.complete,
        time_in=datetime(2026, 7, 28, 8, 0),
        time_out=datetime(2026, 7, 28, 16, 0),
        created_at=datetime(2026, 7, 28, 8, 0),
    )
    # Fix employee id on assignment path via payslip employee — rebind
    slip = _run_payslip(
        mode=HolidayRulesMode.philippine_labor,
        work_date=work_date,
        holiday=holiday,
        attendance_rows=[(record, assignment, shift)],
        scheduled=[(assignment, shift)],
    )
    # day_earned 800, premium 800 → holiday_pay 800; gross 1600
    assert slip["holiday_pay"] == 800.0
    assert slip["gross_pay"] == 1600.0
    assert slip["absent_days"] == 0


def test_ph_worked_special_holiday_premium():
    business_id = uuid4()
    work_date = date(2026, 7, 28)
    shift = _shift(business_id)
    assignment = _assignment(uuid4(), shift, work_date)
    holiday = _holiday(
        business_id,
        work_date,
        holiday_type=HolidayType.special_non_working,
        is_paid=True,
        pay_multiplier=1.3,
    )
    record = SimpleNamespace(
        shift_assignment_id=assignment.id,
        status=AttendanceStatus.complete,
        time_in=datetime(2026, 7, 28, 8, 0),
        time_out=datetime(2026, 7, 28, 16, 0),
        created_at=datetime(2026, 7, 28, 8, 0),
    )
    slip = _run_payslip(
        mode=HolidayRulesMode.philippine_labor,
        work_date=work_date,
        holiday=holiday,
        attendance_rows=[(record, assignment, shift)],
        scheduled=[(assignment, shift)],
    )
    assert slip["holiday_pay"] == 240.0  # 800 * 0.3
    assert slip["gross_pay"] == 1040.0


def test_ph_unworked_regular_holiday_pays_and_not_absent():
    business_id = uuid4()
    work_date = date(2026, 7, 28)
    shift = _shift(business_id)
    assignment = _assignment(uuid4(), shift, work_date)
    holiday = _holiday(
        business_id,
        work_date,
        holiday_type=HolidayType.regular,
        is_paid=True,
        pay_multiplier=2.0,
    )
    slip = _run_payslip(
        mode=HolidayRulesMode.philippine_labor,
        work_date=work_date,
        holiday=holiday,
        attendance_rows=[],
        scheduled=[(assignment, shift)],
    )
    assert slip["absent_days"] == 0
    assert slip["holiday_pay"] == 800.0
    assert slip["gross_pay"] == 800.0
    assert any(r["status"] == "holiday_paid" for r in slip["attendance_records"])


def test_ph_unworked_special_holiday_is_noshow_absent():
    business_id = uuid4()
    work_date = date(2026, 7, 28)
    shift = _shift(business_id)
    assignment = _assignment(uuid4(), shift, work_date)
    holiday = _holiday(
        business_id,
        work_date,
        holiday_type=HolidayType.special_non_working,
        is_paid=True,
        pay_multiplier=1.3,
    )
    slip = _run_payslip(
        mode=HolidayRulesMode.philippine_labor,
        work_date=work_date,
        holiday=holiday,
        attendance_rows=[],
        scheduled=[(assignment, shift)],
    )
    assert slip["absent_days"] == 1
    assert slip["holiday_pay"] == 0.0
    assert slip["gross_pay"] == 0.0


def test_ph_company_paid_unworked():
    business_id = uuid4()
    work_date = date(2026, 7, 28)
    shift = _shift(business_id)
    assignment = _assignment(uuid4(), shift, work_date)
    holiday = _holiday(
        business_id,
        work_date,
        holiday_type=HolidayType.company,
        is_paid=True,
        pay_multiplier=1.5,
    )
    slip = _run_payslip(
        mode=HolidayRulesMode.philippine_labor,
        work_date=work_date,
        holiday=holiday,
        attendance_rows=[],
        scheduled=[(assignment, shift)],
    )
    assert slip["absent_days"] == 0
    assert slip["holiday_pay"] == 800.0


def test_ph_company_unpaid_unworked_absent():
    business_id = uuid4()
    work_date = date(2026, 7, 28)
    shift = _shift(business_id)
    assignment = _assignment(uuid4(), shift, work_date)
    holiday = _holiday(
        business_id,
        work_date,
        holiday_type=HolidayType.company,
        is_paid=False,
        pay_multiplier=1.5,
    )
    slip = _run_payslip(
        mode=HolidayRulesMode.philippine_labor,
        work_date=work_date,
        holiday=holiday,
        attendance_rows=[],
        scheduled=[(assignment, shift)],
    )
    assert slip["absent_days"] == 1
    assert slip["holiday_pay"] == 0.0


def test_custom_worked_uses_multiplier():
    business_id = uuid4()
    work_date = date(2026, 7, 28)
    shift = _shift(business_id)
    assignment = _assignment(uuid4(), shift, work_date)
    holiday = _holiday(
        business_id,
        work_date,
        holiday_type=HolidayType.regular,
        is_paid=False,
        pay_multiplier=2.0,
    )
    record = SimpleNamespace(
        shift_assignment_id=assignment.id,
        status=AttendanceStatus.complete,
        time_in=datetime(2026, 7, 28, 8, 0),
        time_out=datetime(2026, 7, 28, 16, 0),
        created_at=datetime(2026, 7, 28, 8, 0),
    )
    slip = _run_payslip(
        mode=HolidayRulesMode.custom_company,
        work_date=work_date,
        holiday=holiday,
        attendance_rows=[(record, assignment, shift)],
        scheduled=[(assignment, shift)],
    )
    assert slip["holiday_pay"] == 800.0
    assert slip["gross_pay"] == 1600.0


def test_custom_unworked_paid():
    business_id = uuid4()
    work_date = date(2026, 7, 28)
    shift = _shift(business_id)
    assignment = _assignment(uuid4(), shift, work_date)
    holiday = _holiday(
        business_id,
        work_date,
        holiday_type=HolidayType.special_non_working,
        is_paid=True,
        pay_multiplier=1.3,
    )
    slip = _run_payslip(
        mode=HolidayRulesMode.custom_company,
        work_date=work_date,
        holiday=holiday,
        attendance_rows=[],
        scheduled=[(assignment, shift)],
    )
    assert slip["absent_days"] == 0
    assert slip["holiday_pay"] == 800.0


def test_custom_unworked_unpaid_absent():
    business_id = uuid4()
    work_date = date(2026, 7, 28)
    shift = _shift(business_id)
    assignment = _assignment(uuid4(), shift, work_date)
    holiday = _holiday(
        business_id,
        work_date,
        holiday_type=HolidayType.regular,
        is_paid=False,
        pay_multiplier=2.0,
    )
    slip = _run_payslip(
        mode=HolidayRulesMode.custom_company,
        work_date=work_date,
        holiday=holiday,
        attendance_rows=[],
        scheduled=[(assignment, shift)],
    )
    assert slip["absent_days"] == 1
    assert slip["holiday_pay"] == 0.0


def test_ordinary_workday_unchanged():
    business_id = uuid4()
    work_date = date(2026, 7, 28)
    shift = _shift(business_id)
    assignment = _assignment(uuid4(), shift, work_date)
    record = SimpleNamespace(
        shift_assignment_id=assignment.id,
        status=AttendanceStatus.complete,
        time_in=datetime(2026, 7, 28, 8, 0),
        time_out=datetime(2026, 7, 28, 16, 0),
        created_at=datetime(2026, 7, 28, 8, 0),
    )
    slip = _run_payslip(
        mode=HolidayRulesMode.philippine_labor,
        work_date=work_date,
        holiday=None,
        attendance_rows=[(record, assignment, shift)],
        scheduled=[(assignment, shift)],
    )
    assert slip["holiday_pay"] == 0.0
    assert slip["gross_pay"] == 800.0
    assert slip["absent_days"] == 0


def test_ot_unchanged_on_ordinary_day():
    business_id = uuid4()
    work_date = date(2026, 7, 28)
    shift = _shift(business_id)
    assignment = _assignment(uuid4(), shift, work_date)
    record = SimpleNamespace(
        shift_assignment_id=assignment.id,
        status=AttendanceStatus.complete,
        time_in=datetime(2026, 7, 28, 8, 0),
        time_out=datetime(2026, 7, 28, 17, 0),  # 60 min OT
        created_at=datetime(2026, 7, 28, 8, 0),
    )
    slip = _run_payslip(
        mode=HolidayRulesMode.philippine_labor,
        work_date=work_date,
        holiday=None,
        attendance_rows=[(record, assignment, shift)],
        scheduled=[(assignment, shift)],
    )
    assert slip["overtime_minutes"] == 60.0
    assert slip["overtime_pay"] == 120.0  # 60 * 2.0
    assert slip["gross_pay"] == 920.0


def test_paid_leave_unchanged():
    business_id = uuid4()
    work_date = date(2026, 7, 28)
    shift = _shift(business_id)
    assignment = _assignment(uuid4(), shift, work_date)
    record = SimpleNamespace(
        shift_assignment_id=assignment.id,
        status=AttendanceStatus.on_leave,
        time_in=None,
        time_out=None,
        created_at=datetime(2026, 7, 28, 8, 0),
    )
    with patch(
        "app.api.owner_reports.leave_is_paid_for_attendance_day",
        return_value=True,
    ):
        slip = _run_payslip(
            mode=HolidayRulesMode.philippine_labor,
            work_date=work_date,
            holiday=None,
            attendance_rows=[(record, assignment, shift)],
            scheduled=[(assignment, shift)],
        )
    assert slip["paid_leave_days"] == 1
    assert slip["gross_pay"] == 800.0
    assert slip["holiday_pay"] == 0.0


def test_noshow_ordinary_day_still_absent():
    business_id = uuid4()
    work_date = date(2026, 7, 28)
    shift = _shift(business_id)
    assignment = _assignment(uuid4(), shift, work_date)
    slip = _run_payslip(
        mode=HolidayRulesMode.philippine_labor,
        work_date=work_date,
        holiday=None,
        attendance_rows=[],
        scheduled=[(assignment, shift)],
    )
    assert slip["absent_days"] == 1
    assert slip["gross_pay"] == 0.0
