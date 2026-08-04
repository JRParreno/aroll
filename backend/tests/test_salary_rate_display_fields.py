"""API exposes pay_basis + basis-specific rates for UI salary-rate labels."""

from types import SimpleNamespace

from app.models.enums import PayBasis
from app.services.employee_pay import resolve_employee_pay


def test_hourly_resolved_fields_for_display():
    employee = SimpleNamespace(
        pay_basis=PayBasis.hourly,
        daily_rate=None,
        hourly_rate=120.0,
        monthly_salary=None,
    )
    position = SimpleNamespace(daily_rate=650.0)
    resolved = resolve_employee_pay(employee, position=position)
    assert resolved.pay_basis == PayBasis.hourly
    assert resolved.hourly_rate == 120.0
    # Legacy daily fallback may still be present — UI must ignore for hourly label.
    assert resolved.daily_rate == 650.0


def test_payslip_payload_includes_canonical_rate_fields():
    """Smoke: slip keys used by clients for salary-rate formatting."""
    from datetime import date, datetime, time, timezone
    from unittest.mock import MagicMock, patch
    from uuid import uuid4
    from contextlib import ExitStack

    from app.api.owner_reports import _calculate_employee_payslip
    from app.models.attendance import AttendanceRecord
    from app.models.attendance_policy import BusinessAttendancePolicy
    from app.models.business import Business
    from app.models.enums import AttendanceStatus, EmploymentType
    from app.models.holiday import Holiday
    from app.models.payroll import BusinessPayrollConfig, Position
    from app.models.rest_day_policy import BusinessRestDayPolicy
    from app.models.scheduling import Shift, ShiftAssignment

    business_id = uuid4()
    employee_id = uuid4()
    position_id = uuid4()
    work_date = date(2026, 8, 4)

    employee = SimpleNamespace(
        id=employee_id,
        business_id=business_id,
        full_name="Hourly Emp",
        position_title="Cashier",
        position_id=position_id,
        employment_type=EmploymentType.part_time,
        pay_basis=PayBasis.hourly,
        daily_rate=None,
        hourly_rate=120.0,
        monthly_salary=None,
    )
    position = SimpleNamespace(daily_rate=650.0)
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
    record = AttendanceRecord(
        id=uuid4(),
        business_id=business_id,
        employee_id=employee_id,
        shift_assignment_id=assignment.id,
        time_in=datetime(2026, 8, 4, 0, 0, tzinfo=timezone.utc),
        time_out=datetime(2026, 8, 4, 8, 0, tzinfo=timezone.utc),
        status=AttendanceStatus.complete,
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
        slip = _calculate_employee_payslip(
            db, employee, date(2026, 8, 1), date(2026, 8, 31)
        )

    assert slip["pay_basis"] == "hourly"
    assert slip["hourly_rate"] == 120.0
    assert slip["monthly_salary"] is None
    assert slip["hourly_rate_configured"] == 120.0
    # Legacy field may still show position fallback — not for salary-rate label.
    assert slip["daily_rate"] == 650.0
    # Basic Salary UI must use engine regular_pay (8h × ₱120), not daily_rate.
    assert slip["regular_pay"] == 960.0
