"""Late–OT Balancing: optional recovery of late-from-start via post-end OT."""

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


def _run_payslip(
    *,
    time_in: datetime,
    time_out: datetime | None,
    status: AttendanceStatus,
    enable_late_overtime_balancing: bool,
    ot_minimum: int = 30,
    daily_rate: float = 2700.0,
    overtime_per_minute: float = 1.0,
    is_rest_day_work: bool = False,
    rest_premium_percent: float = 30.0,
):
    business_id = uuid4()
    employee_id = uuid4()
    position_id = uuid4()
    work_date = date(2026, 8, 4)

    employee = SimpleNamespace(
        id=employee_id,
        business_id=business_id,
        full_name="Test Emp",
        position_title="Staff",
        position_id=position_id,
        employment_type=EmploymentType.full_time,
    )
    position = SimpleNamespace(daily_rate=daily_rate)
    business = SimpleNamespace(timezone="Asia/Manila")
    att_policy = SimpleNamespace(
        business_id=business_id,
        on_time_grace_minutes=10,
        overtime_minimum_minutes=ot_minimum,
        half_day_threshold_minutes=240,
        overtime_enabled=True,
    )
    config = SimpleNamespace(
        overtime_per_minute=overtime_per_minute,
        late_deduction_per_minute=1.0,
        late_deduction_enabled=True,
        overtime_enabled=True,
        enable_late_overtime_balancing=enable_late_overtime_balancing,
        holiday_rules_mode=None,
    )
    rest_policy = SimpleNamespace(rest_day_premium_percent=rest_premium_percent)

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
        is_rest_day_work=is_rest_day_work,
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
            return rest_policy
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
            return_value=date(2026, 8, 5),
        ),
        patch(
            "app.api.owner_reports.business_now",
            return_value=datetime(2026, 8, 5, 12, 0),
        ),
        patch(
            "app.api.owner_reports.resolve_holiday_rules_mode",
            return_value="philippine_labor",
        ),
    ):
        slip = _calculate_employee_payslip(
            db, employee, date(2026, 8, 1), date(2026, 8, 31)
        )

    return slip


def _ph(hour: int, minute: int = 0) -> datetime:
    """Asia/Manila wall time as UTC instant for work_date 2026-08-04."""
    # PH = UTC+8 → subtract 8 hours for UTC storage.
    utc_hour = hour - 8
    day = 4
    if utc_hour < 0:
        utc_hour += 24
        day = 3
    return datetime(2026, 8, day, utc_hour, minute, tzinfo=timezone.utc)


def test_balancing_off_pays_full_raw_ot():
    """Toggle OFF: 20 late + 60 past end → pay full 60 OT (existing behavior)."""
    slip = _run_payslip(
        time_in=_ph(8, 20),
        time_out=_ph(18, 0),
        status=AttendanceStatus.late,
        enable_late_overtime_balancing=False,
        ot_minimum=30,
    )
    assert slip["overtime_minutes"] == 60.0
    assert slip["overtime_pay"] == 60.0
    assert slip["deductions"] == 0.0


def test_balancing_on_equal_late_and_ot_zero_payable():
    """Example 1: 20 late + 20 OT → recoverable 20 → payable 0."""
    slip = _run_payslip(
        time_in=_ph(8, 20),
        time_out=_ph(17, 20),
        status=AttendanceStatus.late,
        enable_late_overtime_balancing=True,
        ot_minimum=30,
    )
    assert slip["overtime_minutes"] == 0.0
    assert slip["overtime_pay"] == 0.0
    assert slip["deductions"] == 0.0


def test_balancing_on_late_20_ot_60_pays_40():
    """Example 2: payable OT = 40 after recovering 20 late."""
    slip = _run_payslip(
        time_in=_ph(8, 20),
        time_out=_ph(18, 0),
        status=AttendanceStatus.late,
        enable_late_overtime_balancing=True,
        ot_minimum=30,
    )
    assert slip["overtime_minutes"] == 40.0
    assert slip["overtime_pay"] == 40.0
    assert slip["deductions"] == 0.0


def test_balancing_on_no_late_full_ot():
    """Example 3: on-time → full OT unchanged."""
    slip = _run_payslip(
        time_in=_ph(8, 0),
        time_out=_ph(18, 0),
        status=AttendanceStatus.complete,
        enable_late_overtime_balancing=True,
        ot_minimum=30,
    )
    assert slip["overtime_minutes"] == 60.0
    assert slip["overtime_pay"] == 60.0


def test_balancing_on_raw_ot_less_than_late_zero_payable():
    """Example 4: late 20, raw OT 5 → payable 0; shortfall still from worked span."""
    slip_on = _run_payslip(
        time_in=_ph(8, 20),
        time_out=_ph(17, 5),
        status=AttendanceStatus.late,
        enable_late_overtime_balancing=True,
        ot_minimum=30,
    )
    slip_off = _run_payslip(
        time_in=_ph(8, 20),
        time_out=_ph(17, 5),
        status=AttendanceStatus.late,
        enable_late_overtime_balancing=False,
        ot_minimum=30,
    )
    assert slip_on["overtime_minutes"] == 0.0
    assert slip_off["overtime_minutes"] == 0.0
    # Worked 525 vs scheduled 540 → 15 unpaid minutes at minute_rate 2700/540=5
    assert slip_on["unpaid_minutes"] == 15.0
    assert slip_on["deductions"] == slip_off["deductions"]
    assert slip_on["deductions"] == 75.0


