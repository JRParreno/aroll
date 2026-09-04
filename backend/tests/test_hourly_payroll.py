"""Phase 3: hourly employee payroll via PayrollPayContext."""

from contextlib import ExitStack
from datetime import date, datetime, time, timedelta, timezone
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


def _manila_to_utc(local: datetime) -> datetime:
    """Naive Asia/Manila wall clock → UTC (fixed UTC+8)."""
    return (local - timedelta(hours=8)).replace(tzinfo=timezone.utc)


def _run_payslip(
    *,
    pay_basis: PayBasis = PayBasis.hourly,
    daily_rate: float | None = None,
    hourly_rate: float | None = 100.0,
    position_daily_rate: float = 650.0,
    position_hourly_rate: float | None = None,
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
    position = SimpleNamespace(
        daily_rate=position_daily_rate,
        hourly_rate=position_hourly_rate,
    )
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
    assert slip["worked_days"] == 1.0
    assert slip["hours_worked"] == 8.0


def test_hourly_full_eight_hours():
    """8h scheduled × ₱100/h = ₱800; net earnings = worked × minute_rate."""
    slip = _run_payslip(hourly_rate=100.0)
    assert slip["pay_basis"] == "hourly"
    assert slip["hourly_rate_configured"] == 100.0
    # Engine credits scheduled_day_value; shortfall 0 → net = 8 × hourly
    assert slip["gross_pay"] == 800.0
    assert slip["deductions"] == 0.0
    assert slip["net_pay"] == 800.0
    assert slip["worked_days"] == 1.0
    assert slip["hours_worked"] == 8.0
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
    assert slip["worked_days"] == 1.0
    assert slip["hours_worked"] == 6.0
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
    # Actual 8:00–17:00 = 9h. OT is already inside duration — not 8 + OT.
    assert slip["hours_worked"] == 9.0
    assert slip["worked_days"] == 1.0


def test_hourly_paid_leave():
    slip = _run_payslip(hourly_rate=100.0, is_leave=True)
    assert slip["paid_leave_days"] == 1
    assert slip["gross_pay"] == 800.0
    assert slip["overtime_minutes"] == 0.0
    assert slip["worked_days"] == 0.0
    assert slip["hours_worked"] == 0.0


def test_hourly_leave_reconciliation():
    slip = _run_payslip(
        hourly_rate=100.0,
        include_attendance=False,
        approved_leave_dates=[date(2026, 8, 4)],
    )
    assert slip["paid_leave_days"] == 1
    assert slip["gross_pay"] == 800.0
    assert slip["worked_days"] == 0.0
    assert slip["hours_worked"] == 0.0


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
    assert slip["worked_days"] == 0.0
    assert slip["hours_worked"] == 0.0


def test_hourly_incomplete_unpaid():
    slip = _run_payslip(
        hourly_rate=100.0,
        status=AttendanceStatus.incomplete,
        time_in=_ph(8, 0),
        time_out=None,
    )
    assert slip["gross_pay"] == 0.0
    assert slip["net_pay"] == 0.0
    assert slip["worked_days"] == 0.0
    assert slip["hours_worked"] == 0.0
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


def test_hourly_falls_back_to_position_hourly_rate():
    slip = _run_payslip(
        hourly_rate=None,
        daily_rate=None,
        position_hourly_rate=100.0,
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


def test_hourly_two_shifts_same_day_are_paid_independently():
    """Morning 4h + evening 5h on one date each contribute their own scheduled pay."""
    business_id = uuid4()
    employee_id = uuid4()
    position_id = uuid4()
    work_date = date(2026, 8, 4)
    hourly_rate = 100.0

    employee = SimpleNamespace(
        id=employee_id,
        business_id=business_id,
        full_name="Split Shift Emp",
        position_title="Cashier",
        position_id=position_id,
        employment_type=EmploymentType.part_time,
        pay_basis=PayBasis.hourly,
        daily_rate=None,
        hourly_rate=hourly_rate,
        monthly_salary=None,
    )
    position = SimpleNamespace(daily_rate=650.0, hourly_rate=None)
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

    morning_shift = Shift(
        id=uuid4(),
        business_id=business_id,
        name="Morning",
        start_time=time(8, 30),
        end_time=time(12, 30),
    )
    evening_shift = Shift(
        id=uuid4(),
        business_id=business_id,
        name="Evening",
        start_time=time(18, 0),
        end_time=time(23, 0),
    )
    morning_assignment = ShiftAssignment(
        id=uuid4(),
        shift_id=morning_shift.id,
        employee_id=employee_id,
        work_date=work_date,
        is_rest_day_work=False,
    )
    evening_assignment = ShiftAssignment(
        id=uuid4(),
        shift_id=evening_shift.id,
        employee_id=employee_id,
        work_date=work_date,
        is_rest_day_work=False,
    )
    morning_record = AttendanceRecord(
        id=uuid4(),
        business_id=business_id,
        employee_id=employee_id,
        shift_assignment_id=morning_assignment.id,
        time_in=_ph(8, 30),
        time_out=_ph(12, 30),
        status=AttendanceStatus.complete,
    )
    evening_record = AttendanceRecord(
        id=uuid4(),
        business_id=business_id,
        employee_id=employee_id,
        shift_assignment_id=evening_assignment.id,
        time_in=_ph(18, 0),
        time_out=_ph(23, 0),
        status=AttendanceStatus.complete,
    )
    rows = [
        (morning_record, morning_assignment, morning_shift),
        (evening_record, evening_assignment, evening_shift),
    ]

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
        (morning_assignment, morning_shift),
        (evening_assignment, evening_shift),
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

    with ExitStack() as stack:
        stack.enter_context(patch("app.api.owner_reports.ensure_incomplete_for_employee"))
        stack.enter_context(
            patch("app.api.owner_reports.employee_on_approved_leave", return_value=False)
        )
        stack.enter_context(
            patch("app.api.owner_reports.approved_leave_dates_for_employee", return_value=[])
        )
        stack.enter_context(
            patch("app.api.owner_reports.business_today", return_value=date(2026, 8, 5))
        )
        stack.enter_context(
            patch(
                "app.api.owner_reports.business_now",
                return_value=datetime(2026, 8, 5, 12, 0),
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
        slip = _calculate_employee_payslip(
            db, employee, date(2026, 8, 1), date(2026, 8, 31)
        )

    assignment_ids = {
        row.get("shift_assignment_id") for row in slip["attendance_records"]
    }
    assert assignment_ids == {
        str(morning_assignment.id),
        str(evening_assignment.id),
    }
    assert {row.get("shift_name") for row in slip["attendance_records"]} == {
        "Morning",
        "Evening",
    }
    assert slip["worked_days"] == 1.0
    assert slip["hours_worked"] == 9.0
    # 4h × ₱100 + 5h × ₱100 — pay still per shift
    assert abs(slip["gross_pay"] - 900.0) < 0.01
    assert abs(slip["net_pay"] - 900.0) < 0.01
    dates = {row["date"] for row in slip["attendance_records"]}
    assert dates == {"2026-08-04"}


def _hourly_slip_for_shifts(shift_rows: list[dict], *, today: date | None = None):
    """Build a payslip from completed/incomplete shift specs.

    Each spec: work_date, name, start, end, time_in, time_out, status.
    Monetary hourly rate is ₱100 unless overridden.
    """
    business_id = uuid4()
    employee_id = uuid4()
    position_id = uuid4()
    hourly_rate = 100.0
    as_of = today or date(2026, 9, 6)

    employee = SimpleNamespace(
        id=employee_id,
        business_id=business_id,
        full_name="Split Shift Emp",
        position_title="Cashier",
        position_id=position_id,
        employment_type=EmploymentType.part_time,
        pay_basis=PayBasis.hourly,
        daily_rate=None,
        hourly_rate=hourly_rate,
        monthly_salary=None,
    )
    position = SimpleNamespace(daily_rate=650.0, hourly_rate=None)
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

    rows = []
    scheduled = []
    for spec in shift_rows:
        shift = Shift(
            id=uuid4(),
            business_id=business_id,
            name=spec["name"],
            start_time=spec["start"],
            end_time=spec["end"],
        )
        assignment = ShiftAssignment(
            id=uuid4(),
            shift_id=shift.id,
            employee_id=employee_id,
            work_date=spec["work_date"],
            is_rest_day_work=False,
        )
        record = AttendanceRecord(
            id=uuid4(),
            business_id=business_id,
            employee_id=employee_id,
            shift_assignment_id=assignment.id,
            time_in=spec.get("time_in"),
            time_out=spec.get("time_out"),
            status=spec.get("status", AttendanceStatus.complete),
        )
        rows.append((record, assignment, shift))
        scheduled.append((assignment, shift))

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
    scheduled_query.join.return_value.filter.return_value.all.return_value = scheduled
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

    period_start = min(spec["work_date"] for spec in shift_rows)
    period_end = max(spec["work_date"] for spec in shift_rows)
    with ExitStack() as stack:
        stack.enter_context(patch("app.api.owner_reports.ensure_incomplete_for_employee"))
        stack.enter_context(
            patch("app.api.owner_reports.employee_on_approved_leave", return_value=False)
        )
        stack.enter_context(
            patch("app.api.owner_reports.approved_leave_dates_for_employee", return_value=[])
        )
        stack.enter_context(
            patch("app.api.owner_reports.business_today", return_value=as_of)
        )
        stack.enter_context(
            patch(
                "app.api.owner_reports.business_now",
                return_value=datetime(as_of.year, as_of.month, as_of.day, 12, 0),
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


def test_same_date_afternoon_and_evening_hours():
    """2:30–5:30 + 6:00–10:00 on one work_date → 1 day, 7 hours."""
    work_date = date(2026, 9, 4)
    slip = _hourly_slip_for_shifts(
        [
            {
                "work_date": work_date,
                "name": "Afternoon",
                "start": time(14, 30),
                "end": time(17, 30),
                "time_in": _manila_to_utc(datetime(2026, 9, 4, 14, 30)),
                "time_out": _manila_to_utc(datetime(2026, 9, 4, 17, 30)),
            },
            {
                "work_date": work_date,
                "name": "Evening",
                "start": time(18, 0),
                "end": time(22, 0),
                "time_in": _manila_to_utc(datetime(2026, 9, 4, 18, 0)),
                "time_out": _manila_to_utc(datetime(2026, 9, 4, 22, 0)),
            },
        ]
    )
    assert slip["worked_days"] == 1.0
    assert slip["hours_worked"] == 7.0
    # Pay still per shift: 3h + 4h at ₱100
    assert abs(slip["gross_pay"] - 700.0) < 0.01
    assert abs(slip["net_pay"] - 700.0) < 0.01


def test_two_dates_with_multiple_shifts():
    """Unique work_dates = 2; hours = 3+4 + 3+4 = 14."""
    slip = _hourly_slip_for_shifts(
        [
            {
                "work_date": date(2026, 9, 4),
                "name": "A1",
                "start": time(14, 30),
                "end": time(17, 30),
                "time_in": _manila_to_utc(datetime(2026, 9, 4, 14, 30)),
                "time_out": _manila_to_utc(datetime(2026, 9, 4, 17, 30)),
            },
            {
                "work_date": date(2026, 9, 4),
                "name": "A2",
                "start": time(18, 0),
                "end": time(22, 0),
                "time_in": _manila_to_utc(datetime(2026, 9, 4, 18, 0)),
                "time_out": _manila_to_utc(datetime(2026, 9, 4, 22, 0)),
            },
            {
                "work_date": date(2026, 9, 5),
                "name": "B1",
                "start": time(14, 30),
                "end": time(17, 30),
                "time_in": _manila_to_utc(datetime(2026, 9, 5, 14, 30)),
                "time_out": _manila_to_utc(datetime(2026, 9, 5, 17, 30)),
            },
            {
                "work_date": date(2026, 9, 5),
                "name": "B2",
                "start": time(18, 0),
                "end": time(22, 0),
                "time_in": _manila_to_utc(datetime(2026, 9, 5, 18, 0)),
                "time_out": _manila_to_utc(datetime(2026, 9, 5, 22, 0)),
            },
        ]
    )
    assert slip["worked_days"] == 2.0
    assert slip["hours_worked"] == 14.0
    assert abs(slip["gross_pay"] - 1400.0) < 0.01
    assert abs(slip["net_pay"] - 1400.0) < 0.01


def test_overnight_shift_counts_start_work_date():
    """10:00 PM → 2:00 AM belongs to Sept 4 work_date: 1 day, 4 hours."""
    work_date = date(2026, 9, 4)
    slip = _hourly_slip_for_shifts(
        [
            {
                "work_date": work_date,
                "name": "Overnight",
                "start": time(22, 0),
                "end": time(2, 0),
                "time_in": _manila_to_utc(datetime(2026, 9, 4, 22, 0)),
                "time_out": _manila_to_utc(datetime(2026, 9, 5, 2, 0)),
            }
        ]
    )
    assert slip["worked_days"] == 1.0
    assert slip["hours_worked"] == 4.0
    assert slip["attendance_records"][0]["date"] == "2026-09-04"
    assert abs(slip["gross_pay"] - 400.0) < 0.01
    assert abs(slip["net_pay"] - 400.0) < 0.01


def test_same_date_day_shift_plus_overnight():
    """Sept 4 2:30–5:30 plus 10:00 PM–2:00 AM → 1 day, 7 hours."""
    work_date = date(2026, 9, 4)
    slip = _hourly_slip_for_shifts(
        [
            {
                "work_date": work_date,
                "name": "Afternoon",
                "start": time(14, 30),
                "end": time(17, 30),
                "time_in": _manila_to_utc(datetime(2026, 9, 4, 14, 30)),
                "time_out": _manila_to_utc(datetime(2026, 9, 4, 17, 30)),
            },
            {
                "work_date": work_date,
                "name": "Overnight",
                "start": time(22, 0),
                "end": time(2, 0),
                "time_in": _manila_to_utc(datetime(2026, 9, 4, 22, 0)),
                "time_out": _manila_to_utc(datetime(2026, 9, 5, 2, 0)),
            },
        ]
    )
    assert slip["worked_days"] == 1.0
    assert slip["hours_worked"] == 7.0


def test_shift_ending_exactly_at_midnight():
    """10:00 PM → 12:00 AM on work_date Sept 4 → 1 day, 2 hours."""
    work_date = date(2026, 9, 4)
    slip = _hourly_slip_for_shifts(
        [
            {
                "work_date": work_date,
                "name": "Late",
                "start": time(22, 0),
                "end": time(0, 0),
                "time_in": _manila_to_utc(datetime(2026, 9, 4, 22, 0)),
                "time_out": _manila_to_utc(datetime(2026, 9, 5, 0, 0)),
            }
        ]
    )
    assert slip["worked_days"] == 1.0
    assert slip["hours_worked"] == 2.0
    assert slip["attendance_records"][0]["date"] == "2026-09-04"
    assert abs(slip["gross_pay"] - 200.0) < 0.01


def test_incomplete_second_shift_excluded_from_hours():
    work_date = date(2026, 9, 4)
    slip = _hourly_slip_for_shifts(
        [
            {
                "work_date": work_date,
                "name": "Afternoon",
                "start": time(14, 30),
                "end": time(17, 30),
                "time_in": _manila_to_utc(datetime(2026, 9, 4, 14, 30)),
                "time_out": _manila_to_utc(datetime(2026, 9, 4, 17, 30)),
                "status": AttendanceStatus.complete,
            },
            {
                "work_date": work_date,
                "name": "Evening",
                "start": time(18, 0),
                "end": time(22, 0),
                "time_in": _manila_to_utc(datetime(2026, 9, 4, 18, 0)),
                "time_out": None,
                "status": AttendanceStatus.incomplete,
            },
        ]
    )
    assert slip["worked_days"] == 1.0
    assert slip["hours_worked"] == 3.0
    assert abs(slip["gross_pay"] - 300.0) < 0.01
    assert abs(slip["net_pay"] - 300.0) < 0.01


def test_hours_worked_comes_from_core_slip_not_eight_hour_days():
    """List/payslip/history all read hours_worked from _calculate_employee_payslip."""
    slip = _run_payslip(hourly_rate=100.0)
    assert "hours_worked" in slip
    assert slip["hours_worked"] == 8.0
    assert slip["worked_days"] == 1.0

    split = _hourly_slip_for_shifts(
        [
            {
                "work_date": date(2026, 9, 4),
                "name": "Afternoon",
                "start": time(14, 30),
                "end": time(17, 30),
                "time_in": _manila_to_utc(datetime(2026, 9, 4, 14, 30)),
                "time_out": _manila_to_utc(datetime(2026, 9, 4, 17, 30)),
            },
            {
                "work_date": date(2026, 9, 4),
                "name": "Evening",
                "start": time(18, 0),
                "end": time(22, 0),
                "time_in": _manila_to_utc(datetime(2026, 9, 4, 18, 0)),
                "time_out": _manila_to_utc(datetime(2026, 9, 4, 22, 0)),
            },
        ]
    )
    assert split["worked_days"] == 1.0
    assert split["hours_worked"] == 7.0
    # Old display formula would have been 1×8 + OT = 8.
    assert split["hours_worked"] != split["worked_days"] * 8 + split["overtime_hours"]

    ot_slip = _run_payslip(
        hourly_rate=100.0,
        time_in=_ph(8, 0),
        time_out=_ph(17, 0),
    )
    assert ot_slip["hours_worked"] == 9.0
    assert ot_slip["overtime_hours"] == 1.0
    assert ot_slip["net_pay"] == 800.0 + 60.0


