"""Option 2 paid leave: scheduled-shift leave pay as a separate payslip field."""

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
from app.models.enums import AttendanceStatus, EmploymentType, PayBasis, PayrollRunStatus
from app.models.holiday import Holiday
from app.models.payroll import BusinessPayrollConfig, Position
from app.models.rest_day_policy import BusinessRestDayPolicy
from app.models.scheduling import Shift, ShiftAssignment
from app.services.payroll_snapshot import (
    freeze_payslip_dict,
    load_period_payslip,
    mark_payroll_run_unfinalized,
)
from tests.test_payroll_snapshot_retrieval import FakeDB, _employee, _row, _run as _snapshot_run


def _ph(hour: int, minute: int = 0, day: int = 19) -> datetime:
    utc_hour = hour - 8
    utc_day = day
    if utc_hour < 0:
        utc_hour += 24
        utc_day = day - 1
    return datetime(2026, 9, utc_day, utc_hour, minute, tzinfo=timezone.utc)


def _shift(
    *,
    start: time,
    end: time,
    name="Shift",
    break_minutes: int = 0,
    work_date: date | None = None,
):
    shift = Shift(
        id=uuid4(),
        business_id=uuid4(),
        name=name,
        start_time=start,
        end_time=end,
        break_minutes=break_minutes,
    )
    assignment = ShiftAssignment(
        id=uuid4(),
        shift_id=shift.id,
        employee_id=uuid4(),
        work_date=work_date or date(2026, 9, 19),
        is_rest_day_work=False,
    )
    return shift, assignment


def _on_leave_record(assignment):
    return AttendanceRecord(
        id=uuid4(),
        business_id=uuid4(),
        employee_id=assignment.employee_id,
        shift_assignment_id=assignment.id,
        time_in=None,
        time_out=None,
        status=AttendanceStatus.on_leave,
    )


def _complete_record(assignment, time_in, time_out):
    return AttendanceRecord(
        id=uuid4(),
        business_id=uuid4(),
        employee_id=assignment.employee_id,
        shift_assignment_id=assignment.id,
        time_in=time_in,
        time_out=time_out,
        status=AttendanceStatus.complete,
    )


def _run(
    *,
    pay_basis: PayBasis = PayBasis.hourly,
    daily_rate: float | None = None,
    hourly_rate: float | None = 100.0,
    attendance_rows=None,
    scheduled=None,
    leave_dates=None,
    leave_paid: bool | None = True,
    breaktime_is_paid: bool = False,
    period_start: date = date(2026, 8, 31),
    period_end: date = date(2026, 9, 30),
    today: date = date(2026, 9, 21),
    rest_premium: float | None = 10.0,
):
    business_id = uuid4()
    employee = SimpleNamespace(
        id=uuid4(),
        business_id=business_id,
        full_name="Leave Pay Emp",
        position_title="Chef",
        position_id=uuid4(),
        employment_type=EmploymentType.full_time,
        pay_basis=pay_basis,
        daily_rate=daily_rate,
        hourly_rate=hourly_rate,
        monthly_salary=None,
    )
    position = SimpleNamespace(daily_rate=daily_rate or 730.0, hourly_rate=hourly_rate)
    business = SimpleNamespace(timezone="Asia/Manila")
    att_policy = SimpleNamespace(
        business_id=business_id,
        on_time_grace_minutes=10,
        overtime_minimum_minutes=30,
        half_day_threshold_minutes=240,
        overtime_enabled=True,
        breaktime_is_paid=breaktime_is_paid,
    )
    config = SimpleNamespace(
        overtime_per_minute=1.0,
        late_deduction_per_minute=1.0,
        late_deduction_enabled=True,
        overtime_enabled=True,
        enable_late_overtime_balancing=False,
        holiday_rules_mode=None,
    )
    rest_policy = (
        SimpleNamespace(
            weekly_rest_day="sunday",
            rest_day_premium_percent=rest_premium,
            work_on_rest_day_allowed=True,
        )
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
        attendance_rows or []
    )
    scheduled_query = MagicMock()
    scheduled_query.join.return_value.filter.return_value.all.return_value = (
        scheduled or []
    )
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
    dates = list(leave_dates or [])
    with ExitStack() as stack:
        stack.enter_context(patch("app.api.owner_reports.ensure_incomplete_for_employee"))
        stack.enter_context(
            patch(
                "app.api.owner_reports.employee_on_approved_leave",
                return_value=bool(dates),
            )
        )
        stack.enter_context(
            patch(
                "app.api.owner_reports.approved_leave_dates_for_employee",
                return_value=dates,
            )
        )
        stack.enter_context(
            patch(
                "app.api.owner_reports.leave_is_paid_for_attendance_day",
                return_value=leave_paid,
            )
        )
        stack.enter_context(patch("app.api.owner_reports.business_today", return_value=today))
        stack.enter_context(
            patch(
                "app.api.owner_reports.business_now",
                return_value=datetime(today.year, today.month, today.day, 12, 0),
            )
        )
        stack.enter_context(
            patch(
                "app.api.owner_reports.resolve_holiday_rules_mode",
                return_value="philippine_labor",
            )
        )
        stack.enter_context(
            patch("app.api.owner_reports.is_past_clock_out_deadline", return_value=True)
        )
        return _calculate_employee_payslip(db, employee, period_start, period_end)


