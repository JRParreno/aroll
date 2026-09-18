"""Payroll correction: worked days, hours, overlap, OT premiums, daily workday."""

import inspect
from contextlib import ExitStack
from datetime import date, datetime, time, timezone
from types import SimpleNamespace
from unittest.mock import MagicMock, patch
from uuid import uuid4

from app.api.employee_mobile import _simple_payslip_pdf
from app.api.owner_reports import _calculate_employee_payslip
from app.models.attendance import AttendanceRecord
from app.models.attendance_policy import BusinessAttendancePolicy
from app.models.business import Business
from app.models.enums import AttendanceStatus, EmploymentType, HolidayType, PayBasis
from app.models.holiday import Holiday
from app.models.payroll import BusinessPayrollConfig, Position
from app.models.rest_day_policy import BusinessRestDayPolicy
from app.models.scheduling import Shift, ShiftAssignment
from app.services.payroll_engine import (
    early_departure_minutes,
    hours_worked_from_slip,
    in_shift_payable_minutes,
    is_scheduled_assignment_resolved,
    monetary_late_minutes,
    overtime_pay_amount,
    overtime_premium_percent,
    qualifying_overtime_minutes,
    remaining_monetary_late_minutes,
    scheduled_paid_minutes,
    scheduled_working_minutes,
)


def _ph(hour: int, minute: int = 0, day: int = 4) -> datetime:
    utc_hour = hour - 8
    utc_day = day
    if utc_hour < 0:
        utc_hour += 24
        utc_day = day - 1
    return datetime(2026, 8, utc_day, utc_hour, minute, tzinfo=timezone.utc)