def test_balancing_uses_start_not_grace():
    """In at 8:05 (within grace) still balances 5 minutes from scheduled start."""
    # raw_ot 40, late-from-start 5 → payable 35 (>=30)
    slip = _run_payslip(
        time_in=_ph(8, 5),
        time_out=_ph(17, 40),
        status=AttendanceStatus.complete,
        enable_late_overtime_balancing=True,
        ot_minimum=30,
    )
    assert slip["overtime_minutes"] == 35.0


def test_incomplete_unchanged_with_balancing_on():
    slip = _run_payslip(
        time_in=_ph(8, 0),
        time_out=None,
        status=AttendanceStatus.incomplete,
        enable_late_overtime_balancing=True,
    )
    assert slip["overtime_minutes"] == 0.0
    assert slip["overtime_pay"] == 0.0
    assert slip["deductions"] == 0.0
    assert slip["gross_pay"] == 0.0


def test_rest_day_premium_unchanged_by_balancing_path():
    """Rest premium still from day_earned; balancing only trims OT minutes."""
    slip = _run_payslip(
        time_in=_ph(8, 20),
        time_out=_ph(18, 0),
        status=AttendanceStatus.late,
        enable_late_overtime_balancing=True,
        is_rest_day_work=True,
        rest_premium_percent=30.0,
        daily_rate=2700.0,
    )
    # Full day earned (shortfall 0) → rest premium 30% of 2700
    assert slip["rest_day_pay"] == 810.0
    assert slip["overtime_minutes"] == 40.0


def test_leave_day_unchanged_with_balancing_on():
    business_id = uuid4()
    employee_id = uuid4()
    position_id = uuid4()
    work_date = date(2026, 8, 4)

    employee = SimpleNamespace(
        id=employee_id,
        business_id=business_id,
        full_name="Leave Emp",
        position_title="Staff",
        position_id=position_id,
        employment_type=EmploymentType.full_time,
    )
    position = SimpleNamespace(daily_rate=2700.0)
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
        enable_late_overtime_balancing=True,
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
    record = AttendanceRecord(
        id=uuid4(),
        business_id=business_id,
        employee_id=employee_id,
        shift_assignment_id=assignment.id,
        time_in=None,
        time_out=None,
        status=AttendanceStatus.on_leave,
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
    scheduled_query.join.return_value.filter.return_value.all.return_value = []
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
        patch("app.api.owner_reports.ensure_incomplete_for_employee"),
        patch("app.api.owner_reports.employee_on_approved_leave", return_value=False),
        patch("app.api.owner_reports.approved_leave_dates_for_employee", return_value=[]),
        patch("app.api.owner_reports.leave_is_paid_for_attendance_day", return_value=True),
        patch("app.api.owner_reports.business_today", return_value=date(2026, 8, 5)),
        patch(
            "app.api.owner_reports.business_now",
            return_value=datetime(2026, 8, 5, 12, 0),
        ),
        patch(
            "app.api.owner_reports.resolve_holiday_rules_mode",
            return_value="philippine_labor",
        ),
    ):
        slip = _calculate_employee_payslip(
            db, employee, date(2026, 8, 1), date(2026, 8, 31)
        )

    assert slip["paid_leave_days"] == 1
    assert slip["overtime_minutes"] == 0.0
    assert slip["gross_pay"] == 2700.0
    assert slip["deductions"] == 0.0


def test_holiday_premium_uses_day_earned_not_ot_balancing():
    """Holiday worked premium stays on day_earned; balancing only affects OT add-on."""
    from app.models.enums import HolidayType
    from app.services.holiday_pay import HolidayPolicy

    business_id = uuid4()
    employee_id = uuid4()
    position_id = uuid4()
    work_date = date(2026, 8, 4)
    holiday = Holiday(
        id=uuid4(),
        business_id=business_id,
        name="Test Holiday",
        holiday_date=work_date,
        holiday_type=HolidayType.special_non_working,
        is_active=True,
    )

    employee = SimpleNamespace(
        id=employee_id,
        business_id=business_id,
        full_name="Hol Emp",
        position_title="Staff",
        position_id=position_id,
        employment_type=EmploymentType.full_time,
    )
    position = SimpleNamespace(daily_rate=2700.0)
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
        enable_late_overtime_balancing=True,
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
    record = AttendanceRecord(
        id=uuid4(),
        business_id=business_id,
        employee_id=employee_id,
        shift_assignment_id=assignment.id,
        time_in=_ph(8, 20),
        time_out=_ph(18, 0),
        status=AttendanceStatus.late,
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
    holiday_query.filter.return_value.all.return_value = [holiday]

    def real_query(*models):
        if models[0] is AttendanceRecord:
            return attendance_query
        if models[0] is ShiftAssignment:
            return scheduled_query
        if models[0] is Holiday:
            return holiday_query
        return MagicMock()

    db.query.side_effect = real_query
    policy = HolidayPolicy(
        worked_multiplier=1.3,
        pay_if_not_worked=True,
        suppress_absence=True,
    )

    with (
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
        patch(
            "app.api.owner_reports.resolve_holiday_policy",
            return_value=policy,
        ),
    ):
        slip = _calculate_employee_payslip(
            db, employee, date(2026, 8, 1), date(2026, 8, 31)
        )

    # day_earned = 2700; holiday premium = 2700 * 0.3 = 810
    assert slip["holiday_pay"] == 810.0
    assert slip["overtime_minutes"] == 40.0
    assert slip["deductions"] == 0.0
