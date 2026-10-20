"""OT approval gating + transparency; preserves automatic OT when approval off."""

from datetime import date, datetime, time, timezone
from types import SimpleNamespace
from unittest.mock import MagicMock, patch
from uuid import uuid4

from app.api.owner_reports import _calculate_employee_payslip
from app.models.attendance import AttendanceRecord
from app.models.attendance_policy import BusinessAttendancePolicy
from app.models.business import Business
from app.models.enums import (
    AttendanceStatus,
    EmploymentType,
    OvertimeApprovalStatus,
    PayBasis,
)
from app.models.payroll import BusinessPayrollConfig, Position
from app.models.rest_day_policy import BusinessRestDayPolicy
from app.models.scheduling import Shift, ShiftAssignment
from app.services.employee_pay import stamp_attendance_completion_pay
from app.services.ot_approval import payable_ot_minutes
from app.services.payroll_adjustments import apply_adjustments_to_slip
from app.services.payroll_engine import overtime_pay_amount


def _ph(hour: int, minute: int = 0) -> datetime:
    utc_hour = hour - 8
    day = 4
    if utc_hour < 0:
        utc_hour += 24
        day = 3
    return datetime(2026, 8, day, utc_hour, minute, tzinfo=timezone.utc)


def test_payable_ot_minutes_gate():
    assert payable_ot_minutes(
        worked_ot_minutes=60,
        approval_required=False,
        ot_approval_status=None,
    ) == 60
    assert payable_ot_minutes(
        worked_ot_minutes=60,
        approval_required=True,
        ot_approval_status="pending",
    ) == 0
    assert payable_ot_minutes(
        worked_ot_minutes=60,
        approval_required=True,
        ot_approval_status="rejected",
    ) == 0
    assert payable_ot_minutes(
        worked_ot_minutes=60,
        approval_required=True,
        ot_approval_status="approved",
    ) == 60


def test_ot_rate_one_peso_thirty_minutes():
    assert abs(overtime_pay_amount(30, 1.0, 0.0) - 30.0) < 0.01