def _assert_no_double_count(slip):
    assert abs(
        slip["gross_pay"]
        - (
            slip["regular_pay"]
            + slip["leave_pay"]
            + slip["overtime_pay"]
            + slip["holiday_pay"]
            + slip["rest_day_pay"]
        )
    ) < 0.01


def test_hourly_paid_leave_with_scheduled_shift_uses_paid_minutes():
    shift, assignment = _shift(start=time(16, 0), end=time(20, 30))
    slip = _run(
        attendance_rows=[(_on_leave_record(assignment), assignment, shift)],
        scheduled=[(assignment, shift)],
        leave_dates=[date(2026, 9, 19)],
    )
    assert slip["leave_pay"] == 450.0
    assert slip["regular_pay"] == 0.0
    assert slip["paid_leave_days"] == 1
    assert slip["gross_pay"] == 450.0
    _assert_no_double_count(slip)


def test_hourly_paid_leave_without_scheduled_shift_is_zero():
    slip = _run(
        scheduled=[],
        attendance_rows=[],
        leave_dates=[date(2026, 9, 19)],
    )
    assert slip["leave_pay"] == 0.0
    assert slip["regular_pay"] == 0.0
    assert slip["paid_leave_days"] == 0
    assert slip["gross_pay"] == 0.0
    assert slip["hours_worked"] == 0.0
    leave_rows = [row for row in slip["attendance_records"] if row["status"] == "on_leave"]
    assert leave_rows == []


def test_hourly_paid_leave_on_sunday_without_shift_is_zero():
    sunday = date(2026, 9, 20)
    assert sunday.weekday() == 6
    slip = _run(
        scheduled=[],
        attendance_rows=[],
        leave_dates=[sunday],
    )
    assert slip["leave_pay"] == 0.0
    assert slip["paid_leave_days"] == 0
    assert slip["rest_day_pay"] == 0.0


def test_daily_paid_leave_with_scheduled_shift_uses_daily_rate():
    shift, assignment = _shift(start=time(16, 0), end=time(20, 30))
    slip = _run(
        pay_basis=PayBasis.daily,
        daily_rate=850.0,
        hourly_rate=None,
        attendance_rows=[(_on_leave_record(assignment), assignment, shift)],
        scheduled=[(assignment, shift)],
        leave_dates=[date(2026, 9, 19)],
    )
    assert slip["leave_pay"] == 850.0
    assert slip["regular_pay"] == 0.0
    assert slip["paid_leave_days"] == 1
    assert slip["gross_pay"] == 850.0
    _assert_no_double_count(slip)


def test_daily_paid_leave_without_scheduled_shift_is_zero():
    slip = _run(
        pay_basis=PayBasis.daily,
        daily_rate=850.0,
        hourly_rate=None,
        scheduled=[],
        attendance_rows=[],
        leave_dates=[date(2026, 9, 19)],
    )
    assert slip["leave_pay"] == 0.0
    assert slip["regular_pay"] == 0.0
    assert slip["paid_leave_days"] == 0
    assert slip["gross_pay"] == 0.0


def test_unpaid_leave_with_schedule_has_zero_leave_pay():
    shift, assignment = _shift(start=time(16, 0), end=time(20, 30))
    slip = _run(
        attendance_rows=[(_on_leave_record(assignment), assignment, shift)],
        scheduled=[(assignment, shift)],
        leave_dates=[date(2026, 9, 19)],
        leave_paid=False,
    )
    assert slip["leave_pay"] == 0.0
    assert slip["paid_leave_days"] == 0
    assert slip["unpaid_leave_days"] == 1
    assert slip["gross_pay"] == 0.0


def test_rejected_leave_is_not_in_payroll():
    shift, assignment = _shift(start=time(16, 0), end=time(20, 30))
    slip = _run(
        scheduled=[(assignment, shift)],
        attendance_rows=[],
        leave_dates=[],
        leave_paid=True,
    )
    assert slip["leave_pay"] == 0.0
    assert slip["paid_leave_days"] == 0


def test_hourly_leave_unpaid_break_uses_scheduled_paid_minutes():
    shift, assignment = _shift(
        start=time(16, 0), end=time(21, 0), break_minutes=30
    )
    slip = _run(
        attendance_rows=[(_on_leave_record(assignment), assignment, shift)],
        scheduled=[(assignment, shift)],
        leave_dates=[date(2026, 9, 19)],
        breaktime_is_paid=False,
    )
    assert slip["leave_pay"] == 450.0
    assert slip["paid_leave_days"] == 1