def _run(
    *,
    pay_basis: PayBasis = PayBasis.daily,
    daily_rate: float | None = 850.0,
    hourly_rate: float | None = None,
    monthly_salary: float | None = None,
    rows: list | None = None,
    scheduled: list | None = None,
    holidays: list | None = None,
    rest_premium: float | None = None,
    enable_late_overtime_balancing: bool = False,
    ot_minimum: int = 30,
    ordinary_ot: float = 25.0,
    rest_day_ot: float = 25.0,
    overtime_enabled: bool = True,
    overtime_per_minute: float = 1.0,
    late_deduction_per_minute: float = 1.0,
    late_deduction_enabled: bool = True,
    employment_type: EmploymentType = EmploymentType.full_time,
    grace_minutes: int = 10,
    period_start: date = date(2026, 8, 1),
    period_end: date = date(2026, 8, 31),
    today: date = date(2026, 8, 10),
    now: datetime | None = None,
    clock_out_deadline_passed: bool | None = True,
    breaktime_is_paid: bool = False,
):
    business_id = uuid4()
    employee_id = uuid4()
    position_id = uuid4()
    employee = SimpleNamespace(
        id=employee_id,
        business_id=business_id,
        full_name="Pay Emp",
        position_title="Staff",
        position_id=position_id,
        employment_type=employment_type,
        pay_basis=pay_basis,
        daily_rate=daily_rate,
        hourly_rate=hourly_rate,
        monthly_salary=monthly_salary,
    )
    position = SimpleNamespace(daily_rate=daily_rate or 0.0, hourly_rate=hourly_rate)
    business = SimpleNamespace(timezone="Asia/Manila")
    att_policy = SimpleNamespace(
        business_id=business_id,
        on_time_grace_minutes=grace_minutes,
        overtime_minimum_minutes=ot_minimum,
        half_day_threshold_minutes=240,
        overtime_enabled=overtime_enabled,
        breaktime_is_paid=breaktime_is_paid,
    )
    config = SimpleNamespace(
        overtime_per_minute=overtime_per_minute,
        late_deduction_per_minute=late_deduction_per_minute,
        late_deduction_enabled=late_deduction_enabled,
        overtime_enabled=overtime_enabled,
        enable_late_overtime_balancing=enable_late_overtime_balancing,
        holiday_rules_mode=None,
        ordinary_ot_premium_percent=ordinary_ot,
        rest_day_ot_premium_percent=rest_day_ot,
    )
    rest_policy = (
        SimpleNamespace(rest_day_premium_percent=rest_premium)
        if rest_premium is not None
        else None
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
            return rest_policy
        if model is Position:
            return position
        return None

    db.get.side_effect = db_get
    attendance_query = MagicMock()
    attendance_query.outerjoin.return_value.outerjoin.return_value.filter.return_value.all.return_value = (
        rows or []
    )
    scheduled_query = MagicMock()
    scheduled_query.join.return_value.filter.return_value.all.return_value = (
        scheduled or []
    )
    holiday_query = MagicMock()
    holiday_query.filter.return_value.all.return_value = holidays or []

    def real_query(*models):
        if models[0] is AttendanceRecord:
            return attendance_query
        if models[0] is ShiftAssignment:
            return scheduled_query
        if models[0] is Holiday:
            return holiday_query
        return MagicMock()

    db.query.side_effect = real_query

    with ExitStack() as stack:
        stack.enter_context(patch("app.api.owner_reports.ensure_incomplete_for_employee"))
        stack.enter_context(
            patch("app.api.owner_reports.employee_on_approved_leave", return_value=False)
        )
        stack.enter_context(
            patch(
                "app.api.owner_reports.approved_leave_dates_for_employee",
                return_value=[],
            )
        )
        stack.enter_context(
            patch("app.api.owner_reports.business_today", return_value=today)
        )
        stack.enter_context(
            patch(
                "app.api.owner_reports.business_now",
                return_value=now
                or datetime(today.year, today.month, today.day, 12, 0),
            )
        )
        stack.enter_context(
            patch(
                "app.api.owner_reports.resolve_holiday_rules_mode",
                return_value="philippine_labor",
            )
        )
        if clock_out_deadline_passed is not None:
            stack.enter_context(
                patch(
                    "app.api.owner_reports.is_past_clock_out_deadline",
                    return_value=clock_out_deadline_passed,
                )
            )
        stack.enter_context(
            patch(
                "app.api.owner_reports.leave_is_paid_for_attendance_day",
                return_value=True,
            )
        )
        return _calculate_employee_payslip(
            db, employee, period_start, period_end
        )


def _shift_pair(start: time, end: time, *, name="Shift", break_minutes=0, work_date=None):
    business_id = uuid4()
    employee_id = uuid4()
    shift = Shift(
        id=uuid4(),
        business_id=business_id,
        name=name,
        start_time=start,
        end_time=end,
        break_minutes=break_minutes,
    )
    assignment = ShiftAssignment(
        id=uuid4(),
        shift_id=shift.id,
        employee_id=employee_id,
        work_date=work_date or date(2026, 8, 4),
        is_rest_day_work=False,
    )
    return shift, assignment


def _record(assignment, time_in, time_out, status=AttendanceStatus.complete):
    return AttendanceRecord(
        id=uuid4(),
        business_id=uuid4(),
        employee_id=assignment.employee_id,
        shift_assignment_id=assignment.id,
        time_in=time_in,
        time_out=time_out,
        status=status,
    )


def test_scheduled_working_minutes_subtracts_unpaid_break():
    assert scheduled_working_minutes(span_minutes=540, break_minutes=60) == 480
    assert scheduled_working_minutes(span_minutes=480, break_minutes=0) == 480
    assert scheduled_working_minutes(span_minutes=60, break_minutes=90) == 0
    assert scheduled_paid_minutes(
        span_minutes=180, break_minutes=35, breaktime_is_paid=False
    ) == 145
    assert scheduled_paid_minutes(
        span_minutes=180, break_minutes=35, breaktime_is_paid=True
    ) == 180


def test_in_shift_payable_ignores_early_arrival():
    start = datetime(2026, 8, 4, 8, 0)
    end = datetime(2026, 8, 4, 17, 0)
    payable = in_shift_payable_minutes(
        time_in=datetime(2026, 8, 4, 7, 30),
        time_out=datetime(2026, 8, 4, 16, 30),
        scheduled_start=start,
        scheduled_end=end,
        scheduled_working=540,
    )
    assert payable == 510


def test_monetary_late_minutes_respects_grace():
    start = datetime(2026, 8, 4, 8, 0)
    assert monetary_late_minutes(
        time_in=datetime(2026, 8, 4, 8, 8),
        scheduled_start=start,
        grace_minutes=10,
    ) == 0
    assert monetary_late_minutes(
        time_in=datetime(2026, 8, 4, 8, 15),
        scheduled_start=start,
        grace_minutes=10,
    ) == 5


def test_early_departure_ignores_early_arrival():
    end = datetime(2026, 8, 4, 17, 0)
    assert early_departure_minutes(
        time_out=datetime(2026, 8, 4, 16, 0),
        scheduled_end=end,
    ) == 60
    assert early_departure_minutes(
        time_out=datetime(2026, 8, 4, 17, 0),
        scheduled_end=end,
    ) == 0


def test_ot_threshold_counts_from_shift_end():
    start = datetime(2026, 8, 4, 8, 0)
    end = datetime(2026, 8, 4, 11, 0)
    time_in = datetime(2026, 8, 4, 8, 0)
    assert qualifying_overtime_minutes(
        time_in=time_in,
        time_out=datetime(2026, 8, 4, 11, 20),
        scheduled_start=start,
        scheduled_end=end,
        ot_minimum=30,
        late_ot_balancing=False,
    ) == (0.0, 0.0)
    assert qualifying_overtime_minutes(
        time_in=time_in,
        time_out=datetime(2026, 8, 4, 11, 30),
        scheduled_start=start,
        scheduled_end=end,
        ot_minimum=30,
        late_ot_balancing=False,
    ) == (30.0, 0.0)
    assert qualifying_overtime_minutes(
        time_in=time_in,
        time_out=datetime(2026, 8, 4, 11, 45),
        scheduled_start=start,
        scheduled_end=end,
        ot_minimum=30,
        late_ot_balancing=False,
    ) == (45.0, 0.0)


def test_one_shift_one_worked_day():
    shift, assignment = _shift_pair(time(8, 0), time(16, 0))
    record = _record(assignment, _ph(8, 0), _ph(16, 0))
    slip = _run(
        rows=[(record, assignment, shift)],
        scheduled=[(assignment, shift)],
        daily_rate=800.0,
    )
    assert slip["worked_days"] == 1.0
    assert slip["hours_worked"] == 8.0


def test_two_shifts_same_day_one_worked_day():
    morning, morning_asg = _shift_pair(time(8, 0), time(11, 0), name="AM")
    afternoon, afternoon_asg = _shift_pair(time(13, 0), time(17, 0), name="PM")
    rows = [
        (_record(morning_asg, _ph(8, 0), _ph(11, 0)), morning_asg, morning),
        (_record(afternoon_asg, _ph(13, 0), _ph(17, 0)), afternoon_asg, afternoon),
    ]
    slip = _run(
        pay_basis=PayBasis.hourly,
        daily_rate=None,
        hourly_rate=100.0,
        rows=rows,
        scheduled=[(morning_asg, morning), (afternoon_asg, afternoon)],
    )
    assert slip["worked_days"] == 1.0
    assert slip["hours_worked"] == 7.0
    assert abs(slip["regular_pay"] - 700.0) < 0.01


def test_shifts_on_two_days_two_worked_days():
    day1, asg1 = _shift_pair(time(8, 0), time(16, 0), work_date=date(2026, 8, 4))
    day2, asg2 = _shift_pair(time(8, 0), time(16, 0), work_date=date(2026, 8, 5))
    rows = [
        (_record(asg1, _ph(8, 0, day=4), _ph(16, 0, day=4)), asg1, day1),
        (_record(asg2, _ph(8, 0, day=5), _ph(16, 0, day=5)), asg2, day2),
    ]
    slip = _run(
        rows=rows,
        scheduled=[(asg1, day1), (asg2, day2)],
        daily_rate=800.0,
    )
    assert slip["worked_days"] == 2.0
    assert slip["hours_worked"] == 16.0


def test_hours_worked_not_days_times_eight():
    morning, morning_asg = _shift_pair(time(8, 0), time(11, 0), name="AM")
    afternoon, afternoon_asg = _shift_pair(time(13, 0), time(17, 0), name="PM")
    rows = [
        (_record(morning_asg, _ph(8, 0), _ph(11, 0)), morning_asg, morning),
        (_record(afternoon_asg, _ph(13, 0), _ph(17, 0)), afternoon_asg, afternoon),
    ]
    slip = _run(
        pay_basis=PayBasis.hourly,
        daily_rate=None,
        hourly_rate=100.0,
        rows=rows,
        scheduled=[(morning_asg, morning), (afternoon_asg, afternoon)],
    )
    assert hours_worked_from_slip(slip) == 7.0
    assert hours_worked_from_slip(slip) != slip["worked_days"] * 8
    assert hours_worked_from_slip(slip) != 16.0


def test_early_arrival_does_not_offset_early_departure():
    shift, assignment = _shift_pair(time(8, 0), time(17, 0))
    record = _record(assignment, _ph(7, 30), _ph(16, 30))
    slip = _run(
        rows=[(record, assignment, shift)],
        scheduled=[(assignment, shift)],
        daily_rate=540.0,
    )
    assert slip["hours_worked"] == 8.5
    assert slip["unpaid_minutes"] == 30.0
    assert abs(slip["deductions"] - 30.0) < 0.01
    assert abs(slip["undertime_deductions"] - slip["deductions"]) < 0.01
    assert slip["overtime_minutes"] == 0.0


def test_ot_threshold_payslip_11_20_11_30_11_45():
    shift, assignment = _shift_pair(time(8, 0), time(11, 0))
    for out_hour, out_min, expected in ((11, 20, 0.0), (11, 30, 30.0), (11, 45, 45.0)):
        record = _record(assignment, _ph(8, 0), _ph(out_hour, out_min))
        slip = _run(
            rows=[(record, assignment, shift)],
            scheduled=[(assignment, shift)],
            daily_rate=180.0,
            ot_minimum=30,
        )
        assert slip["overtime_minutes"] == expected


def test_late_ot_balancing_equal_window_zero_ot():
    shift, assignment = _shift_pair(time(8, 0), time(17, 0))
    record = _record(assignment, _ph(8, 30), _ph(17, 30), status=AttendanceStatus.late)
    slip = _run(
        rows=[(record, assignment, shift)],
        scheduled=[(assignment, shift)],
        daily_rate=540.0,
        enable_late_overtime_balancing=True,
    )
    assert slip["overtime_minutes"] == 0.0
    assert slip["overtime_pay"] == 0.0
    # OT 30 recovers 30 late-from-start; remaining monetary late is 0.
    assert slip["late_deductions"] == 0.0
    assert slip["undertime_deductions"] == 0.0
    assert slip["deductions"] == 0.0


def test_late_ot_balancing_remainder_becomes_ot():
    # late-from-start 20 + raw OT 50 → remaining 30, which meets the 30 threshold.
    shift, assignment = _shift_pair(time(8, 0), time(17, 0))
    record = _record(assignment, _ph(8, 20), _ph(17, 50), status=AttendanceStatus.late)
    slip = _run(
        rows=[(record, assignment, shift)],
        scheduled=[(assignment, shift)],
        daily_rate=540.0,
        enable_late_overtime_balancing=True,
        ot_minimum=30,
    )
    assert slip["overtime_minutes"] == 30.0
    assert slip["late_deductions"] == 0.0
    assert slip["undertime_deductions"] == 0.0


def test_early_arrival_does_not_participate_in_balancing():
    shift, assignment = _shift_pair(time(8, 0), time(17, 0))
    record = _record(assignment, _ph(7, 30), _ph(17, 30))
    slip = _run(
        rows=[(record, assignment, shift)],
        scheduled=[(assignment, shift)],
        daily_rate=540.0,
        enable_late_overtime_balancing=True,
    )
    assert slip["overtime_minutes"] == 30.0
    assert slip["deductions"] == 0.0


def test_ordinary_ot_uses_owner_rate_with_zero_premium():
    shift, assignment = _shift_pair(time(8, 0), time(16, 0))
    record = _record(assignment, _ph(8, 0), _ph(17, 0))
    slip = _run(
        pay_basis=PayBasis.hourly,
        daily_rate=None,
        hourly_rate=120.0,
        rows=[(record, assignment, shift)],
        scheduled=[(assignment, shift)],
        ordinary_ot=25.0,
        overtime_per_minute=1.0,
    )
    expected = overtime_pay_amount(60, 1.0, 0.0)
    assert slip["overtime_minutes"] == 60.0
    assert abs(slip["overtime_pay"] - expected) < 0.01
    assert abs(slip["overtime_pay"] - 60.0) < 0.01
    assert abs(slip["overtime_pay"] - overtime_pay_amount(60, 1.0, 25.0)) > 0.01
    assert slip["overtime_pay"] != overtime_pay_amount(60, 120.0 / 60.0, 25.0)


def test_special_holiday_ot_premium():
    work_date = date(2026, 8, 4)
    shift, assignment = _shift_pair(time(8, 0), time(16, 0), work_date=work_date)
    holiday = Holiday(
        id=uuid4(),
        business_id=uuid4(),
        name="Special",
        holiday_date=work_date,
        holiday_type=HolidayType.special_non_working,
        is_paid=True,
        pay_multiplier=1.3,
        ot_premium_percent=30.0,
        is_active=True,
    )
    record = _record(assignment, _ph(8, 0), _ph(17, 0))
    slip = _run(
        pay_basis=PayBasis.hourly,
        daily_rate=None,
        hourly_rate=60.0,
        rows=[(record, assignment, shift)],
        scheduled=[(assignment, shift)],
        holidays=[holiday],
    )
    expected = overtime_pay_amount(60, 1.0, 30.0)
    assert abs(slip["overtime_pay"] - expected) < 0.01


def test_regular_holiday_ot_premium():
    work_date = date(2026, 8, 4)
    shift, assignment = _shift_pair(time(8, 0), time(16, 0), work_date=work_date)
    holiday = Holiday(
        id=uuid4(),
        business_id=uuid4(),
        name="Regular",
        holiday_date=work_date,
        holiday_type=HolidayType.regular,
        is_paid=True,
        pay_multiplier=2.0,
        ot_premium_percent=40.0,
        is_active=True,
    )
    record = _record(assignment, _ph(8, 0), _ph(17, 0))
    slip = _run(
        pay_basis=PayBasis.hourly,
        daily_rate=None,
        hourly_rate=60.0,
        rows=[(record, assignment, shift)],
        scheduled=[(assignment, shift)],
        holidays=[holiday],
        ordinary_ot=25.0,
        rest_day_ot=30.0,
    )
    expected = overtime_pay_amount(60, 1.0, 40.0)
    assert abs(slip["overtime_pay"] - expected) < 0.01


def test_holiday_rest_day_ot_premium_priority():
    work_date = date(2026, 8, 4)
    shift, assignment = _shift_pair(time(8, 0), time(16, 0), work_date=work_date)
    assignment.is_rest_day_work = True
    holiday = Holiday(
        id=uuid4(),
        business_id=uuid4(),
        name="Regular",
        holiday_date=work_date,
        holiday_type=HolidayType.regular,
        is_paid=True,
        pay_multiplier=2.0,
        ot_premium_percent=50.0,
        is_active=True,
    )
    config = SimpleNamespace(
        ordinary_ot_premium_percent=25.0,
        rest_day_ot_premium_percent=30.0,
    )
    assert overtime_premium_percent(config, holiday, True) == 50.0
    record = _record(assignment, _ph(8, 0), _ph(17, 0))
    slip = _run(
        pay_basis=PayBasis.hourly,
        daily_rate=None,
        hourly_rate=60.0,
        rows=[(record, assignment, shift)],
        scheduled=[(assignment, shift)],
        holidays=[holiday],
        ordinary_ot=25.0,
        rest_day_ot=30.0,
        rest_premium=30.0,
    )
    expected = overtime_pay_amount(60, 1.0, 50.0)
    assert abs(slip["overtime_pay"] - expected) < 0.01
    assert abs(slip["overtime_pay"] - overtime_pay_amount(60, 1.0, 30.0)) > 0.01


def test_daily_two_shifts_same_date_one_daily_rate():
    morning, morning_asg = _shift_pair(time(8, 0), time(12, 0), name="AM")
    evening, evening_asg = _shift_pair(time(13, 0), time(17, 0), name="PM")
    rows = [
        (_record(morning_asg, _ph(8, 0), _ph(12, 0)), morning_asg, morning),
        (_record(evening_asg, _ph(13, 0), _ph(17, 0)), evening_asg, evening),
    ]
    slip = _run(
        pay_basis=PayBasis.daily,
        daily_rate=850.0,
        rows=rows,
        scheduled=[(morning_asg, morning), (evening_asg, evening)],
    )
    assert slip["worked_days"] == 1.0
    assert abs(slip["regular_pay"] - 850.0) < 0.01
    assert abs(slip["gross_pay"] - 850.0) < 0.01
    assert slip["net_pay"] == 850.0
    assert slip["hours_worked"] == 8.0


def test_undertime_display_equals_actual_deduction():
    shift, assignment = _shift_pair(time(8, 0), time(17, 0))
    record = _record(assignment, _ph(8, 0), _ph(16, 0))
    slip = _run(
        rows=[(record, assignment, shift)],
        scheduled=[(assignment, shift)],
        daily_rate=540.0,
    )
    assert slip["deductions"] > 0
    assert abs(slip["undertime_deductions"] - slip["deductions"]) < 0.01
    assert abs(slip["late_deductions"] + slip["undertime_deductions"] - slip["deductions"]) < 0.01
    net_from_parts = slip["gross_pay"] - slip["deductions"]
    assert abs(slip["net_pay"] - net_from_parts) < 0.01


def test_unpaid_break_reduces_scheduled_entitlement():
    shift, assignment = _shift_pair(time(8, 0), time(17, 0), break_minutes=60)
    record = _record(assignment, _ph(8, 0), _ph(17, 0))
    slip = _run(
        rows=[(record, assignment, shift)],
        scheduled=[(assignment, shift)],
        daily_rate=800.0,
    )
    assert slip["hours_worked"] == 8.0
    assert slip["deductions"] == 0.0
    assert abs(slip["net_pay"] - 800.0) < 0.01


def test_break_is_not_subtracted_when_zero():
    shift, assignment = _shift_pair(time(8, 0), time(16, 0), break_minutes=0)
    record = _record(assignment, _ph(8, 0), _ph(16, 0))
    slip = _run(
        rows=[(record, assignment, shift)],
        scheduled=[(assignment, shift)],
        daily_rate=800.0,
    )
    assert slip["hours_worked"] == 8.0
    assert slip["net_pay"] == 800.0


def test_hourly_pdf_uses_regular_pay_not_daily_times_days():
    pdf = _simple_payslip_pdf(
        {
            "business_name": "Test Co",
            "employee_name": "Hourly Emp",
            "position_title": "Cashier",
            "period_start": "2026-08-01",
            "period_end": "2026-08-15",
            "worked_days": 2,
            "hours_worked": 9.0,
            "pay_basis": "hourly",
            "hourly_rate": 100.0,
            "daily_rate": 650.0,
            "regular_pay": 900.0,
            "leave_pay": 0.0,
            "overtime_pay": 125.0,
            "holiday_pay": 0.0,
            "rest_day_pay": 0.0,
            "gross_pay": 1025.0,
            "deductions": 0.0,
            "net_pay": 1025.0,
        }
    )
    assert b"Basic salary: PHP 900.00" in pdf
    assert b"Leave pay: PHP 0.00" in pdf
    assert b"Hourly rate: PHP 100.00" in pdf
    assert b"1,300.00" not in pdf
    assert b"Hours worked: 9.0" in pdf


def test_pdf_totals_agree_with_backend_regular_pay():
    shift, assignment = _shift_pair(time(8, 0), time(16, 0))
    record = _record(assignment, _ph(8, 0), _ph(16, 0))
    slip = _run(
        pay_basis=PayBasis.hourly,
        daily_rate=None,
        hourly_rate=100.0,
        rows=[(record, assignment, shift)],
        scheduled=[(assignment, shift)],
    )
    pdf = _simple_payslip_pdf(
        {
            "business_name": "Test Co",
            "employee_name": slip["employee_name"],
            "position_title": slip["position_title"],
            "period_start": slip["period_start"],
            "period_end": slip["period_end"],
            "worked_days": slip["worked_days"],
            "hours_worked": slip["hours_worked"],
            "pay_basis": slip["pay_basis"],
            "hourly_rate": slip["hourly_rate"],
            "daily_rate": slip["daily_rate"],
            "regular_pay": slip["regular_pay"],
            "leave_pay": slip.get("leave_pay", 0),
            "overtime_pay": slip["overtime_pay"],
            "holiday_pay": slip["holiday_pay"],
            "rest_day_pay": slip["rest_day_pay"],
            "gross_pay": slip["gross_pay"],
            "deductions": slip["deductions"],
            "net_pay": slip["net_pay"],
        }
    )
    assert f"Basic salary: PHP {slip['regular_pay']:,.2f}".encode() in pdf
    assert f"Leave pay: PHP {slip.get('leave_pay', 0):,.2f}".encode() in pdf
    assert f"Gross pay: PHP {slip['gross_pay']:,.2f}".encode() in pdf


def test_monthly_without_daily_rate_does_not_invent_divisor():
    shift, assignment = _shift_pair(time(8, 0), time(16, 0))
    record = _record(assignment, _ph(8, 0), _ph(16, 0))
    slip = _run(
        pay_basis=PayBasis.monthly,
        daily_rate=None,
        hourly_rate=None,
        monthly_salary=20000.0,
        rows=[(record, assignment, shift)],
        scheduled=[(assignment, shift)],
    )
    assert slip["pay_basis"] == "monthly"
    assert slip["monthly_salary"] == 20000.0
    assert slip["regular_pay"] == 0.0
    assert slip["net_pay"] == 0.0


def _money_fields(slip: dict) -> dict:
    return {
        "regular_pay": slip["regular_pay"],
        "overtime_pay": slip["overtime_pay"],
        "late_deductions": slip["late_deductions"],
        "undertime_deductions": slip["undertime_deductions"],
        "deductions": slip["deductions"],
        "gross_pay": slip["gross_pay"],
        "net_pay": slip["net_pay"],
        "worked_days": slip["worked_days"],
        "hours_worked": slip["hours_worked"],
        "holiday_pay": slip["holiday_pay"],
        "rest_day_pay": slip["rest_day_pay"],
        "overtime_minutes": slip["overtime_minutes"],
        "late_minutes": slip["late_minutes"],
        "undertime_minutes": slip["undertime_minutes"],
    }


def test_daily_three_hour_completed_shift_one_daily_rate():
    shift, assignment = _shift_pair(time(13, 0), time(16, 0))
    record = _record(assignment, _ph(13, 0), _ph(16, 0))
    slip = _run(
        rows=[(record, assignment, shift)],
        scheduled=[(assignment, shift)],
        daily_rate=850.0,
    )
    assert slip["worked_days"] == 1.0
    assert abs(slip["regular_pay"] - 850.0) < 0.01
    assert slip["hours_worked"] == 3.0
    assert slip["deductions"] == 0.0
    assert slip["net_pay"] == 850.0


def test_late_within_grace_is_on_time_zero_pesos():
    shift, assignment = _shift_pair(time(8, 0), time(17, 0))
    record = _record(assignment, _ph(8, 8), _ph(17, 0))
    slip = _run(
        rows=[(record, assignment, shift)],
        scheduled=[(assignment, shift)],
        daily_rate=850.0,
        late_deduction_per_minute=1.0,
        grace_minutes=10,
    )
    assert slip["late_minutes"] == 0.0
    assert slip["late_deductions"] == 0.0
    assert slip["undertime_minutes"] == 0.0
    assert slip["undertime_deductions"] == 0.0
    assert abs(slip["net_pay"] - 850.0) < 0.01


def test_late_after_grace_uses_owner_per_minute():
    shift, assignment = _shift_pair(time(8, 0), time(17, 0))
    record = _record(assignment, _ph(8, 15), _ph(17, 0), status=AttendanceStatus.late)
    slip = _run(
        rows=[(record, assignment, shift)],
        scheduled=[(assignment, shift)],
        daily_rate=850.0,
        late_deduction_per_minute=1.0,
        grace_minutes=10,
    )
    assert slip["late_minutes"] == 5.0
    assert abs(slip["late_deductions"] - 5.0) < 0.01
    assert slip["undertime_minutes"] == 0.0
    assert slip["undertime_deductions"] == 0.0
    assert abs(slip["deductions"] - 5.0) < 0.01


def test_late_toggle_off_zeroes_money_keeps_late_minutes():
    shift, assignment = _shift_pair(time(8, 0), time(17, 0))
    record = _record(assignment, _ph(8, 15), _ph(17, 0), status=AttendanceStatus.late)
    slip = _run(
        rows=[(record, assignment, shift)],
        scheduled=[(assignment, shift)],
        daily_rate=850.0,
        late_deduction_per_minute=1.0,
        late_deduction_enabled=False,
        grace_minutes=10,
    )
    assert slip["late_minutes"] == 5.0
    assert slip["late_deductions"] == 0.0
    assert slip["deductions"] == 0.0
    assert abs(slip["net_pay"] - 850.0) < 0.01


def test_late_and_undertime_remain_separate():
    """8:20–16:00 on 8:00–17:00, grace 10 → 10 late min + 60 undertime min."""
    shift, assignment = _shift_pair(time(8, 0), time(17, 0))
    record = _record(assignment, _ph(8, 20), _ph(16, 0), status=AttendanceStatus.late)
    slip = _run(
        rows=[(record, assignment, shift)],
        scheduled=[(assignment, shift)],
        daily_rate=540.0,
        late_deduction_per_minute=1.0,
        grace_minutes=10,
    )
    assert slip["late_minutes"] == 10.0
    assert abs(slip["late_deductions"] - 10.0) < 0.01
    assert slip["undertime_minutes"] == 60.0
    assert abs(slip["undertime_deductions"] - 60.0) < 0.01
    assert abs(slip["deductions"] - 70.0) < 0.01
    assert abs(slip["regular_pay"] - 540.0) < 0.01


def test_grace_does_not_become_undertime():
    shift, assignment = _shift_pair(time(8, 0), time(17, 0))
    record = _record(assignment, _ph(8, 8), _ph(17, 0))
    slip = _run(
        rows=[(record, assignment, shift)],
        scheduled=[(assignment, shift)],
        daily_rate=540.0,
    )
    assert slip["late_minutes"] == 0.0
    assert slip["undertime_minutes"] == 0.0
    assert slip["deductions"] == 0.0


def test_daily_undertime_uses_daily_rate_over_scheduled_minutes():
    shift, assignment = _shift_pair(time(8, 0), time(16, 0))
    record = _record(assignment, _ph(8, 0), _ph(15, 0))
    slip = _run(
        rows=[(record, assignment, shift)],
        scheduled=[(assignment, shift)],
        daily_rate=480.0,
    )
    assert slip["undertime_minutes"] == 60.0
    assert abs(slip["undertime_deductions"] - 60.0) < 0.01
    assert slip["late_deductions"] == 0.0


def test_ot_below_threshold_is_zero_pay():
    shift, assignment = _shift_pair(time(8, 0), time(11, 0))
    record = _record(assignment, _ph(8, 0), _ph(11, 20))
    slip = _run(
        rows=[(record, assignment, shift)],
        scheduled=[(assignment, shift)],
        daily_rate=180.0,
        ot_minimum=30,
        overtime_per_minute=2.0,
    )
    assert slip["overtime_minutes"] == 0.0
    assert slip["overtime_pay"] == 0.0


def test_threshold_20_minutes_pays_zero():
    shift, assignment = _shift_pair(time(8, 0), time(16, 0))
    record = _record(assignment, _ph(8, 0), _ph(16, 20))
    slip = _run(
        rows=[(record, assignment, shift)],
        scheduled=[(assignment, shift)],
        overtime_per_minute=1.0,
        ot_minimum=30,
        ordinary_ot=25.0,
    )
    assert slip["overtime_minutes"] == 0.0
    assert slip["overtime_pay"] == 0.0


def test_threshold_30_minutes_pays_all_30_not_subtracted():
    shift, assignment = _shift_pair(time(8, 0), time(16, 0))
    record = _record(assignment, _ph(8, 0), _ph(16, 30))
    slip = _run(
        rows=[(record, assignment, shift)],
        scheduled=[(assignment, shift)],
        overtime_per_minute=1.0,
        ot_minimum=30,
        ordinary_ot=25.0,
    )
    assert slip["overtime_minutes"] == 30.0
    assert abs(slip["overtime_pay"] - 30.0) < 0.01
    assert slip["overtime_minutes"] != 0.0


def test_ot_uses_overtime_per_minute_not_wage_minute():
    shift, assignment = _shift_pair(time(8, 0), time(16, 0))
    record = _record(assignment, _ph(8, 0), _ph(16, 45))
    slip = _run(
        rows=[(record, assignment, shift)],
        scheduled=[(assignment, shift)],
        daily_rate=800.0,
        overtime_per_minute=2.0,
        ordinary_ot=25.0,
        ot_minimum=30,
    )
    assert slip["overtime_minutes"] == 45.0
    expected = overtime_pay_amount(45, 2.0, 0.0)
    assert abs(slip["overtime_pay"] - expected) < 0.01
    assert slip["overtime_pay"] != overtime_pay_amount(45, 800.0 / 480.0, 0.0)


def test_hourly_two_four_hour_shifts_pay_independently():
    morning, morning_asg = _shift_pair(time(8, 0), time(12, 0), name="AM")
    evening, evening_asg = _shift_pair(time(13, 0), time(17, 0), name="PM")
    rows = [
        (_record(morning_asg, _ph(8, 0), _ph(12, 0)), morning_asg, morning),
        (_record(evening_asg, _ph(13, 0), _ph(17, 0)), evening_asg, evening),
    ]
    slip = _run(
        pay_basis=PayBasis.hourly,
        daily_rate=None,
        hourly_rate=100.0,
        rows=rows,
        scheduled=[(morning_asg, morning), (evening_asg, evening)],
    )
    assert abs(slip["regular_pay"] - 800.0) < 0.01
    assert slip["hours_worked"] == 8.0
    assert slip["worked_days"] == 1.0
    assert slip["net_pay"] == 800.0


def test_hourly_missed_second_shift_is_absence_not_daily_rate():
    morning, morning_asg = _shift_pair(time(8, 0), time(12, 0), name="AM")
    evening, evening_asg = _shift_pair(time(13, 0), time(17, 0), name="PM")
    rows = [
        (_record(morning_asg, _ph(8, 0), _ph(12, 0)), morning_asg, morning),
    ]
    slip = _run(
        pay_basis=PayBasis.hourly,
        daily_rate=None,
        hourly_rate=100.0,
        rows=rows,
        scheduled=[(morning_asg, morning), (evening_asg, evening)],
    )
    assert abs(slip["regular_pay"] - 400.0) < 0.01
    assert slip["absent_days"] == 1
    assert slip["daily_rate"] == 0.0 or slip["regular_pay"] != slip["daily_rate"]
    assert slip["net_pay"] == 400.0


def test_daily_two_leave_rows_same_date_one_daily_rate():
    morning, morning_asg = _shift_pair(time(8, 0), time(12, 0), name="AM")
    evening, evening_asg = _shift_pair(time(13, 0), time(17, 0), name="PM")
    rows = [
        (_record(morning_asg, None, None, status=AttendanceStatus.on_leave), morning_asg, morning),
        (_record(evening_asg, None, None, status=AttendanceStatus.on_leave), evening_asg, evening),
    ]
    slip = _run(
        daily_rate=850.0,
        rows=rows,
        scheduled=[(morning_asg, morning), (evening_asg, evening)],
    )
    assert abs(slip["leave_pay"] - 850.0) < 0.01
    assert abs(slip["regular_pay"] - 0.0) < 0.01
    assert slip["paid_leave_days"] == 1
    assert slip["worked_days"] == 1.0


def test_daily_two_unworked_holiday_assignments_one_credit():
    work_date = date(2026, 8, 4)
    morning, morning_asg = _shift_pair(
        time(8, 0), time(12, 0), name="AM", work_date=work_date
    )
    evening, evening_asg = _shift_pair(
        time(13, 0), time(17, 0), name="PM", work_date=work_date
    )
    holiday = Holiday(
        id=uuid4(),
        business_id=uuid4(),
        name="Regular",
        holiday_date=work_date,
        holiday_type=HolidayType.regular,
        is_paid=True,
        pay_multiplier=2.0,
        is_active=True,
    )
    slip = _run(
        daily_rate=850.0,
        rows=[],
        scheduled=[(morning_asg, morning), (evening_asg, evening)],
        holidays=[holiday],
    )
    assert abs(slip["holiday_pay"] - 850.0) < 0.01
    assert slip["regular_pay"] == 0.0
    assert slip["absent_days"] == 0


def test_rest_day_regular_premium_separate_from_ot_premium():
    shift, assignment = _shift_pair(time(8, 0), time(16, 0))
    assignment.is_rest_day_work = True
    record = _record(assignment, _ph(8, 0), _ph(17, 0))
    slip = _run(
        daily_rate=800.0,
        rows=[(record, assignment, shift)],
        scheduled=[(assignment, shift)],
        rest_premium=30.0,
        overtime_per_minute=1.0,
        ordinary_ot=25.0,
    )
    assert abs(slip["rest_day_pay"] - 240.0) < 0.01
    assert abs(slip["overtime_pay"] - overtime_pay_amount(60, 1.0, 0.0)) < 0.01
    assert abs(slip["overtime_pay"] - overtime_pay_amount(60, 1.0, 25.0)) > 0.01
    assert abs(slip["rest_day_pay"] - slip["overtime_pay"]) > 0.01


def test_employment_type_does_not_change_payroll_amounts():
    shift, assignment = _shift_pair(time(8, 0), time(16, 0))
    kwargs = dict(
        pay_basis=PayBasis.daily,
        daily_rate=850.0,
        scheduled=[(assignment, shift)],
        late_deduction_per_minute=1.0,
        overtime_per_minute=2.0,
    )
    full = _run(
        employment_type=EmploymentType.full_time,
        rows=[(_record(assignment, _ph(8, 15), _ph(16, 45), status=AttendanceStatus.late), assignment, shift)],
        **kwargs,
    )
    part = _run(
        employment_type=EmploymentType.part_time,
        rows=[(_record(assignment, _ph(8, 15), _ph(16, 45), status=AttendanceStatus.late), assignment, shift)],
        **kwargs,
    )
    assert full["employment_type"] != part["employment_type"]
    assert _money_fields(full) == _money_fields(part)


def test_part_time_daily_follows_daily_path():
    shift, assignment = _shift_pair(time(8, 0), time(16, 0))
    record = _record(assignment, _ph(8, 0), _ph(16, 0))
    slip = _run(
        employment_type=EmploymentType.part_time,
        pay_basis=PayBasis.daily,
        daily_rate=850.0,
        rows=[(record, assignment, shift)],
        scheduled=[(assignment, shift)],
    )
    assert slip["pay_basis"] == "daily"
    assert abs(slip["regular_pay"] - 850.0) < 0.01
    assert slip["hours_worked"] == 8.0


def test_part_time_hourly_follows_hourly_path():
    shift, assignment = _shift_pair(time(8, 0), time(16, 0))
    record = _record(assignment, _ph(8, 0), _ph(16, 0))
    slip = _run(
        employment_type=EmploymentType.part_time,
        pay_basis=PayBasis.hourly,
        daily_rate=None,
        hourly_rate=100.0,
        rows=[(record, assignment, shift)],
        scheduled=[(assignment, shift)],
    )
    assert slip["pay_basis"] == "hourly"
    assert abs(slip["regular_pay"] - 800.0) < 0.01
    assert abs(slip["net_pay"] - 800.0) < 0.01


def _ot_holiday(
    work_date,
    *,
    name="Holiday",
    holiday_type=HolidayType.regular,
    pay_multiplier=2.0,
    ot_premium_percent=None,
):
    return Holiday(
        id=uuid4(),
        business_id=uuid4(),
        name=name,
        holiday_date=work_date,
        holiday_type=holiday_type,
        is_paid=True,
        pay_multiplier=pay_multiplier,
        ot_premium_percent=ot_premium_percent,
        is_active=True,
    )


def test_ordinary_day_45_minutes_ot_pays_45():
    shift, assignment = _shift_pair(time(8, 0), time(16, 0))
    record = _record(assignment, _ph(8, 0), _ph(16, 45))
    slip = _run(
        rows=[(record, assignment, shift)],
        scheduled=[(assignment, shift)],
        ordinary_ot=25.0,
        rest_day_ot=25.0,
        overtime_per_minute=1.0,
        ot_minimum=30,
    )
    assert slip["overtime_minutes"] == 45.0
    assert abs(slip["overtime_pay"] - 45.0) < 0.01
    assert abs(slip["overtime_pay"] - overtime_pay_amount(45, 1.0, 25.0)) > 0.01


def test_rest_day_60_minutes_ot_pays_60_legacy_25_ignored():
    shift, assignment = _shift_pair(time(8, 0), time(16, 0))
    assignment.is_rest_day_work = True
    record = _record(assignment, _ph(8, 0), _ph(17, 0))
    slip = _run(
        rows=[(record, assignment, shift)],
        scheduled=[(assignment, shift)],
        ordinary_ot=25.0,
        rest_day_ot=25.0,
        rest_premium=30.0,
        overtime_per_minute=1.0,
        ot_minimum=30,
    )
    assert slip["overtime_minutes"] == 60.0
    assert abs(slip["overtime_pay"] - 60.0) < 0.01
    assert abs(slip["overtime_pay"] - overtime_pay_amount(60, 1.0, 25.0)) > 0.01


def test_legacy_rest_day_ot_percent_does_not_change_ot_pay():
    shift, assignment = _shift_pair(time(8, 0), time(16, 0))
    assignment.is_rest_day_work = True
    record = _record(assignment, _ph(8, 0), _ph(17, 0))
    kwargs = dict(
        rows=[(record, assignment, shift)],
        scheduled=[(assignment, shift)],
        ordinary_ot=25.0,
        rest_premium=30.0,
        overtime_per_minute=1.0,
        ot_minimum=30,
    )
    slip_25 = _run(rest_day_ot=25.0, **kwargs)
    slip_40 = _run(rest_day_ot=40.0, **kwargs)
    assert abs(slip_25["overtime_pay"] - 60.0) < 0.01
    assert abs(slip_40["overtime_pay"] - 60.0) < 0.01
    assert abs(slip_25["overtime_pay"] - slip_40["overtime_pay"]) < 0.01


def test_holiday_specific_ot_premium_25_vs_30():
    work_date = date(2026, 8, 4)
    shift, assignment = _shift_pair(time(8, 0), time(16, 0), work_date=work_date)
    christmas = _ot_holiday(
        work_date, name="Christmas Day", ot_premium_percent=30.0
    )
    anniversary = _ot_holiday(
        work_date,
        name="Company Anniversary",
        holiday_type=HolidayType.company,
        pay_multiplier=1.0,
        ot_premium_percent=25.0,
    )
    record = _record(assignment, _ph(8, 0), _ph(16, 30))
    kwargs = dict(
        rows=[(record, assignment, shift)],
        scheduled=[(assignment, shift)],
        ordinary_ot=10.0,
        rest_day_ot=40.0,
        overtime_per_minute=1.0,
        ot_minimum=30,
    )
    slip_30 = _run(holidays=[christmas], **kwargs)
    slip_25 = _run(holidays=[anniversary], **kwargs)
    assert abs(slip_30["overtime_pay"] - overtime_pay_amount(30, 1.0, 30.0)) < 0.01
    assert abs(slip_25["overtime_pay"] - overtime_pay_amount(30, 1.0, 25.0)) < 0.01
    assert abs(slip_30["overtime_pay"] - slip_25["overtime_pay"]) > 0.01


def test_holiday_30_percent_60_minutes_pays_78():
    work_date = date(2026, 8, 4)
    shift, assignment = _shift_pair(time(8, 0), time(16, 0), work_date=work_date)
    holiday = _ot_holiday(work_date, ot_premium_percent=30.0)
    record = _record(assignment, _ph(8, 0), _ph(17, 0))
    slip = _run(
        rows=[(record, assignment, shift)],
        scheduled=[(assignment, shift)],
        holidays=[holiday],
        ordinary_ot=25.0,
        overtime_per_minute=1.0,
        ot_minimum=30,
    )
    assert slip["overtime_minutes"] == 60.0
    assert abs(slip["overtime_pay"] - 78.0) < 0.01
    assert abs(slip["overtime_pay"] - overtime_pay_amount(60, 1.0, 30.0)) < 0.01


def test_holiday_zero_percent_60_minutes_pays_60():
    work_date = date(2026, 8, 4)
    shift, assignment = _shift_pair(time(8, 0), time(16, 0), work_date=work_date)
    holiday = _ot_holiday(work_date, ot_premium_percent=0.0)
    record = _record(assignment, _ph(8, 0), _ph(17, 0))
    slip = _run(
        rows=[(record, assignment, shift)],
        scheduled=[(assignment, shift)],
        holidays=[holiday],
        ordinary_ot=25.0,
        rest_day_ot=25.0,
        overtime_per_minute=1.0,
        ot_minimum=30,
    )
    assert slip["overtime_minutes"] == 60.0
    assert abs(slip["overtime_pay"] - 60.0) < 0.01


def test_holiday_null_ot_premium_is_zero_on_rest_day():
    work_date = date(2026, 8, 4)
    shift, assignment = _shift_pair(time(8, 0), time(16, 0), work_date=work_date)
    assignment.is_rest_day_work = True
    holiday = _ot_holiday(work_date, ot_premium_percent=None)
    config = SimpleNamespace(
        ordinary_ot_premium_percent=25.0,
        rest_day_ot_premium_percent=30.0,
    )
    assert overtime_premium_percent(config, holiday, True) == 0.0
    record = _record(assignment, _ph(8, 0), _ph(17, 0))
    slip = _run(
        rows=[(record, assignment, shift)],
        scheduled=[(assignment, shift)],
        holidays=[holiday],
        ordinary_ot=25.0,
        rest_day_ot=30.0,
        rest_premium=30.0,
        overtime_per_minute=1.0,
    )
    assert slip["overtime_minutes"] == 60.0
    assert abs(slip["overtime_pay"] - 60.0) < 0.01


def test_holiday_null_ot_premium_is_zero():
    work_date = date(2026, 8, 4)
    shift, assignment = _shift_pair(time(8, 0), time(16, 0), work_date=work_date)
    holiday = _ot_holiday(work_date, ot_premium_percent=None)
    config = SimpleNamespace(
        ordinary_ot_premium_percent=25.0,
        rest_day_ot_premium_percent=30.0,
    )
    assert overtime_premium_percent(config, holiday, False) == 0.0
    record = _record(assignment, _ph(8, 0), _ph(17, 0))
    slip = _run(
        rows=[(record, assignment, shift)],
        scheduled=[(assignment, shift)],
        holidays=[holiday],
        ordinary_ot=25.0,
        rest_day_ot=30.0,
        overtime_per_minute=1.0,
    )
    assert slip["overtime_minutes"] == 60.0
    assert abs(slip["overtime_pay"] - 60.0) < 0.01
    assert abs(slip["overtime_pay"] - overtime_pay_amount(60, 1.0, 25.0)) > 0.01


def test_ot_base_is_owner_per_minute_not_wage_rate():
    work_date = date(2026, 8, 4)
    shift, assignment = _shift_pair(time(8, 0), time(16, 0), work_date=work_date)
    assignment.is_rest_day_work = True
    holiday = _ot_holiday(work_date, ot_premium_percent=30.0)
    record = _record(assignment, _ph(8, 0), _ph(16, 30))
    slip = _run(
        pay_basis=PayBasis.daily,
        daily_rate=800.0,
        rows=[(record, assignment, shift)],
        scheduled=[(assignment, shift)],
        holidays=[holiday],
        rest_premium=30.0,
        overtime_per_minute=2.0,
        ot_minimum=30,
    )
    expected = overtime_pay_amount(30, 2.0, 30.0)
    wage_minute = overtime_pay_amount(30, 800.0 / 480.0, 30.0)
    assert abs(slip["overtime_pay"] - expected) < 0.01
    assert abs(slip["overtime_pay"] - wage_minute) > 0.01


def test_balancing_20_late_30_raw_ot_pays_10_and_clears_late_pesos():
    shift, assignment = _shift_pair(time(8, 0), time(17, 0))
    record = _record(assignment, _ph(8, 20), _ph(17, 30), status=AttendanceStatus.late)
    slip = _run(
        rows=[(record, assignment, shift)],
        scheduled=[(assignment, shift)],
        daily_rate=540.0,
        enable_late_overtime_balancing=True,
        grace_minutes=0,
        ot_minimum=0,
        late_deduction_per_minute=1.0,
        overtime_per_minute=1.0,
        ordinary_ot=0.0,
    )
    assert slip["overtime_minutes"] == 10.0
    assert slip["late_deductions"] == 0.0
    assert abs(slip["overtime_pay"] - overtime_pay_amount(10, 1.0, 0.0)) < 0.01
    assert slip["overtime_minutes"] != 30.0


def test_balancing_then_threshold_20_remaining_is_zero():
    shift, assignment = _shift_pair(time(8, 0), time(17, 0))
    record = _record(assignment, _ph(8, 20), _ph(17, 40), status=AttendanceStatus.late)
    slip = _run(
        rows=[(record, assignment, shift)],
        scheduled=[(assignment, shift)],
        enable_late_overtime_balancing=True,
        grace_minutes=0,
        ot_minimum=30,
        overtime_per_minute=1.0,
    )
    assert slip["overtime_minutes"] == 0.0
    assert slip["overtime_pay"] == 0.0
    assert slip["late_deductions"] == 0.0


def test_balancing_then_threshold_30_remaining_pays_30():
    shift, assignment = _shift_pair(time(8, 0), time(17, 0))
    record = _record(assignment, _ph(8, 20), _ph(17, 50), status=AttendanceStatus.late)
    slip = _run(
        rows=[(record, assignment, shift)],
        scheduled=[(assignment, shift)],
        enable_late_overtime_balancing=True,
        grace_minutes=0,
        ot_minimum=30,
        overtime_per_minute=1.0,
        ordinary_ot=0.0,
    )
    assert slip["overtime_minutes"] == 30.0
    assert abs(slip["overtime_pay"] - overtime_pay_amount(30, 1.0, 0.0)) < 0.01
    assert slip["late_deductions"] == 0.0


def test_threshold_is_not_subtracted_from_remaining_ot():
    start = datetime(2026, 8, 4, 8, 0)
    end = datetime(2026, 8, 4, 17, 0)
    ot_mins, recovered = qualifying_overtime_minutes(
        time_in=datetime(2026, 8, 4, 8, 20),
        time_out=datetime(2026, 8, 4, 17, 50),
        scheduled_start=start,
        scheduled_end=end,
        ot_minimum=30,
        late_ot_balancing=True,
    )
    assert recovered == 20.0
    assert ot_mins == 30.0
    assert ot_mins != 0.0


def test_full_time_hourly_and_part_time_hourly_payroll_amounts_match():
    shift, assignment = _shift_pair(time(8, 0), time(16, 0))
    kwargs = dict(
        pay_basis=PayBasis.hourly,
        daily_rate=None,
        hourly_rate=100.0,
        scheduled=[(assignment, shift)],
        late_deduction_per_minute=1.0,
        overtime_per_minute=2.0,
        rest_day_ot=30.0,
    )
    full = _run(
        employment_type=EmploymentType.full_time,
        rows=[
            (
                _record(assignment, _ph(8, 15), _ph(16, 45), status=AttendanceStatus.late),
                assignment,
                shift,
            )
        ],
        **kwargs,
    )
    part = _run(
        employment_type=EmploymentType.part_time,
        rows=[
            (
                _record(assignment, _ph(8, 15), _ph(16, 45), status=AttendanceStatus.late),
                assignment,
                shift,
            )
        ],
        **kwargs,
    )
    assert full["employment_type"] != part["employment_type"]
    assert _money_fields(full) == _money_fields(part)
    assert full["pay_basis"] == "hourly"
    assert part["pay_basis"] == "hourly"


def test_payroll_helpers_do_not_branch_on_employment_type():
    from app.services import employee_pay

    for fn in (
        overtime_premium_percent,
        qualifying_overtime_minutes,
        overtime_pay_amount,
        monetary_late_minutes,
        early_departure_minutes,
        employee_pay.resolve_employee_pay_context,
        employee_pay.resolve_employee_pay,
    ):
        assert "employment_type" not in inspect.getsource(fn)
    assembler = inspect.getsource(_calculate_employee_payslip)
    assert "employment_type ==" not in assembler
    assert "PayBasis" in assembler or "pay_basis" in assembler


def test_legacy_business_ot_fields_do_not_select_premium():
    config = SimpleNamespace(
        ordinary_ot_premium_percent=25.0,
        rest_day_ot_premium_percent=30.0,
        special_day_ot_premium_percent=99.0,
        regular_holiday_ot_premium_percent=98.0,
        holiday_rest_day_ot_premium_percent=97.0,
    )
    special = SimpleNamespace(
        ot_premium_percent=None,
        holiday_type=HolidayType.special_non_working,
    )
    regular = SimpleNamespace(
        ot_premium_percent=None,
        holiday_type=HolidayType.regular,
    )
    zero = SimpleNamespace(
        ot_premium_percent=0.0,
        holiday_type=HolidayType.regular,
    )
    assert overtime_premium_percent(config, special, False) == 0.0
    assert overtime_premium_percent(config, regular, False) == 0.0
    assert overtime_premium_percent(config, regular, True) == 0.0
    assert overtime_premium_percent(config, None, True) == 0.0
    assert overtime_premium_percent(config, None, False) == 0.0
    assert overtime_premium_percent(config, zero, True) == 0.0


def test_explicit_zero_holiday_ot_premium_does_not_fallback():
    work_date = date(2026, 8, 4)
    shift, assignment = _shift_pair(time(8, 0), time(16, 0), work_date=work_date)
    assignment.is_rest_day_work = True
    holiday = _ot_holiday(work_date, ot_premium_percent=0.0)
    record = _record(assignment, _ph(8, 0), _ph(16, 30))
    slip = _run(
        rows=[(record, assignment, shift)],
        scheduled=[(assignment, shift)],
        holidays=[holiday],
        ordinary_ot=25.0,
        rest_day_ot=30.0,
        rest_premium=30.0,
        overtime_per_minute=1.0,
    )
    assert overtime_premium_percent(
        SimpleNamespace(
            ordinary_ot_premium_percent=25.0,
            rest_day_ot_premium_percent=30.0,
        ),
        holiday,
        True,
    ) == 0.0
    assert abs(slip["overtime_pay"] - overtime_pay_amount(30, 1.0, 0.0)) < 0.01
    assert abs(slip["overtime_pay"] - overtime_pay_amount(30, 1.0, 25.0)) > 0.01
    assert abs(slip["overtime_pay"] - overtime_pay_amount(30, 1.0, 30.0)) > 0.01


def test_holiday_ot_premium_same_field_as_owner_api():
    """Web and Mobile both persist holiday.ot_premium_percent; engine reads that field."""
    work_date = date(2026, 8, 4)
    shift, assignment = _shift_pair(time(8, 0), time(16, 0), work_date=work_date)
    holiday = _ot_holiday(work_date, ot_premium_percent=30.0)
    record = _record(assignment, _ph(8, 0), _ph(16, 30))
    slip = _run(
        rows=[(record, assignment, shift)],
        scheduled=[(assignment, shift)],
        holidays=[holiday],
        ordinary_ot=25.0,
        rest_day_ot=40.0,
        overtime_per_minute=1.0,
    )
    assert abs(slip["overtime_pay"] - overtime_pay_amount(30, 1.0, 30.0)) < 0.01


def test_grace_on_time_8_08_zero_monetary_late():
    shift, assignment = _shift_pair(time(8, 0), time(17, 0))
    record = _record(assignment, _ph(8, 8), _ph(17, 0))
    slip = _run(
        rows=[(record, assignment, shift)],
        scheduled=[(assignment, shift)],
        grace_minutes=10,
        late_deduction_per_minute=1.0,
        enable_late_overtime_balancing=True,
    )
    assert record.status == AttendanceStatus.complete
    assert slip["attendance_records"][0]["status"] == "complete"
    assert slip["late_minutes"] == 0.0
    assert slip["late_deductions"] == 0.0
    assert monetary_late_minutes(
        time_in=datetime(2026, 8, 4, 8, 8),
        scheduled_start=datetime(2026, 8, 4, 8, 0),
        grace_minutes=10,
    ) == 0.0


def test_grace_late_8_15_five_monetary_minutes():
    shift, assignment = _shift_pair(time(8, 0), time(17, 0))
    record = _record(assignment, _ph(8, 15), _ph(17, 0), status=AttendanceStatus.late)
    slip = _run(
        rows=[(record, assignment, shift)],
        scheduled=[(assignment, shift)],
        grace_minutes=10,
        late_deduction_per_minute=1.0,
    )
    assert slip["attendance_records"][0]["status"] == "late"
    assert slip["late_minutes"] == 5.0
    assert abs(slip["late_deductions"] - 5.0) < 0.01


def test_late_from_start_differs_from_monetary_late_minutes():
    start = datetime(2026, 8, 4, 8, 0)
    time_in = datetime(2026, 8, 4, 8, 30)
    late_from_start = (time_in - start).total_seconds() / 60.0
    monetary = monetary_late_minutes(
        time_in=time_in,
        scheduled_start=start,
        grace_minutes=10,
    )
    assert late_from_start == 30.0
    assert monetary == 20.0
    assert late_from_start != monetary


def test_balancing_45_raw_ot_below_threshold_pays_zero():
    shift, assignment = _shift_pair(time(8, 0), time(17, 0))
    record = _record(assignment, _ph(8, 30), _ph(17, 45), status=AttendanceStatus.late)
    slip = _run(
        rows=[(record, assignment, shift)],
        scheduled=[(assignment, shift)],
        enable_late_overtime_balancing=True,
        grace_minutes=10,
        ot_minimum=30,
        overtime_per_minute=1.0,
        late_deduction_per_minute=1.0,
    )
    ot_mins, recovered = qualifying_overtime_minutes(
        time_in=datetime(2026, 8, 4, 8, 30),
        time_out=datetime(2026, 8, 4, 17, 45),
        scheduled_start=datetime(2026, 8, 4, 8, 0),
        scheduled_end=datetime(2026, 8, 4, 17, 0),
        ot_minimum=30,
        late_ot_balancing=True,
    )
    assert recovered == 30.0
    assert ot_mins == 0.0
    assert slip["overtime_minutes"] == 0.0
    assert slip["overtime_pay"] == 0.0
    assert slip["late_deductions"] == 0.0


def test_balancing_60_raw_ot_exactly_meets_threshold():
    shift, assignment = _shift_pair(time(8, 0), time(17, 0))
    record = _record(assignment, _ph(8, 30), _ph(18, 0), status=AttendanceStatus.late)
    slip = _run(
        rows=[(record, assignment, shift)],
        scheduled=[(assignment, shift)],
        enable_late_overtime_balancing=True,
        grace_minutes=10,
        ot_minimum=30,
        overtime_per_minute=1.0,
        ordinary_ot=25.0,
        late_deduction_per_minute=1.0,
    )
    ot_mins, recovered = qualifying_overtime_minutes(
        time_in=datetime(2026, 8, 4, 8, 30),
        time_out=datetime(2026, 8, 4, 18, 0),
        scheduled_start=datetime(2026, 8, 4, 8, 0),
        scheduled_end=datetime(2026, 8, 4, 17, 0),
        ot_minimum=30,
        late_ot_balancing=True,
    )
    assert recovered == 30.0
    assert ot_mins == 30.0
    assert slip["overtime_minutes"] == 30.0
    assert abs(slip["overtime_pay"] - overtime_pay_amount(30, 1.0, 0.0)) < 0.01
    assert slip["late_deductions"] == 0.0


def test_balancing_75_raw_ot_pays_all_remaining_minutes():
    shift, assignment = _shift_pair(time(8, 0), time(17, 0))
    record = _record(assignment, _ph(8, 30), _ph(18, 15), status=AttendanceStatus.late)
    slip = _run(
        rows=[(record, assignment, shift)],
        scheduled=[(assignment, shift)],
        enable_late_overtime_balancing=True,
        grace_minutes=10,
        ot_minimum=30,
        overtime_per_minute=1.0,
        ordinary_ot=25.0,
        late_deduction_per_minute=1.0,
    )
    ot_mins, recovered = qualifying_overtime_minutes(
        time_in=datetime(2026, 8, 4, 8, 30),
        time_out=datetime(2026, 8, 4, 18, 15),
        scheduled_start=datetime(2026, 8, 4, 8, 0),
        scheduled_end=datetime(2026, 8, 4, 17, 0),
        ot_minimum=30,
        late_ot_balancing=True,
    )
    assert recovered == 30.0
    assert ot_mins == 45.0
    assert slip["overtime_minutes"] == 45.0
    assert abs(slip["overtime_pay"] - overtime_pay_amount(45, 1.0, 0.0)) < 0.01
    assert ot_mins != 45.0 - 30.0


def test_balancing_reduces_monetary_late_deduction():
    shift, assignment = _shift_pair(time(8, 0), time(17, 0))
    record = _record(assignment, _ph(8, 30), _ph(18, 0), status=AttendanceStatus.late)
    slip = _run(
        rows=[(record, assignment, shift)],
        scheduled=[(assignment, shift)],
        enable_late_overtime_balancing=True,
        grace_minutes=10,
        ot_minimum=30,
        overtime_per_minute=1.0,
        late_deduction_per_minute=1.0,
    )
    assert slip["late_minutes"] == 0.0
    assert slip["late_deductions"] == 0.0
    assert slip["overtime_minutes"] == 30.0
    slip_off = _run(
        rows=[
            (
                _record(assignment, _ph(8, 30), _ph(18, 0), status=AttendanceStatus.late),
                assignment,
                shift,
            )
        ],
        scheduled=[(assignment, shift)],
        enable_late_overtime_balancing=False,
        grace_minutes=10,
        ot_minimum=30,
        overtime_per_minute=1.0,
        late_deduction_per_minute=1.0,
    )
    assert abs(slip_off["late_deductions"] - 20.0) < 0.01
    assert slip["late_deductions"] != slip_off["late_deductions"]


def test_late_toggle_off_still_balances_from_scheduled_start():
    shift, assignment = _shift_pair(time(8, 0), time(17, 0))
    record = _record(assignment, _ph(8, 30), _ph(18, 0), status=AttendanceStatus.late)
    slip = _run(
        rows=[(record, assignment, shift)],
        scheduled=[(assignment, shift)],
        enable_late_overtime_balancing=True,
        late_deduction_enabled=False,
        grace_minutes=10,
        ot_minimum=30,
        overtime_per_minute=1.0,
        ordinary_ot=25.0,
        late_deduction_per_minute=1.0,
    )
    assert slip["attendance_records"][0]["status"] == "late"
    assert slip["late_minutes"] == 0.0
    assert slip["late_deductions"] == 0.0
    assert slip["overtime_minutes"] == 30.0
    assert abs(slip["overtime_pay"] - overtime_pay_amount(30, 1.0, 0.0)) < 0.01


def test_cate_ordinary_day_ot_has_no_automatic_premium():
    """Cate Blanchett 2026-09-17 ordinary Thursday: leftover 25% must not apply.

    Stored UTC punches:
      time_in  2026-09-16 17:56:53.268985Z → Manila 01:56:53.268985
      time_out 2026-09-17 01:12:40.238347Z → Manila 09:12:40.238347
    Shift 00:15–08:00. Raw OT ≈ 72.670639 min × ₱1/min. No holiday.
    The previous 25% ordinary premium produced ₱90.84.
    """
    work_date = date(2026, 9, 17)
    shift, assignment = _shift_pair(time(0, 15), time(8, 0), work_date=work_date)
    time_in = datetime(2026, 9, 16, 17, 56, 53, 268985, tzinfo=timezone.utc)
    time_out = datetime(2026, 9, 17, 1, 12, 40, 238347, tzinfo=timezone.utc)
    record = _record(assignment, time_in, time_out, status=AttendanceStatus.late)
    slip = _run(
        daily_rate=730.0,
        rows=[(record, assignment, shift)],
        scheduled=[(assignment, shift)],
        overtime_per_minute=1.0,
        ordinary_ot=25.0,
        rest_day_ot=25.0,
        ot_minimum=30,
        grace_minutes=10,
        enable_late_overtime_balancing=False,
        period_start=date(2026, 8, 31),
        period_end=date(2026, 9, 30),
        today=date(2026, 9, 18),
    )
    raw_ot, _recovered = qualifying_overtime_minutes(
        time_in=datetime(2026, 9, 17, 1, 56, 53, 268985),
        time_out=datetime(2026, 9, 17, 9, 12, 40, 238347),
        scheduled_start=datetime(2026, 9, 17, 0, 15),
        scheduled_end=datetime(2026, 9, 17, 8, 0),
        ot_minimum=30,
        late_ot_balancing=False,
    )
    assert abs(raw_ot - 72.670639) < 1e-5
    assert abs(slip["overtime_minutes"] - 72.67) < 0.01
    assert abs(slip["overtime_pay"] - 72.67) < 0.01
    assert abs(slip["overtime_pay"] - 90.84) > 0.01
    assert overtime_premium_percent(
        SimpleNamespace(
            ordinary_ot_premium_percent=25.0,
            rest_day_ot_premium_percent=25.0,
        ),
        None,
        False,
    ) == 0.0


def test_unpaid_breaktime_hourly_uses_145_paid_minutes():
    shift, assignment = _shift_pair(
        time(13, 0), time(16, 0), break_minutes=35
    )
    record = _record(assignment, _ph(13, 0), _ph(16, 0))
    slip = _run(
        pay_basis=PayBasis.hourly,
        daily_rate=None,
        hourly_rate=100.0,
        rows=[(record, assignment, shift)],
        scheduled=[(assignment, shift)],
        breaktime_is_paid=False,
        overtime_per_minute=1.0,
    )
    assert slip["attendance_records"][0]["scheduled_minutes"] == 145.0
    assert abs(slip["regular_pay"] - 241.67) < 0.01
    assert abs(slip["gross_pay"] - 241.67) < 0.01
    assert slip["overtime_pay"] == 0.0


def test_paid_breaktime_hourly_uses_full_span():
    shift, assignment = _shift_pair(
        time(13, 0), time(16, 0), break_minutes=35
    )
    record = _record(assignment, _ph(13, 0), _ph(16, 0))
    slip = _run(
        pay_basis=PayBasis.hourly,
        daily_rate=None,
        hourly_rate=100.0,
        rows=[(record, assignment, shift)],
        scheduled=[(assignment, shift)],
        breaktime_is_paid=True,
        overtime_per_minute=1.0,
    )
    assert slip["attendance_records"][0]["scheduled_minutes"] == 180.0
    assert abs(slip["regular_pay"] - 300.0) < 0.01
    assert abs(slip["gross_pay"] - 300.0) < 0.01


def test_unpaid_break_does_not_move_ot_boundary():
    shift, assignment = _shift_pair(
        time(13, 0), time(16, 0), break_minutes=35
    )
    record = _record(assignment, _ph(13, 0), _ph(16, 30))
    slip = _run(
        pay_basis=PayBasis.hourly,
        daily_rate=None,
        hourly_rate=100.0,
        rows=[(record, assignment, shift)],
        scheduled=[(assignment, shift)],
        breaktime_is_paid=False,
        overtime_per_minute=1.0,
        ot_minimum=30,
    )
    assert slip["overtime_minutes"] == 30.0
    assert abs(slip["overtime_pay"] - 30.0) < 0.01
    assert abs(slip["overtime_pay"] - overtime_pay_amount(0, 1.0, 0.0)) > 0.01


def test_open_punch_is_pending_and_pays_zero():
    """Paula-style open late punch must not finalize ₱241.67 from scheduled hours."""
    work_date = date(2026, 9, 17)
    shift, assignment = _shift_pair(
        time(13, 0), time(16, 0), break_minutes=35, work_date=work_date
    )
    time_in = datetime(2026, 9, 17, 5, 22, 32, 520204, tzinfo=timezone.utc)
    record = _record(assignment, time_in, None, status=AttendanceStatus.late)
    slip = _run(
        pay_basis=PayBasis.hourly,
        daily_rate=None,
        hourly_rate=100.0,
        rows=[(record, assignment, shift)],
        scheduled=[(assignment, shift)],
        overtime_per_minute=1.0,
        late_deduction_per_minute=1.0,
        grace_minutes=10,
        breaktime_is_paid=False,
        period_start=date(2026, 8, 31),
        period_end=date(2026, 9, 30),
        today=date(2026, 9, 17),
    )
    assert slip["pending_attendance_count"] == 1
    assert slip["attendance_records"][0]["payroll_status"] == "pending"
    assert slip["worked_days"] == 0.0
    assert slip["hours_worked"] == 0.0
    assert slip["regular_pay"] == 0.0
    assert slip["gross_pay"] == 0.0
    assert slip["late_deductions"] == 0.0
    assert slip["overtime_pay"] == 0.0
    assert abs(slip["gross_pay"] - 241.67) > 0.01


def test_incomplete_open_punch_pays_zero():
    shift, assignment = _shift_pair(time(13, 0), time(16, 0), break_minutes=35)
    record = _record(
        assignment, _ph(13, 22), None, status=AttendanceStatus.incomplete
    )
    slip = _run(
        pay_basis=PayBasis.hourly,
        daily_rate=None,
        hourly_rate=100.0,
        rows=[(record, assignment, shift)],
        scheduled=[(assignment, shift)],
        breaktime_is_paid=False,
    )
    assert slip["gross_pay"] == 0.0
    assert slip["late_deductions"] == 0.0
    assert slip["attendance_records"][0]["payroll_status"] == (
        "pending_attendance_correction"
    )


def test_ot_threshold_is_qualification_not_subtraction():
    shift, assignment = _shift_pair(time(8, 0), time(16, 0))
    below = _run(
        rows=[(_record(assignment, _ph(8, 0), _ph(16, 20)), assignment, shift)],
        scheduled=[(assignment, shift)],
        overtime_per_minute=1.0,
        ot_minimum=30,
    )
    exact = _run(
        rows=[(_record(assignment, _ph(8, 0), _ph(16, 30)), assignment, shift)],
        scheduled=[(assignment, shift)],
        overtime_per_minute=1.0,
        ot_minimum=30,
    )
    above = _run(
        rows=[(_record(assignment, _ph(8, 0), _ph(16, 45)), assignment, shift)],
        scheduled=[(assignment, shift)],
        overtime_per_minute=1.0,
        ot_minimum=30,
    )
    assert below["overtime_minutes"] == 0.0
    assert below["overtime_pay"] == 0.0
    assert exact["overtime_minutes"] == 30.0
    assert abs(exact["overtime_pay"] - 30.0) < 0.01
    assert above["overtime_minutes"] == 45.0
    assert abs(above["overtime_pay"] - 45.0) < 0.01


def test_balancing_20_late_50_raw_ot_pays_30_and_clears_late():
    shift, assignment = _shift_pair(time(8, 0), time(17, 0))
    record = _record(assignment, _ph(8, 20), _ph(17, 50), status=AttendanceStatus.late)
    slip = _run(
        rows=[(record, assignment, shift)],
        scheduled=[(assignment, shift)],
        enable_late_overtime_balancing=True,
        grace_minutes=0,
        ot_minimum=30,
        overtime_per_minute=1.0,
        late_deduction_per_minute=1.0,
        ordinary_ot=25.0,
    )
    assert slip["overtime_minutes"] == 30.0
    assert abs(slip["overtime_pay"] - 30.0) < 0.01
    assert slip["late_deductions"] == 0.0


def test_daily_undertime_uses_scheduled_paid_minutes_not_span():
    shift, assignment = _shift_pair(time(13, 0), time(16, 0), break_minutes=35)
    record = _record(assignment, _ph(13, 0), _ph(15, 0))
    slip = _run(
        daily_rate=730.0,
        rows=[(record, assignment, shift)],
        scheduled=[(assignment, shift)],
        breaktime_is_paid=False,
    )
    expected = 60.0 * (730.0 / 145.0)
    span_rate = 60.0 * (730.0 / 180.0)
    assert abs(slip["undertime_minutes"] - 60.0) < 0.01
    assert abs(slip["undertime_deductions"] - expected) < 0.01
    assert abs(slip["undertime_deductions"] - span_rate) > 0.01


def test_same_day_unresolved_afternoon_keeps_day_pending():
    work_date = date(2026, 8, 4)
    morning, morning_asg = _shift_pair(
        time(0, 15), time(8, 0), name="early morning", work_date=work_date
    )
    afternoon, afternoon_asg = _shift_pair(
        time(13, 0), time(16, 0), name="afternoon", break_minutes=35, work_date=work_date
    )
    morning_rec = _record(
        morning_asg, _ph(1, 56), _ph(9, 12), status=AttendanceStatus.late
    )
    slip = _run(
        daily_rate=730.0,
        rows=[(morning_rec, morning_asg, morning)],
        scheduled=[(morning_asg, morning), (afternoon_asg, afternoon)],
        today=date(2026, 8, 4),
        now=datetime(2026, 8, 4, 12, 0),
        clock_out_deadline_passed=None,
        breaktime_is_paid=False,
    )
    assert slip["pending_work_dates"] == ["2026-08-04"]
    assert slip["pending_attendance_count"] == 1
    assert slip["worked_days"] == 0.0
    assert slip["regular_pay"] == 0.0
    assert slip["gross_pay"] == 0.0
    assert slip["late_deductions"] == 0.0
    assert slip["overtime_pay"] == 0.0
    assert slip["hours_worked"] == 0.0
    assert slip["attendance_records"][0]["payroll_status"] == "pending"


def test_same_day_both_shifts_completed_credits_daily_rate_once():
    work_date = date(2026, 8, 4)
    morning, morning_asg = _shift_pair(
        time(0, 15), time(8, 0), name="early morning", work_date=work_date
    )
    afternoon, afternoon_asg = _shift_pair(
        time(13, 0), time(16, 0), name="afternoon", break_minutes=35, work_date=work_date
    )
    morning_rec = _record(morning_asg, _ph(0, 15), _ph(8, 0))
    afternoon_rec = _record(afternoon_asg, _ph(13, 0), _ph(16, 0))
    slip = _run(
        daily_rate=730.0,
        rows=[
            (morning_rec, morning_asg, morning),
            (afternoon_rec, afternoon_asg, afternoon),
        ],
        scheduled=[(morning_asg, morning), (afternoon_asg, afternoon)],
        today=date(2026, 8, 4),
        now=datetime(2026, 8, 4, 18, 0),
        clock_out_deadline_passed=None,
        breaktime_is_paid=False,
    )
    assert slip["pending_work_dates"] == []
    assert slip["pending_attendance_count"] == 0
    assert slip["worked_days"] == 1.0
    assert abs(slip["regular_pay"] - 730.0) < 0.01
    assert abs(slip["gross_pay"] - 730.0) < 0.01
    assert abs(slip["hours_worked"] - 10.17) < 0.01
    assert all(
        row["payroll_status"] == "finalized" for row in slip["attendance_records"]
    )


def test_same_day_second_shift_absent_resolves_day_without_duplicate_rate():
    work_date = date(2026, 8, 4)
    morning, morning_asg = _shift_pair(
        time(0, 15), time(8, 0), name="early morning", work_date=work_date
    )
    afternoon, afternoon_asg = _shift_pair(
        time(13, 0), time(16, 0), name="afternoon", work_date=work_date
    )
    morning_rec = _record(morning_asg, _ph(0, 15), _ph(8, 0))
    afternoon_rec = _record(afternoon_asg, None, None, status=AttendanceStatus.absent)
    slip = _run(
        daily_rate=730.0,
        rows=[
            (morning_rec, morning_asg, morning),
            (afternoon_rec, afternoon_asg, afternoon),
        ],
        scheduled=[(morning_asg, morning), (afternoon_asg, afternoon)],
        today=date(2026, 8, 5),
        clock_out_deadline_passed=True,
    )
    assert slip["pending_work_dates"] == []
    assert slip["worked_days"] == 1.0
    assert abs(slip["regular_pay"] - 730.0) < 0.01
    assert slip["absent_days"] == 1


def test_same_day_second_shift_incomplete_resolves_day():
    work_date = date(2026, 8, 4)
    morning, morning_asg = _shift_pair(
        time(0, 15), time(8, 0), name="early morning", work_date=work_date
    )
    afternoon, afternoon_asg = _shift_pair(
        time(13, 0), time(16, 0), name="afternoon", work_date=work_date
    )
    morning_rec = _record(morning_asg, _ph(0, 15), _ph(8, 0))
    afternoon_rec = _record(
        afternoon_asg, _ph(13, 0), None, status=AttendanceStatus.incomplete
    )
    slip = _run(
        daily_rate=730.0,
        rows=[
            (morning_rec, morning_asg, morning),
            (afternoon_rec, afternoon_asg, afternoon),
        ],
        scheduled=[(morning_asg, morning), (afternoon_asg, afternoon)],
        today=date(2026, 8, 5),
    )
    assert slip["pending_work_dates"] == []
    assert slip["worked_days"] == 1.0
    assert abs(slip["regular_pay"] - 730.0) < 0.01
    statuses = {row["shift_name"]: row["payroll_status"] for row in slip["attendance_records"]}
    assert statuses["afternoon"] == "pending_attendance_correction"


def test_same_day_open_afternoon_punch_keeps_day_pending():
    work_date = date(2026, 8, 4)
    morning, morning_asg = _shift_pair(
        time(0, 15), time(8, 0), name="early morning", work_date=work_date
    )
    afternoon, afternoon_asg = _shift_pair(
        time(13, 0), time(16, 0), name="afternoon", work_date=work_date
    )
    morning_rec = _record(morning_asg, _ph(0, 15), _ph(8, 0))
    afternoon_rec = _record(
        afternoon_asg, _ph(13, 5), None, status=AttendanceStatus.late
    )
    slip = _run(
        daily_rate=730.0,
        rows=[
            (morning_rec, morning_asg, morning),
            (afternoon_rec, afternoon_asg, afternoon),
        ],
        scheduled=[(morning_asg, morning), (afternoon_asg, afternoon)],
        today=date(2026, 8, 4),
        now=datetime(2026, 8, 4, 15, 0),
        clock_out_deadline_passed=None,
    )
    assert slip["pending_work_dates"] == ["2026-08-04"]
    assert slip["regular_pay"] == 0.0
    assert slip["gross_pay"] == 0.0
    assert slip["hours_worked"] == 0.0


def test_single_shift_completed_day_unchanged():
    shift, assignment = _shift_pair(time(8, 0), time(16, 0))
    record = _record(assignment, _ph(8, 0), _ph(16, 0))
    slip = _run(
        daily_rate=730.0,
        rows=[(record, assignment, shift)],
        scheduled=[(assignment, shift)],
    )
    assert slip["pending_work_dates"] == []
    assert slip["worked_days"] == 1.0
    assert abs(slip["regular_pay"] - 730.0) < 0.01
    assert slip["hours_worked"] == 8.0


def test_same_day_gate_preserves_unpaid_break_and_ot_boundary():
    work_date = date(2026, 8, 4)
    morning, morning_asg = _shift_pair(
        time(0, 15), time(8, 0), name="early morning", work_date=work_date
    )
    afternoon, afternoon_asg = _shift_pair(
        time(13, 0), time(16, 0), name="afternoon", break_minutes=35, work_date=work_date
    )
    morning_rec = _record(morning_asg, _ph(0, 15), _ph(8, 0))
    afternoon_rec = _record(afternoon_asg, _ph(13, 0), _ph(16, 30))
    slip = _run(
        daily_rate=730.0,
        rows=[
            (morning_rec, morning_asg, morning),
            (afternoon_rec, afternoon_asg, afternoon),
        ],
        scheduled=[(morning_asg, morning), (afternoon_asg, afternoon)],
        overtime_per_minute=1.0,
        ot_minimum=30,
        today=date(2026, 8, 4),
        now=datetime(2026, 8, 4, 18, 0),
        clock_out_deadline_passed=None,
        breaktime_is_paid=False,
    )
    by_shift = {row["shift_name"]: row for row in slip["attendance_records"]}
    assert by_shift["afternoon"]["scheduled_minutes"] == 145.0
    assert abs(slip["hours_worked"] - 10.17) < 0.01
    assert slip["overtime_minutes"] == 30.0
    assert abs(slip["overtime_pay"] - 30.0) < 0.01
    assert abs(slip["regular_pay"] - 730.0) < 0.01


def test_overnight_assignment_gate_uses_work_date_and_end_next_day():
    work_date = date(2026, 8, 4)
    overnight, overnight_asg = _shift_pair(
        time(22, 0), time(6, 0), name="overnight", work_date=work_date
    )
    day, day_asg = _shift_pair(
        time(8, 0), time(12, 0), name="morning", work_date=work_date
    )
    day_rec = _record(day_asg, _ph(8, 0), _ph(12, 0))
    slip = _run(
        daily_rate=730.0,
        rows=[(day_rec, day_asg, day)],
        scheduled=[(day_asg, day), (overnight_asg, overnight)],
        today=date(2026, 8, 4),
        now=datetime(2026, 8, 4, 15, 0),
        clock_out_deadline_passed=None,
    )
    assert is_scheduled_assignment_resolved(
        now_local=datetime(2026, 8, 4, 15, 0),
        today=date(2026, 8, 4),
        work_date=work_date,
        scheduled_end=datetime(2026, 8, 5, 6, 0),
        grace_minutes=10,
        records=[],
    ) is False
    assert slip["pending_work_dates"] == ["2026-08-04"]
    assert slip["regular_pay"] == 0.0

    overnight_rec = _record(overnight_asg, _ph(22, 0), _ph(6, 0, day=5))
    resolved = _run(
        daily_rate=730.0,
        rows=[
            (day_rec, day_asg, day),
            (overnight_rec, overnight_asg, overnight),
        ],
        scheduled=[(day_asg, day), (overnight_asg, overnight)],
        today=date(2026, 8, 5),
        now=datetime(2026, 8, 5, 8, 0),
        clock_out_deadline_passed=None,
    )
    assert resolved["pending_work_dates"] == []
    assert resolved["worked_days"] == 1.0
    assert abs(resolved["regular_pay"] - 730.0) < 0.01


def test_remaining_monetary_late_minutes_balances_after_grace():
    assert abs(
        remaining_monetary_late_minutes(
            monetary_late=101.89,
            recovered_late_minutes=72.67,
            late_ot_balancing=True,
        )
        - 29.22
    ) < 0.01
    assert remaining_monetary_late_minutes(
        monetary_late=20.0,
        recovered_late_minutes=30.0,
        late_ot_balancing=True,
    ) == 0.0
    assert remaining_monetary_late_minutes(
        monetary_late=30.0,
        recovered_late_minutes=20.0,
        late_ot_balancing=True,
    ) == 10.0
    assert remaining_monetary_late_minutes(
        monetary_late=30.0,
        recovered_late_minutes=30.0,
        late_ot_balancing=True,
    ) == 0.0
    assert remaining_monetary_late_minutes(
        monetary_late=20.0,
        recovered_late_minutes=0.0,
        late_ot_balancing=True,
    ) == 20.0
    assert remaining_monetary_late_minutes(
        monetary_late=20.0,
        recovered_late_minutes=50.0,
        late_ot_balancing=False,
    ) == 20.0


def test_cate_morning_ot_balances_late_to_29_22():
    work_date = date(2026, 9, 17)
    shift, assignment = _shift_pair(time(0, 15), time(8, 0), work_date=work_date)
    time_in = datetime(2026, 9, 16, 17, 56, 53, 268985, tzinfo=timezone.utc)
    time_out = datetime(2026, 9, 17, 1, 12, 40, 238347, tzinfo=timezone.utc)
    record = _record(assignment, time_in, time_out, status=AttendanceStatus.late)
    slip = _run(
        daily_rate=730.0,
        rows=[(record, assignment, shift)],
        scheduled=[(assignment, shift)],
        overtime_per_minute=1.0,
        late_deduction_per_minute=1.0,
        ot_minimum=30,
        grace_minutes=0,
        enable_late_overtime_balancing=True,
        period_start=date(2026, 8, 31),
        period_end=date(2026, 9, 30),
        today=date(2026, 9, 18),
    )
    assert slip["overtime_minutes"] == 0.0
    assert slip["overtime_pay"] == 0.0
    assert abs(slip["late_minutes"] - 29.22) < 0.01
    assert abs(slip["late_deductions"] - 29.22) < 0.01


def test_ot_completely_offsets_late_then_threshold_applies():
    shift, assignment = _shift_pair(time(8, 0), time(17, 0))
    record = _record(assignment, _ph(8, 20), _ph(17, 30), status=AttendanceStatus.late)
    slip = _run(
        rows=[(record, assignment, shift)],
        scheduled=[(assignment, shift)],
        enable_late_overtime_balancing=True,
        grace_minutes=0,
        ot_minimum=30,
        late_deduction_per_minute=1.0,
        overtime_per_minute=1.0,
    )
    assert slip["late_deductions"] == 0.0
    assert slip["overtime_minutes"] == 0.0
    assert slip["overtime_pay"] == 0.0


def test_late_completely_offsets_ot_remaining_late_is_charged():
    shift, assignment = _shift_pair(time(8, 0), time(17, 0))
    record = _record(assignment, _ph(8, 30), _ph(17, 20), status=AttendanceStatus.late)
    slip = _run(
        rows=[(record, assignment, shift)],
        scheduled=[(assignment, shift)],
        enable_late_overtime_balancing=True,
        grace_minutes=0,
        ot_minimum=30,
        late_deduction_per_minute=1.0,
        overtime_per_minute=1.0,
    )
    assert slip["overtime_minutes"] == 0.0
    assert slip["overtime_pay"] == 0.0
    assert abs(slip["late_minutes"] - 10.0) < 0.01
    assert abs(slip["late_deductions"] - 10.0) < 0.01


def test_equal_late_and_ot_zero_both_sides():
    shift, assignment = _shift_pair(time(8, 0), time(17, 0))
    record = _record(assignment, _ph(8, 30), _ph(17, 30), status=AttendanceStatus.late)
    slip = _run(
        rows=[(record, assignment, shift)],
        scheduled=[(assignment, shift)],
        enable_late_overtime_balancing=True,
        grace_minutes=0,
        ot_minimum=30,
        late_deduction_per_minute=1.0,
        overtime_per_minute=1.0,
    )
    assert slip["late_deductions"] == 0.0
    assert slip["overtime_minutes"] == 0.0
    assert slip["overtime_pay"] == 0.0


def test_ot_below_threshold_after_balancing_clears_late():
    shift, assignment = _shift_pair(time(8, 0), time(17, 0))
    record = _record(assignment, _ph(8, 20), _ph(17, 40), status=AttendanceStatus.late)
    slip = _run(
        rows=[(record, assignment, shift)],
        scheduled=[(assignment, shift)],
        enable_late_overtime_balancing=True,
        grace_minutes=0,
        ot_minimum=30,
        late_deduction_per_minute=1.0,
        overtime_per_minute=1.0,
    )
    assert slip["overtime_minutes"] == 0.0
    assert slip["overtime_hours"] == 0.0
    assert slip["overtime_pay"] == 0.0
    assert slip["late_deductions"] == 0.0


def test_ot_exactly_threshold_after_balancing_pays_ot_clears_late():
    shift, assignment = _shift_pair(time(8, 0), time(17, 0))
    record = _record(assignment, _ph(8, 20), _ph(17, 50), status=AttendanceStatus.late)
    slip = _run(
        rows=[(record, assignment, shift)],
        scheduled=[(assignment, shift)],
        enable_late_overtime_balancing=True,
        grace_minutes=0,
        ot_minimum=30,
        late_deduction_per_minute=1.0,
        overtime_per_minute=1.0,
        ordinary_ot=0.0,
    )
    assert slip["overtime_minutes"] == 30.0
    assert abs(slip["overtime_hours"] - 0.5) < 0.01
    assert abs(slip["overtime_pay"] - 30.0) < 0.01
    assert slip["late_deductions"] == 0.0


def test_grace_then_balancing_within_grace_stays_zero_late():
    shift, assignment = _shift_pair(time(8, 0), time(17, 0))
    record = _record(assignment, _ph(8, 8), _ph(17, 40))
    slip = _run(
        rows=[(record, assignment, shift)],
        scheduled=[(assignment, shift)],
        enable_late_overtime_balancing=True,
        grace_minutes=10,
        ot_minimum=30,
        late_deduction_per_minute=1.0,
        overtime_per_minute=1.0,
    )
    assert slip["late_minutes"] == 0.0
    assert slip["late_deductions"] == 0.0
    # Late-from-start 8 still recovers 8 OT minutes (40 - 8 = 32 payable).
    assert slip["overtime_minutes"] == 32.0


def test_no_ot_leaves_monetary_late_unchanged():
    shift, assignment = _shift_pair(time(8, 0), time(17, 0))
    record = _record(assignment, _ph(8, 20), _ph(17, 0), status=AttendanceStatus.late)
    slip = _run(
        rows=[(record, assignment, shift)],
        scheduled=[(assignment, shift)],
        enable_late_overtime_balancing=True,
        grace_minutes=0,
        ot_minimum=30,
        late_deduction_per_minute=1.0,
        overtime_per_minute=1.0,
    )
    assert slip["overtime_minutes"] == 0.0
    assert slip["overtime_hours"] == 0.0
    assert abs(slip["late_minutes"] - 20.0) < 0.01


def test_cate_two_shift_day_morning_balances_afternoon_ot_independent():
    work_date = date(2026, 9, 17)
    morning, morning_asg = _shift_pair(
        time(0, 15), time(8, 0), name="morning", work_date=work_date
    )
    afternoon, afternoon_asg = _shift_pair(
        time(13, 0),
        time(16, 0),
        name="afternoon",
        break_minutes=35,
        work_date=work_date,
    )
    morning_rec = _record(
        morning_asg,
        datetime(2026, 9, 16, 17, 56, 53, 268985, tzinfo=timezone.utc),
        datetime(2026, 9, 17, 1, 12, 40, 238347, tzinfo=timezone.utc),
        status=AttendanceStatus.late,
    )
    afternoon_rec = _record(
        afternoon_asg,
        datetime(2026, 9, 17, 5, 0, tzinfo=timezone.utc),
        datetime(2026, 9, 17, 8, 30, 28, 800000, tzinfo=timezone.utc),
    )
    slip = _run(
        daily_rate=730.0,
        rows=[
            (morning_rec, morning_asg, morning),
            (afternoon_rec, afternoon_asg, afternoon),
        ],
        scheduled=[(morning_asg, morning), (afternoon_asg, afternoon)],
        overtime_per_minute=1.0,
        late_deduction_per_minute=1.0,
        ot_minimum=30,
        grace_minutes=0,
        enable_late_overtime_balancing=True,
        breaktime_is_paid=False,
        period_start=date(2026, 8, 31),
        period_end=date(2026, 9, 30),
        today=date(2026, 9, 18),
    )
    by_shift = {row["shift_name"]: row for row in slip["attendance_records"]}
    assert abs(by_shift["morning"]["late_deduction"] - 29.22) < 0.01
    assert by_shift["morning"]["late_minutes"] == 29.22 or abs(
        by_shift["morning"]["late_minutes"] - 29.22
    ) < 0.01
    assert by_shift["afternoon"]["late_deduction"] == 0.0
    assert abs(slip["overtime_minutes"] - 30.48) < 0.01
    assert abs(slip["overtime_hours"] - 0.51) < 0.01
    assert abs(slip["overtime_pay"] - 30.48) < 0.01
    assert abs(slip["regular_pay"] - 730.0) < 0.01
    assert abs(slip["gross_pay"] - 760.48) < 0.01
    assert abs(slip["late_deductions"] - 29.22) < 0.01
    assert abs(slip["net_pay"] - 731.26) < 0.01


def test_holiday_ot_premium_unchanged_when_late_is_balanced():
    work_date = date(2026, 8, 4)
    shift, assignment = _shift_pair(time(8, 0), time(16, 0), work_date=work_date)
    holiday = Holiday(
        id=uuid4(),
        business_id=uuid4(),
        name="Special",
        holiday_date=work_date,
        holiday_type=HolidayType.special_non_working,
        is_paid=True,
        pay_multiplier=1.3,
        ot_premium_percent=30.0,
        is_active=True,
    )
    record = _record(assignment, _ph(8, 20), _ph(17, 0), status=AttendanceStatus.late)
    slip = _run(
        pay_basis=PayBasis.hourly,
        daily_rate=None,
        hourly_rate=60.0,
        rows=[(record, assignment, shift)],
        scheduled=[(assignment, shift)],
        holidays=[holiday],
        enable_late_overtime_balancing=True,
        grace_minutes=0,
        ot_minimum=30,
        overtime_per_minute=1.0,
        late_deduction_per_minute=1.0,
    )
    expected_ot = overtime_pay_amount(40, 1.0, 30.0)
    assert abs(slip["overtime_minutes"] - 40.0) < 0.01
    assert abs(slip["overtime_pay"] - expected_ot) < 0.01
    assert slip["late_deductions"] == 0.0
    assert overtime_premium_percent(None, holiday, False) == 30.0
    assert overtime_premium_percent(None, None, True) == 0.0