def _run_slip(
    *,
    time_in: datetime,
    time_out: datetime,
    enable_late_overtime_balancing: bool = False,
    overtime_approval_required: bool = False,
    ot_approval_status: OvertimeApprovalStatus | None = None,
    shift_start: time = time(8, 0),
    shift_end: time = time(17, 0),
    late_rate: float = 1.0,
    ot_rate: float = 1.0,
    grace: int = 10,
    ot_minimum: int = 30,
    stamp: bool = True,
):
    business_id = uuid4()
    employee_id = uuid4()
    work_date = date(2026, 8, 4)
    employee = SimpleNamespace(
        id=employee_id,
        business_id=business_id,
        full_name="OT Emp",
        position_title="Staff",
        position_id=uuid4(),
        employment_type=EmploymentType.full_time,
        pay_basis=PayBasis.daily,
        daily_rate=800.0,
        hourly_rate=None,
        monthly_salary=None,
    )
    position = SimpleNamespace(daily_rate=800.0, hourly_rate=None)
    business = SimpleNamespace(timezone="Asia/Manila")
    att_policy = SimpleNamespace(
        business_id=business_id,
        on_time_grace_minutes=grace,
        overtime_minimum_minutes=ot_minimum,
        half_day_threshold_minutes=240,
        overtime_enabled=True,
    )
    config = SimpleNamespace(
        overtime_per_minute=ot_rate,
        late_deduction_per_minute=late_rate,
        late_deduction_enabled=True,
        overtime_enabled=True,
        enable_late_overtime_balancing=enable_late_overtime_balancing,
        overtime_approval_required=overtime_approval_required,
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
        status=AttendanceStatus.late if time_in > _ph(8, grace) else AttendanceStatus.complete,
        ot_approval_status=ot_approval_status,
    )
    if stamp:
        stamp_attendance_completion_pay(record, employee, position=position)
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
        from app.models.holiday import Holiday

        if models[0] is AttendanceRecord:
            return attendance_query
        if models[0] is ShiftAssignment:
            return scheduled_query
        if models[0] is Holiday:
            return holiday_query
        return MagicMock()

    db.query.side_effect = real_query
    from contextlib import ExitStack

    with ExitStack() as stack:
        for p in [
            patch("app.api.owner_reports.ensure_incomplete_for_employee"),
            patch("app.api.owner_reports.employee_on_approved_leave", return_value=False),
            patch(
                "app.api.owner_reports.approved_leave_dates_for_employee",
                return_value=[],
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
        ]:
            stack.enter_context(p)
        return _calculate_employee_payslip(
            db, employee, date(2026, 8, 1), date(2026, 8, 31)
        )


def test_ot_rate_reaches_payslip_thirty_minutes():
    # 08:00–17:30 → 30 OT at ₱1
    slip = _run_slip(time_in=_ph(8, 0), time_out=_ph(17, 30))
    assert slip["overtime_minutes"] == 30.0
    assert abs(slip["overtime_pay"] - 30.0) < 0.01
    assert slip["attendance_records"][0]["ot"]["ot_rate_per_minute"] == 1.0


def test_closed_punch_without_completion_stamp_is_not_priced_from_the_live_rate():
    slip = _run_slip(time_in=_ph(8, 0), time_out=_ph(17, 30), stamp=False)
    row = slip["attendance_records"][0]
    assert row["historical_rate_required"] is True
    assert slip["regular_pay"] == 0.0
    assert slip["overtime_pay"] == 0.0
    assert slip["late_deductions"] == 0.0
    assert slip["unresolved_historical_rate_count"] == 1


def test_late_twenty_minutes_twenty_pesos():
    # grace 10 → 08:30 is 20 monetary late minutes × ₱1
    slip = _run_slip(time_in=_ph(8, 30), time_out=_ph(17, 0))
    assert abs(slip["late_minutes"] - 20.0) < 0.01
    assert abs(slip["late_deductions"] - 20.0) < 0.01


def test_balancing_on_0830_to_1800():
    slip = _run_slip(
        time_in=_ph(8, 30),
        time_out=_ph(18, 0),
        enable_late_overtime_balancing=True,
    )
    assert slip["overtime_minutes"] == 30.0
    assert abs(slip["overtime_pay"] - 30.0) < 0.01
    assert slip["late_deductions"] == 0.0
    assert slip["attendance_records"][0]["ot"]["time_recovered_minutes"] == 30.0


def test_balancing_off_0830_to_1800():
    slip = _run_slip(
        time_in=_ph(8, 30),
        time_out=_ph(18, 0),
        enable_late_overtime_balancing=False,
    )
    assert abs(slip["late_minutes"] - 20.0) < 0.01
    assert abs(slip["late_deductions"] - 20.0) < 0.01
    assert slip["overtime_minutes"] == 60.0
    assert abs(slip["overtime_pay"] - 60.0) < 0.01


def test_undertime_single_deduction_no_shortfall_double():
    slip = _run_slip(time_in=_ph(8, 0), time_out=_ph(16, 0))
    assert slip["overtime_minutes"] == 0.0
    assert abs(slip["undertime_minutes"] - 60.0) < 0.01
    # shortfall mirrors undertime on the day row; period deductions use undertime once
    row = slip["attendance_records"][0]
    assert abs(row["shortfall_deduction"] - row["undertime_deduction"]) < 0.01
    assert abs(slip["deductions"] - slip["undertime_deductions"]) < 0.01
    assert abs(slip["deductions"] - row["undertime_deduction"]) < 0.01


def test_ot_approval_pending_not_payable():
    slip = _run_slip(
        time_in=_ph(8, 0),
        time_out=_ph(19, 0),
        overtime_approval_required=True,
        ot_approval_status=OvertimeApprovalStatus.pending,
    )
    assert slip["worked_overtime_minutes"] == 120.0
    assert slip["pending_overtime_minutes"] == 120.0
    assert slip["overtime_minutes"] == 0.0
    assert slip["overtime_pay"] == 0.0
    assert slip["attendance_records"][0]["ot"]["ot_approval_status"] == "pending"


def test_ot_approval_approved_pays_configured_rate():
    slip = _run_slip(
        time_in=_ph(8, 0),
        time_out=_ph(19, 0),
        overtime_approval_required=True,
        ot_approval_status=OvertimeApprovalStatus.approved,
    )
    assert slip["worked_overtime_minutes"] == 120.0
    assert slip["overtime_minutes"] == 120.0
    assert abs(slip["overtime_pay"] - 120.0) < 0.01


def test_ot_approval_rejected_worked_but_not_paid():
    slip = _run_slip(
        time_in=_ph(8, 0),
        time_out=_ph(19, 0),
        overtime_approval_required=True,
        ot_approval_status=OvertimeApprovalStatus.rejected,
    )
    assert slip["worked_overtime_minutes"] == 120.0
    assert slip["rejected_overtime_minutes"] == 120.0
    assert slip["overtime_pay"] == 0.0


def test_manual_adjustment_not_confused_with_system_ot():
    slip = _run_slip(time_in=_ph(8, 0), time_out=_ph(18, 0))
    assert abs(slip["overtime_pay"] - 60.0) < 0.01
    adj = SimpleNamespace(
        id=uuid4(),
        employee_id=uuid4(),
        period_start=date(2026, 8, 1),
        period_end=date(2026, 8, 31),
        kind="allowance",
        type_key="meal_allowance",
        custom_name=None,
        display_name="Meal",
        description="Manual",
        amount=100.0,
        created_by=None,
        created_at=None,
        updated_by=None,
        updated_at=None,
        previous_amount=None,
        deleted_at=None,
    )
    enriched = apply_adjustments_to_slip(dict(slip), [adj])
    assert abs(enriched["overtime_pay"] - 60.0) < 0.01
    assert abs(enriched["payroll_adjustments_allowance_total"] - 100.0) < 0.01
    assert abs(enriched["final_net_pay"] - (slip["net_pay"] + 100.0)) < 0.01


def test_ot_not_double_counted_in_gross():
    slip = _run_slip(time_in=_ph(8, 0), time_out=_ph(18, 0))
    # One OT component only
    assert abs(slip["overtime_pay"] - 60.0) < 0.01
    expected_gross = (
        slip["regular_pay"]
        + slip["leave_pay"]
        + slip["overtime_pay"]
        + slip["holiday_pay"]
        + slip["rest_day_pay"]
    )
    assert abs(slip["gross_pay"] - expected_gross) < 0.01


def test_review_ot_approval_blocked_when_period_finalized():
    from fastapi import HTTPException

    from app.models.payroll import BusinessPayrollConfig
    from app.models.scheduling import ShiftAssignment
    from app.services.ot_approval import review_ot_approval

    business_id = uuid4()
    work_date = date(2026, 8, 4)
    assignment_id = uuid4()
    record = SimpleNamespace(
        id=uuid4(),
        business_id=business_id,
        shift_assignment_id=assignment_id,
        time_in=_ph(8, 0),
        ot_approval_status=OvertimeApprovalStatus.pending,
        ot_reviewed_by=None,
        ot_reviewed_at=None,
    )
    assignment = SimpleNamespace(id=assignment_id, work_date=work_date)
    config = SimpleNamespace()
    db = MagicMock()

    def db_get(model, key=None):
        if model is ShiftAssignment:
            return assignment
        if model is BusinessPayrollConfig:
            return config
        return None

    db.get.side_effect = db_get

    with patch(
        "app.services.pay_period.resolve_pay_period",
        return_value=(date(2026, 8, 1), date(2026, 8, 31)),
    ), patch(
        "app.services.payroll_snapshot.find_finalized_run_for_period",
        return_value=SimpleNamespace(id=uuid4()),
    ):
        try:
            review_ot_approval(db, record, reviewer_id=uuid4(), approve=True)
            raised = False
        except HTTPException as exc:
            raised = True
            assert exc.status_code == 409
            assert exc.detail["code"] == "payroll_finalized"
    assert raised
