"""Phase 3: hourly employee payroll via PayrollPayContext."""

from contextlib import ExitStack
from datetime import date, datetime, time, timezone
from types import SimpleNamespace
from unittest.mock import MagicMock, patch
from uuid import uuid4

from app.api.owner_reports import _calculate_employee_payslip
from app.models.attendance import AttendanceRecord
from app.models.attendance_policy import BusinessAttendancePolicy
from app.models.business import Business
from app.models.enums import AttendanceStatus, EmploymentType, HolidayType, PayBasis
from app.models.holiday import Holiday
from app.models.payroll import BusinessPayrollConfig, Position
from app.models.rest_day_policy import BusinessRestDayPolicy
from app.models.scheduling import Shift, ShiftAssignment
from app.services.holiday_pay import HolidayPolicy


def _ph(hour: int, minute: int = 0, day: int = 4) -> datetime:
    """Asia/Manila local wall time → UTC for stored punches."""
    utc_hour = hour - 8
    utc_day = day
    if utc_hour < 0:
        utc_hour += 24
        utc_day = day - 1
    return datetime(2026, 8, utc_day, utc_hour, minute, tzinfo=timezone.utc)


def _run_payslip(
    *,
    pay_basis: PayBasis = PayBasis.hourly,
    daily_rate: float | None = None,
    hourly_rate: float | None = 100.0,
    position_daily_rate: float = 650.0,
    status: AttendanceStatus = AttendanceStatus.complete,
    time_in: datetime | None = None,
    time_out: datetime | None = None,
    shift_start: time = time(8, 0),
    shift_end: time = time(16, 0),
    is_leave: bool = False,
    with_holiday_premium: bool = False,
    unworked_holiday_noshow: bool = False,
    include_attendance: bool = True,
    approved_leave_dates: list[date] | None = None,
):
    business_id = uuid4()
    employee_id = uuid4()
    position_id = uuid4()
    work_date = date(2026, 8, 4)

    if time_in is None and include_attendance and not is_leave:
        time_in = _ph(8, 0)
    if time_out is None and include_attendance and not is_leave:
        time_out = _ph(16, 0)

    employee = SimpleNamespace(
        id=employee_id,
        business_id=business_id,
        full_name="Hourly Emp",
        position_title="Cashier",
        position_id=position_id,
        employment_type=EmploymentType.part_time,
        pay_basis=pay_basis,
        daily_rate=daily_rate,
        hourly_rate=hourly_rate,
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
        name="Day8",
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

    rows = []
    if include_attendance:
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
        rows = [(record, assignment, shift)]

    holiday = None
    if with_holiday_premium or unworked_holiday_noshow:
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
    attendance_query.outerjoin.return_value.outerjoin.return_value.filter.return_value.all.return_value = (
        rows
    )
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
        patch(
            "app.api.owner_reports.employee_on_approved_leave",
            return_value=bool(approved_leave_dates),
        ),
        patch(
            "app.api.owner_reports.approved_leave_dates_for_employee",
            return_value=approved_leave_dates or [],
        ),
        patch("app.api.owner_reports.business_today", return_value=date(2026, 8, 5)),
        patch(
            "app.api.owner_reports.business_now",
            return_value=datetime(2026, 8, 5, 12, 0),
        ),
        patch(
            "app.api.owner_reports.resolve_holiday_rules_mode",
            return_value="philippine_labor",
        ),
        patch(
            "app.api.owner_reports.is_past_clock_out_deadline",
            return_value=True,
        ),
    ]
    if is_leave or approved_leave_dates:
        patches.append(
            patch(
                "app.api.owner_reports.leave_is_paid_for_attendance_day",
                return_value=True,
            )
        )
    if with_holiday_premium or unworked_holiday_noshow:
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

    with ExitStack() as stack:
        for p in patches:
            stack.enter_context(p)
        return _calculate_employee_payslip(
            db, employee, date(2026, 8, 1), date(2026, 8, 31)
        )


def test_daily_regression_full_day_unchanged():
    slip = _run_payslip(
        pay_basis=PayBasis.daily,
        daily_rate=800.0,
        hourly_rate=None,
        position_daily_rate=650.0,
        shift_start=time(8, 0),
        shift_end=time(16, 0),
    )
    assert slip["pay_basis"] == "daily"
    assert slip["daily_rate"] == 800.0
    assert slip["gross_pay"] == 800.0
    assert slip["deductions"] == 0.0
    assert slip["net_pay"] == 800.0


