"""Phase 2: payroll resolves Employee.daily_rate with Position fallback."""

from datetime import date, datetime, time, timezone
from types import SimpleNamespace
from unittest.mock import MagicMock, patch
from uuid import uuid4

from app.api.owner_reports import _calculate_employee_payslip
from app.models.attendance import AttendanceRecord
from app.models.attendance_policy import BusinessAttendancePolicy
from app.models.business import Business
from app.models.enums import AttendanceStatus, EmploymentType, PayBasis
from app.models.holiday import Holiday
from app.models.payroll import BusinessPayrollConfig, Position
from app.models.rest_day_policy import BusinessRestDayPolicy
from app.models.scheduling import Shift, ShiftAssignment
from app.services.employee_pay import (
    payroll_daily_rate,
    resolve_employee_pay,
    resolve_employee_pay_context,
)
from app.services.holiday_pay import HolidayPolicy


def test_resolve_prefers_employee_daily_rate():
    employee = SimpleNamespace(
        pay_basis=PayBasis.daily,
        daily_rate=720.0,
        hourly_rate=None,
        monthly_salary=None,
    )
    position = SimpleNamespace(daily_rate=650.0)
    resolved = resolve_employee_pay(employee, position=position)
    assert resolved.daily_rate == 720.0
    assert resolved.used_position_fallback is False
    assert payroll_daily_rate(resolved) == 720.0


def test_resolve_falls_back_to_position_daily_rate():
    employee = SimpleNamespace(
        pay_basis=PayBasis.daily,
        daily_rate=None,
        hourly_rate=None,
        monthly_salary=None,
    )
    position = SimpleNamespace(daily_rate=650.0)
    resolved = resolve_employee_pay(employee, position=position)
    assert resolved.daily_rate == 650.0
    assert resolved.used_position_fallback is True


def test_hourly_context_uses_hourly_rate_not_position_daily():
    """Phase 3: hourly earnings ignore Position.daily_rate fallback."""
    employee = SimpleNamespace(
        pay_basis=PayBasis.hourly,
        daily_rate=None,
        hourly_rate=95.0,
        monthly_salary=None,
    )
    position = SimpleNamespace(daily_rate=650.0)
    resolved = resolve_employee_pay(employee, position=position)
    assert resolved.pay_basis == PayBasis.hourly
    assert resolved.hourly_rate == 95.0
    # Position daily still stored as legacy fallback field…
    assert resolved.daily_rate == 650.0
    # …but pay context uses hourly for minute/day value.
    ctx = resolve_employee_pay_context(
        employee, 480.0, position=position, resolved=resolved
    )
    assert ctx.minute_rate == 95.0 / 60.0
    assert ctx.scheduled_day_value == 95.0 * 8.0
    assert ctx.hourly_rate == 95.0


def test_resolve_prefers_employee_hourly_rate():
    employee = SimpleNamespace(
        pay_basis=PayBasis.hourly,
        daily_rate=None,
        hourly_rate=120.0,
        monthly_salary=None,
    )
    position = SimpleNamespace(daily_rate=650.0, hourly_rate=80.0)
    resolved = resolve_employee_pay(employee, position=position)
    assert resolved.hourly_rate == 120.0
    assert resolved.daily_rate == 650.0


def test_resolve_falls_back_to_position_hourly_rate():
    employee = SimpleNamespace(
        pay_basis=PayBasis.hourly,
        daily_rate=None,
        hourly_rate=None,
        monthly_salary=None,
    )
    position = SimpleNamespace(daily_rate=650.0, hourly_rate=80.0)
    resolved = resolve_employee_pay(employee, position=position)
    assert resolved.hourly_rate == 80.0
    assert resolved.used_position_fallback is True
    ctx = resolve_employee_pay_context(
        employee, 480.0, position=position, resolved=resolved
    )
    assert ctx.hourly_rate == 80.0
    assert ctx.minute_rate == 80.0 / 60.0
    assert ctx.scheduled_day_value == 80.0 * 8.0