def test_hourly_leave_paid_break_uses_scheduled_paid_minutes():
    shift, assignment = _shift(
        start=time(16, 0), end=time(21, 0), break_minutes=30
    )
    slip = _run(
        attendance_rows=[(_on_leave_record(assignment), assignment, shift)],
        scheduled=[(assignment, shift)],
        leave_dates=[date(2026, 9, 19)],
        breaktime_is_paid=True,
    )
    assert slip["leave_pay"] == 500.0
    assert slip["paid_leave_days"] == 1


def test_hourly_multiple_assignments_same_leave_date_sum_hours_once():
    morning, morning_asg = _shift(start=time(8, 0), end=time(12, 0), name="AM")
    evening, evening_asg = _shift(start=time(13, 0), end=time(17, 0), name="PM")
    slip = _run(
        scheduled=[(morning_asg, morning), (evening_asg, evening)],
        attendance_rows=[],
        leave_dates=[date(2026, 9, 19)],
    )
    assert slip["leave_pay"] == 800.0
    assert slip["paid_leave_days"] == 1
    assert slip["regular_pay"] == 0.0
    _assert_no_double_count(slip)


def test_daily_multiple_assignments_same_leave_date_one_daily_rate():
    morning, morning_asg = _shift(start=time(8, 0), end=time(12, 0), name="AM")
    evening, evening_asg = _shift(start=time(13, 0), end=time(17, 0), name="PM")
    slip = _run(
        pay_basis=PayBasis.daily,
        daily_rate=850.0,
        hourly_rate=None,
        attendance_rows=[
            (_on_leave_record(morning_asg), morning_asg, morning),
            (_on_leave_record(evening_asg), evening_asg, evening),
        ],
        scheduled=[(morning_asg, morning), (evening_asg, evening)],
        leave_dates=[date(2026, 9, 19)],
    )
    assert slip["leave_pay"] == 850.0
    assert slip["regular_pay"] == 0.0
    assert slip["paid_leave_days"] == 1
    _assert_no_double_count(slip)


def test_leave_plus_worked_same_date_does_not_double_pay():
    shift, assignment = _shift(start=time(8, 0), end=time(16, 0))
    record = _complete_record(assignment, _ph(8, 0), _ph(16, 0))
    slip = _run(
        attendance_rows=[(record, assignment, shift)],
        scheduled=[(assignment, shift)],
        leave_dates=[date(2026, 9, 19)],
    )
    assert slip["regular_pay"] == 800.0
    assert slip["leave_pay"] == 0.0
    assert slip["paid_leave_days"] == 0
    assert slip["gross_pay"] == 800.0
    _assert_no_double_count(slip)


def test_paula_regression_unscheduled_sep_19_and_20_are_zero():
    """Hourly ₱100, approved sick leave on Sep 19–20 with no roster → ₱0."""
    slip = _run(
        hourly_rate=100.0,
        scheduled=[],
        attendance_rows=[],
        leave_dates=[date(2026, 9, 19), date(2026, 9, 20)],
    )
    assert slip["leave_pay"] == 0.0
    assert slip["paid_leave_days"] == 0
    assert slip["worked_days"] == 0.0
    assert slip["hours_worked"] == 0.0
    assert slip["gross_pay"] == 0.0


def test_payslip_breakdown_keeps_leave_pay_separate_from_regular_pay():
    work_shift, work_asg = _shift(
        start=time(16, 0), end=time(20, 30), work_date=date(2026, 9, 18)
    )
    leave_shift, leave_asg = _shift(start=time(16, 0), end=time(20, 30))
    work_record = _complete_record(work_asg, _ph(16, 0, day=18), _ph(20, 30, day=18))
    slip = _run(
        attendance_rows=[(work_record, work_asg, work_shift)],
        scheduled=[(work_asg, work_shift), (leave_asg, leave_shift)],
        leave_dates=[date(2026, 9, 19)],
    )
    assert slip["regular_pay"] == 450.0
    assert slip["leave_pay"] == 450.0
    assert slip["gross_pay"] == 900.0
    assert slip["paid_leave_days"] == 1
    _assert_no_double_count(slip)