def test_hourly_full_eight_hours():
    """8h scheduled × ₱100/h = ₱800; net earnings = worked × minute_rate."""
    slip = _run_payslip(hourly_rate=100.0)
    assert slip["pay_basis"] == "hourly"
    assert slip["hourly_rate_configured"] == 100.0
    # Engine credits scheduled_day_value; shortfall 0 → net = 8 × hourly
    assert slip["gross_pay"] == 800.0
    assert slip["deductions"] == 0.0
    assert slip["net_pay"] == 800.0
    assert abs(slip["attendance_records"][0]["earned"] - 800.0) < 0.01


def test_hourly_undertime():
    # Scheduled 8h; worked 6h → unpaid 2h × ₱100
    slip = _run_payslip(
        hourly_rate=100.0,
        status=AttendanceStatus.complete,
        time_in=_ph(8, 0),
        time_out=_ph(14, 0),
    )
    assert slip["unpaid_minutes"] == 120.0
    assert abs(slip["deductions"] - 200.0) < 0.01
    assert abs(slip["gross_pay"] - 800.0) < 0.01
    assert abs(slip["net_pay"] - 600.0) < 0.01
    assert abs(slip["attendance_records"][0]["earned"] - 600.0) < 0.01


def test_hourly_overtime_uses_config_rate():
    # Full 8h + 60 min past end; OT min 30 → 60 × ₱1
    slip = _run_payslip(
        hourly_rate=100.0,
        time_in=_ph(8, 0),
        time_out=_ph(17, 0),
    )
    assert slip["overtime_minutes"] == 60.0
    assert slip["overtime_pay"] == 60.0
    assert slip["net_pay"] == 800.0 + 60.0


def test_hourly_paid_leave():
    slip = _run_payslip(hourly_rate=100.0, is_leave=True)
    assert slip["paid_leave_days"] == 1
    assert slip["gross_pay"] == 800.0
    assert slip["overtime_minutes"] == 0.0


def test_hourly_leave_reconciliation():
    slip = _run_payslip(
        hourly_rate=100.0,
        include_attendance=False,
        approved_leave_dates=[date(2026, 8, 4)],
    )
    assert slip["paid_leave_days"] == 1
    assert slip["gross_pay"] == 800.0


def test_hourly_worked_holiday_premium():
    slip = _run_payslip(hourly_rate=100.0, with_holiday_premium=True)
    # day_earned 800; premium 800 * 0.3 = 240
    assert slip["holiday_pay"] == 240.0
    assert slip["gross_pay"] == 800.0 + 240.0


def test_hourly_unworked_holiday_noshow():
    slip = _run_payslip(
        hourly_rate=100.0,
        include_attendance=False,
        unworked_holiday_noshow=True,
    )
    assert slip["holiday_pay"] == 800.0
    assert slip["absent_days"] == 0
    assert slip["gross_pay"] == 800.0


def test_hourly_noshow_absent_zero():
    slip = _run_payslip(hourly_rate=100.0, include_attendance=False)
    assert slip["absent_days"] == 1
    assert slip["gross_pay"] == 0.0
    assert slip["net_pay"] == 0.0


def test_hourly_incomplete_unpaid():
    slip = _run_payslip(
        hourly_rate=100.0,
        status=AttendanceStatus.incomplete,
        time_in=_ph(8, 0),
        time_out=None,
    )
    assert slip["gross_pay"] == 0.0
    assert slip["net_pay"] == 0.0
    assert slip["attendance_records"][0]["payroll_status"] == (
        "pending_attendance_correction"
    )


def test_hourly_ignores_position_daily_rate():
    """Hourly earnings must not use Position.daily_rate fallback."""
    slip = _run_payslip(
        hourly_rate=100.0,
        daily_rate=None,
        position_daily_rate=9999.0,
    )
    assert slip["net_pay"] == 800.0
    assert slip["gross_pay"] == 800.0


def test_daily_payroll_unchanged_vs_phase2_shape():
    """Daily shortfall math identical: credit daily_rate, deduct unpaid × rate."""
    slip = _run_payslip(
        pay_basis=PayBasis.daily,
        daily_rate=720.0,
        hourly_rate=None,
        position_daily_rate=650.0,
        shift_start=time(8, 0),
        shift_end=time(17, 0),  # 540 min
        status=AttendanceStatus.late,
        time_in=_ph(10, 10),
        time_out=_ph(17, 0),
    )
    assert slip["daily_rate"] == 720.0
    assert slip["unpaid_minutes"] == 130.0
    assert abs(slip["deductions"] - (130.0 * (720.0 / 540.0))) < 0.01
    assert abs(slip["gross_pay"] - 720.0) < 0.01