def test_hourly_context_ignores_position_daily_when_hourly_fallback_used():
    employee = SimpleNamespace(
        pay_basis=PayBasis.hourly,
        daily_rate=None,
        hourly_rate=None,
        monthly_salary=None,
    )
    position = SimpleNamespace(daily_rate=9999.0, hourly_rate=100.0)
    ctx = resolve_employee_pay_context(employee, 480.0, position=position)
    assert ctx.hourly_rate == 100.0
    assert ctx.scheduled_day_value == 800.0


def _ph(hour: int, minute: int = 0) -> datetime:
    utc_hour = hour - 8
    day = 4
    if utc_hour < 0:
        utc_hour += 24
        day = 3
    return datetime(2026, 8, day, utc_hour, minute, tzinfo=timezone.utc)


def _run_payslip(
    *,
    employee_daily_rate: float | None,
    position_daily_rate: float,
    status: AttendanceStatus = AttendanceStatus.complete,
    time_in: datetime | None = None,
    time_out: datetime | None = None,
    is_leave: bool = False,
    with_holiday_premium: bool = False,
    ot_out_hour: int | None = None,
):
    business_id = uuid4()
    employee_id = uuid4()
    position_id = uuid4()
    work_date = date(2026, 8, 4)

    if time_in is None:
        time_in = _ph(8, 0)
    if time_out is None:
        if ot_out_hour is not None:
            time_out = _ph(ot_out_hour, 0)
        else:
            time_out = _ph(17, 0)

    employee = SimpleNamespace(
        id=employee_id,
        business_id=business_id,
        full_name="Pay Emp",
        position_title="Barista",
        position_id=position_id,
        employment_type=EmploymentType.full_time,
        pay_basis=PayBasis.daily,
        daily_rate=employee_daily_rate,
        hourly_rate=None,
        monthly_salary=None,
    )
    position = SimpleNamespace(daily_rate=position_daily_rate)
    business = SimpleNamespace(timezone="Asia/Manila")
    att_policy = SimpleNamespace(
        business_id=business_id,
        on_time_grace_minutes=10,
        overtime_minimum_minutes=30,
        half_day_threshold_minutes=240,
        overtime_enabled=True,
    )
    config = SimpleNamespace(
        overtime_per_minute=1.0,
        late_deduction_per_minute=1.0,
        late_deduction_enabled=True,
        overtime_enabled=True,
        enable_late_overtime_balancing=False,
        holiday_rules_mode=None,
    )

    shift = Shift(
        id=uuid4(),
        business_id=business_id,
        name="Day",
        start_time=time(8, 0),
        end_time=time(17, 0),
    )
    assignment = ShiftAssignment(
        id=uuid4(),
        shift_id=shift.id,
        employee_id=employee_id,
        work_date=work_date,
        is_rest_day_work=False,
    )
    record_status = AttendanceStatus.on_leave if is_leave else status
    record = AttendanceRecord(
        id=uuid4(),
        business_id=business_id,
        employee_id=employee_id,
        shift_assignment_id=assignment.id,
        time_in=None if is_leave else time_in,
        time_out=None if is_leave else time_out,
        status=record_status,
    )

    holiday = None
    if with_holiday_premium:
        from app.models.enums import HolidayType

        holiday = Holiday(
            id=uuid4(),
            business_id=business_id,
            name="Test Day",
            holiday_date=work_date,
            holiday_type=HolidayType.special_non_working,
            is_active=True,
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

    patches = [
        patch("app.api.owner_reports.ensure_incomplete_for_employee"),
        patch("app.api.owner_reports.employee_on_approved_leave", return_value=False),
        patch("app.api.owner_reports.approved_leave_dates_for_employee", return_value=[]),
        patch("app.api.owner_reports.business_today", return_value=date(2026, 8, 5)),
        patch(
            "app.api.owner_reports.business_now",
            return_value=datetime(2026, 8, 5, 12, 0),
        ),
        patch(
            "app.api.owner_reports.resolve_holiday_rules_mode",
            return_value="philippine_labor",
        ),
    ]
    if is_leave:
        patches.append(
            patch(
                "app.api.owner_reports.leave_is_paid_for_attendance_day",
                return_value=True,
            )
        )
    if with_holiday_premium:
        patches.append(
            patch(
                "app.api.owner_reports.resolve_holiday_policy",
                return_value=HolidayPolicy(
                    worked_multiplier=1.3,
                    pay_if_not_worked=True,
                    suppress_absence=True,
                ),
            )
        )

    from contextlib import ExitStack

    with ExitStack() as stack:
        for p in patches:
            stack.enter_context(p)
        return _calculate_employee_payslip(
            db, employee, date(2026, 8, 1), date(2026, 8, 31)
        )


def test_payslip_uses_employee_daily_rate():
    slip = _run_payslip(employee_daily_rate=720.0, position_daily_rate=650.0)
    assert slip["daily_rate"] == 720.0
    assert slip["gross_pay"] == 720.0
    assert slip["deductions"] == 0.0


def test_payslip_falls_back_to_position_daily_rate():
    slip = _run_payslip(employee_daily_rate=None, position_daily_rate=650.0)
    assert slip["daily_rate"] == 650.0
    assert slip["gross_pay"] == 650.0


def test_backfilled_equal_rates_match_legacy_behavior():
    """When employee rate equals position rate, payslip matches prior math."""
    slip_emp = _run_payslip(employee_daily_rate=650.0, position_daily_rate=650.0)
    slip_fallback = _run_payslip(employee_daily_rate=None, position_daily_rate=650.0)
    assert slip_emp["daily_rate"] == slip_fallback["daily_rate"]
    assert slip_emp["gross_pay"] == slip_fallback["gross_pay"]
    assert slip_emp["net_pay"] == slip_fallback["net_pay"]
    assert slip_emp["deductions"] == slip_fallback["deductions"]
    assert slip_emp["overtime_pay"] == slip_fallback["overtime_pay"]


def test_shortfall_uses_resolved_employee_rate():
    # Late in, leave at shift end → unpaid minutes × (720/540)
    slip = _run_payslip(
        employee_daily_rate=720.0,
        position_daily_rate=650.0,
        status=AttendanceStatus.late,
        time_in=_ph(10, 10),
        time_out=_ph(17, 0),
    )
    # Worked 410 vs 540 → 130 unpaid; minute_rate = 720/540 = 4/3
    assert slip["unpaid_minutes"] == 130.0
    assert abs(slip["deductions"] - (130.0 * (720.0 / 540.0))) < 0.01
    assert slip["daily_rate"] == 720.0


def test_leave_pay_uses_resolved_employee_rate():
    slip = _run_payslip(
        employee_daily_rate=720.0,
        position_daily_rate=650.0,
        is_leave=True,
    )
    assert slip["paid_leave_days"] == 1
    assert slip["gross_pay"] == 720.0
    assert slip["overtime_minutes"] == 0.0


def test_holiday_pay_uses_resolved_employee_rate():
    slip = _run_payslip(
        employee_daily_rate=720.0,
        position_daily_rate=650.0,
        with_holiday_premium=True,
    )
    # day_earned 720; premium 720 * 0.3 = 216
    assert slip["holiday_pay"] == 216.0
    assert slip["daily_rate"] == 720.0


def test_ot_unchanged_uses_config_rate_not_daily_rate():
    slip = _run_payslip(
        employee_daily_rate=720.0,
        position_daily_rate=650.0,
        ot_out_hour=18,
    )
    # 60 min OT × ₱1/min config rate
    assert slip["overtime_minutes"] == 60.0
    assert slip["overtime_pay"] == 60.0
    assert slip["gross_pay"] == 720.0 + 60.0