def test_leave_pay_is_frozen_in_finalized_snapshot():
    employee = _employee(name="Ana")
    live = {
        "employee_id": str(employee.id),
        "employee_name": "Ana",
        "period_start": "2026-09-01",
        "period_end": "2026-09-15",
        "regular_pay": 450.0,
        "leave_pay": 450.0,
        "gross_pay": 900.0,
        "net_pay": 900.0,
        "final_net_pay": 900.0,
        "paid_leave_days": 1,
        "hours_worked": 4.5,
    }
    frozen = freeze_payslip_dict(live)
    run = _snapshot_run(business_id=employee.business_id)
    db = FakeDB()
    db.runs = [run]
    db.payslips = [_row(run=run, employee_id=employee.id, slip=frozen)]
    db.employees = [employee]
    calc = MagicMock(
        return_value={**live, "leave_pay": 0.0, "gross_pay": 450.0, "paid_leave_days": 0}
    )
    loaded = load_period_payslip(
        db, employee, as_of=date(2026, 9, 10), calculate_payslip=calc
    )
    assert loaded.from_snapshot is True
    assert loaded.slip["leave_pay"] == 450.0
    assert loaded.slip["regular_pay"] == 450.0
    assert loaded.slip["gross_pay"] == 900.0
    calc.assert_not_called()


def test_unfinalize_returns_to_live_leave_pay_then_new_snapshot_freezes_update():
    employee = _employee(name="Ana")
    frozen_open = {
        "employee_id": str(employee.id),
        "employee_name": "Ana",
        "period_start": "2026-09-01",
        "period_end": "2026-09-15",
        "regular_pay": 0.0,
        "leave_pay": 0.0,
        "gross_pay": 0.0,
        "net_pay": 0.0,
        "final_net_pay": 0.0,
        "paid_leave_days": 0,
        "hours_worked": 0.0,
    }
    run = _snapshot_run(business_id=employee.business_id)
    db = FakeDB()
    db.runs = [run]
    db.payslips = [_row(run=run, employee_id=employee.id, slip=frozen_open)]
    db.employees = [employee]
    updated = {**frozen_open, "leave_pay": 450.0, "gross_pay": 450.0, "paid_leave_days": 1}
    calc = MagicMock(return_value=updated)

    before = load_period_payslip(
        db, employee, as_of=date(2026, 9, 10), calculate_payslip=calc
    )
    assert before.slip["leave_pay"] == 0.0
    calc.assert_not_called()

    mark_payroll_run_unfinalized(run)
    assert run.status == PayrollRunStatus.cancelled

    with (
        patch(
            "app.services.payroll_snapshot.resolve_pay_period",
            return_value=(date(2026, 9, 1), date(2026, 9, 15)),
        ),
        patch(
            "app.services.payroll_snapshot.list_active_adjustments",
            return_value=[],
        ),
    ):
        after = load_period_payslip(
            db, employee, as_of=date(2026, 9, 10), calculate_payslip=calc
        )
    assert after.from_snapshot is False
    assert after.slip["leave_pay"] == 450.0
    calc.assert_called()

    new_frozen = freeze_payslip_dict(after.slip)
    assert new_frozen["leave_pay"] == 450.0
    assert new_frozen["paid_leave_days"] == 1


def test_pdf_leave_pay_matches_backend_value():
    shift, assignment = _shift(start=time(16, 0), end=time(20, 30))
    slip = _run(
        attendance_rows=[(_on_leave_record(assignment), assignment, shift)],
        scheduled=[(assignment, shift)],
        leave_dates=[date(2026, 9, 19)],
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
            "leave_pay": slip["leave_pay"],
            "overtime_pay": slip["overtime_pay"],
            "holiday_pay": slip["holiday_pay"],
            "rest_day_pay": slip["rest_day_pay"],
            "gross_pay": slip["gross_pay"],
            "deductions": slip["deductions"],
            "net_pay": slip["net_pay"],
        }
    )
    assert b"Leave pay: PHP 450.00" in pdf
    assert b"Basic salary: PHP 0.00" in pdf
    assert b"Gross pay: PHP 450.00" in pdf


def test_legacy_snapshot_without_leave_pay_does_not_invent_history():
    employee = _employee(name="Ana")
    legacy = {
        "employee_id": str(employee.id),
        "employee_name": "Ana",
        "period_start": "2026-09-01",
        "period_end": "2026-09-15",
        "regular_pay": 800.0,
        "gross_pay": 800.0,
        "net_pay": 800.0,
        "paid_leave_days": 1,
        "hours_worked": 0.0,
    }
    assert "leave_pay" not in legacy
    frozen = freeze_payslip_dict(legacy)
    assert "leave_pay" not in frozen or frozen.get("leave_pay") is None
    run = _snapshot_run(business_id=employee.business_id)
    db = FakeDB()
    db.runs = [run]
    db.payslips = [_row(run=run, employee_id=employee.id, slip=frozen)]
    db.employees = [employee]
    loaded = load_period_payslip(
        db, employee, as_of=date(2026, 9, 10), calculate_payslip=MagicMock()
    )
    assert loaded.slip.get("leave_pay", 0) == 0 or loaded.slip.get("leave_pay") is None
    assert loaded.slip["regular_pay"] == 800.0
