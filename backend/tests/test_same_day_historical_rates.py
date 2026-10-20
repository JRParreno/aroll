"""Same-day multi-shift historical rates: Hourly independent, Daily conflict."""

from __future__ import annotations

import uuid
from contextlib import ExitStack
from datetime import date, datetime, time, timezone
from types import SimpleNamespace
from unittest.mock import MagicMock, patch

import pytest
from fastapi import HTTPException

from app.api.attendance_corrections import owner_resolve_daily_workday_rate
from app.api.owner_reports import _calculate_employee_payslip
from app.models.attendance import AttendanceRecord
from app.models.attendance_policy import BusinessAttendancePolicy
from app.models.business import Business
from app.models.daily_workday_rate_resolution import DailyWorkdayRateResolution
from app.models.enums import AttendanceStatus, EmploymentType, PayBasis, UserRole
from app.models.payroll import BusinessPayrollConfig, Position
from app.models.rest_day_policy import BusinessRestDayPolicy
from app.models.scheduling import Shift, ShiftAssignment
from app.schemas.attendance_correction import OwnerResolveDailyWorkdayRequest
from app.services.employee_pay import (
    HISTORICAL_RATE_REQUIRED,
    apply_owner_daily_workday_rate,
    find_conflicting_daily_work_dates,
    stamp_attendance_completion_pay,
)


def _ph(hour: int, minute: int = 0, *, day: int = 4) -> datetime:
    utc_hour = hour - 8
    d = day
    if utc_hour < 0:
        utc_hour += 24
        d = day - 1
    return datetime(2026, 8, d, utc_hour, minute, tzinfo=timezone.utc)


def _run_payslip(*, employee, rows, scheduled, position=None, daily_entitlements=None):
    business_id = employee.business_id
    business = SimpleNamespace(timezone="Asia/Manila")
    att_policy = SimpleNamespace(
        business_id=business_id,
        on_time_grace_minutes=10,
        overtime_minimum_minutes=30,
        half_day_threshold_minutes=240,
        overtime_enabled=True,
        breaktime_is_paid=False,
    )
    config = SimpleNamespace(
        overtime_per_minute=1.0,
        late_deduction_per_minute=1.0,
        late_deduction_enabled=True,
        overtime_enabled=True,
        enable_late_overtime_balancing=False,
        holiday_rules_mode=None,
        overtime_approval_required=False,
    )
    position = position or SimpleNamespace(daily_rate=9999.0, hourly_rate=1.0)
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
        from app.models.holiday import Holiday

        if models[0] is Holiday:
            return holiday_query
        return MagicMock()

    db.query.side_effect = real_query
    patches = [
        patch("app.api.owner_reports.ensure_incomplete_for_employee"),
        patch("app.api.owner_reports.employee_on_approved_leave", return_value=False),
        patch(
            "app.api.owner_reports.approved_leave_dates_for_employee",
            return_value=[],
        ),
        patch("app.api.owner_reports.business_today", return_value=date(2026, 8, 20)),
        patch(
            "app.api.owner_reports.business_now",
            return_value=datetime(2026, 8, 20, 12, 0),
        ),
        patch(
            "app.api.owner_reports.resolve_holiday_rules_mode",
            return_value="philippine_labor",
        ),
        patch("app.api.owner_reports.overtime_approval_required", return_value=False),
        patch(
            "app.api.owner_reports.load_daily_workday_entitlements_for_employee",
            return_value=dict(daily_entitlements or {}),
        ),
    ]
    with ExitStack() as stack:
        for p in patches:
            stack.enter_context(p)
        return _calculate_employee_payslip(
            db, employee, date(2026, 8, 1), date(2026, 8, 31)
        )


def _daily_conflict_fixture(*, am_rate=500.0, pm_rate=700.0):
    employee = SimpleNamespace(
        id=uuid.uuid4(),
        business_id=uuid.uuid4(),
        full_name="Daily Conflict",
        position_title="Barista",
        position_id=uuid.uuid4(),
        employment_type=EmploymentType.full_time,
        pay_basis=PayBasis.daily,
        daily_rate=900.0,
        hourly_rate=None,
        monthly_salary=None,
    )
    work_date = date(2026, 8, 4)
    morning = Shift(
        id=uuid.uuid4(),
        business_id=employee.business_id,
        name="AM",
        start_time=time(8, 0),
        end_time=time(12, 0),
    )
    evening = Shift(
        id=uuid.uuid4(),
        business_id=employee.business_id,
        name="PM",
        start_time=time(13, 0),
        end_time=time(17, 0),
    )
    am_asg = ShiftAssignment(
        id=uuid.uuid4(),
        shift_id=morning.id,
        employee_id=employee.id,
        work_date=work_date,
        is_rest_day_work=False,
    )
    pm_asg = ShiftAssignment(
        id=uuid.uuid4(),
        shift_id=evening.id,
        employee_id=employee.id,
        work_date=work_date,
        is_rest_day_work=False,
    )
    am_rec = AttendanceRecord(
        id=uuid.uuid4(),
        business_id=employee.business_id,
        employee_id=employee.id,
        shift_assignment_id=am_asg.id,
        time_in=_ph(8, 0),
        time_out=_ph(12, 0),
        status=AttendanceStatus.complete,
        pay_basis_at_completion=PayBasis.daily,
        daily_rate_at_completion=am_rate,
    )
    pm_rec = AttendanceRecord(
        id=uuid.uuid4(),
        business_id=employee.business_id,
        employee_id=employee.id,
        shift_assignment_id=pm_asg.id,
        time_in=_ph(13, 0),
        time_out=_ph(17, 0),
        status=AttendanceStatus.complete,
        pay_basis_at_completion=PayBasis.daily,
        daily_rate_at_completion=pm_rate,
    )
    return employee, work_date, morning, evening, am_asg, pm_asg, am_rec, pm_rec


def test_hourly_two_shifts_different_historical_rates_sum_independently():
    """Test D: Hourly 100×4 + 150×6 = 1300; current 200 unused."""
    employee = SimpleNamespace(
        id=uuid.uuid4(),
        business_id=uuid.uuid4(),
        full_name="Hourly Dual",
        position_title="Cashier",
        position_id=uuid.uuid4(),
        employment_type=EmploymentType.part_time,
        pay_basis=PayBasis.hourly,
        daily_rate=None,
        hourly_rate=200.0,
        monthly_salary=None,
    )
    work_date = date(2026, 8, 4)
    morning = Shift(
        id=uuid.uuid4(),
        business_id=employee.business_id,
        name="AM",
        start_time=time(8, 0),
        end_time=time(12, 0),
    )
    evening = Shift(
        id=uuid.uuid4(),
        business_id=employee.business_id,
        name="PM",
        start_time=time(13, 0),
        end_time=time(19, 0),
    )
    am_asg = ShiftAssignment(
        id=uuid.uuid4(),
        shift_id=morning.id,
        employee_id=employee.id,
        work_date=work_date,
        is_rest_day_work=False,
    )
    pm_asg = ShiftAssignment(
        id=uuid.uuid4(),
        shift_id=evening.id,
        employee_id=employee.id,
        work_date=work_date,
        is_rest_day_work=False,
    )
    am_rec = AttendanceRecord(
        id=uuid.uuid4(),
        business_id=employee.business_id,
        employee_id=employee.id,
        shift_assignment_id=am_asg.id,
        time_in=_ph(8, 0),
        time_out=_ph(12, 0),
        status=AttendanceStatus.complete,
        pay_basis_at_completion=PayBasis.hourly,
        hourly_rate_at_completion=100.0,
        daily_rate_at_completion=None,
    )
    pm_rec = AttendanceRecord(
        id=uuid.uuid4(),
        business_id=employee.business_id,
        employee_id=employee.id,
        shift_assignment_id=pm_asg.id,
        time_in=_ph(13, 0),
        time_out=_ph(19, 0),
        status=AttendanceStatus.complete,
        pay_basis_at_completion=PayBasis.hourly,
        hourly_rate_at_completion=150.0,
        daily_rate_at_completion=None,
    )
    slip = _run_payslip(
        employee=employee,
        rows=[(am_rec, am_asg, morning), (pm_rec, pm_asg, evening)],
        scheduled=[(am_asg, morning), (pm_asg, evening)],
        daily_entitlements={work_date: 9999.0},
    )
    assert abs(slip["regular_pay"] - 1300.0) < 0.01
    assert abs(slip["gross_pay"] - 1300.0) < 0.01
    assert slip["has_unresolved_historical_rate"] is False


def test_daily_conflicting_stamps_preserve_history_after_workday_resolve_500():
    """Test A: resolve entitlement 500; stamps stay 500 and 700; rate_used truthful."""
    (
        employee,
        work_date,
        morning,
        evening,
        am_asg,
        pm_asg,
        am_rec,
        pm_rec,
    ) = _daily_conflict_fixture()
    rows_a = [(am_rec, am_asg, morning), (pm_rec, pm_asg, evening)]
    rows_b = [(pm_rec, pm_asg, evening), (am_rec, am_asg, morning)]
    assert find_conflicting_daily_work_dates(rows_a) == {work_date}
    assert find_conflicting_daily_work_dates(rows_b) == {work_date}

    slip = _run_payslip(
        employee=employee,
        rows=rows_b,
        scheduled=[(am_asg, morning), (pm_asg, evening)],
    )
    assert slip["has_unresolved_historical_rate"] is True
    assert slip["regular_pay"] == 0.0
    assert slip["gross_pay"] == 0.0
    for row in slip["attendance_records"]:
        if row["shift_name"] in ("AM", "PM"):
            assert row["historical_rate_required"] is True
            assert row["daily_rate_conflict"] is True
            assert row["payroll_status"] == HISTORICAL_RATE_REQUIRED
            assert row["earned"] is None
            assert row["rate_used"] is None

    db = MagicMock()
    db.query.return_value.filter.return_value.first.return_value = None
    entitlement = apply_owner_daily_workday_rate(
        db,
        business_id=employee.business_id,
        employee_id=employee.id,
        work_date=work_date,
        daily_rate=500.0,
    )
    assert entitlement == 500.0
    assert db.add.called
    assert float(am_rec.daily_rate_at_completion) == 500.0
    assert float(pm_rec.daily_rate_at_completion) == 700.0

    slip_after = _run_payslip(
        employee=employee,
        rows=[(am_rec, am_asg, morning), (pm_rec, pm_asg, evening)],
        scheduled=[(am_asg, morning), (pm_asg, evening)],
        daily_entitlements={work_date: 500.0},
    )
    assert slip_after["has_unresolved_historical_rate"] is False
    assert abs(slip_after["regular_pay"] - 500.0) < 0.01
    by_shift = {r["shift_name"]: r for r in slip_after["attendance_records"]}
    assert by_shift["AM"]["rate_used"] == 500.0
    assert by_shift["PM"]["rate_used"] == 700.0
    assert by_shift["AM"]["daily_rate_conflict"] is False
    assert by_shift["PM"]["daily_rate_conflict"] is False
    assert float(am_rec.daily_rate_at_completion) == 500.0
    assert float(pm_rec.daily_rate_at_completion) == 700.0

    # Tests F + G: reload + later Employee rate; entitlement and stamps hold.
    employee.daily_rate = 900.0
    slip_stable = _run_payslip(
        employee=employee,
        rows=[(am_rec, am_asg, morning), (pm_rec, pm_asg, evening)],
        scheduled=[(am_asg, morning), (pm_asg, evening)],
        daily_entitlements={work_date: 500.0},
    )
    assert abs(slip_stable["regular_pay"] - 500.0) < 0.01
    by_shift = {r["shift_name"]: r for r in slip_stable["attendance_records"]}
    assert by_shift["AM"]["rate_used"] == 500.0
    assert by_shift["PM"]["rate_used"] == 700.0
    assert float(am_rec.daily_rate_at_completion) == 500.0
    assert float(pm_rec.daily_rate_at_completion) == 700.0


def test_daily_conflicting_stamps_resolve_entitlement_700():
    """Test B: resolve entitlement 700; stamps stay 500 and 700."""
    (
        employee,
        work_date,
        morning,
        evening,
        am_asg,
        pm_asg,
        am_rec,
        pm_rec,
    ) = _daily_conflict_fixture()
    db = MagicMock()
    db.query.return_value.filter.return_value.first.return_value = None
    assert (
        apply_owner_daily_workday_rate(
            db,
            business_id=employee.business_id,
            employee_id=employee.id,
            work_date=work_date,
            daily_rate=700.0,
        )
        == 700.0
    )
    assert float(am_rec.daily_rate_at_completion) == 500.0
    assert float(pm_rec.daily_rate_at_completion) == 700.0
    slip = _run_payslip(
        employee=employee,
        rows=[(am_rec, am_asg, morning), (pm_rec, pm_asg, evening)],
        scheduled=[(am_asg, morning), (pm_asg, evening)],
        daily_entitlements={work_date: 700.0},
    )
    assert abs(slip["regular_pay"] - 700.0) < 0.01
    by_shift = {r["shift_name"]: r for r in slip["attendance_records"]}
    assert by_shift["AM"]["rate_used"] == 500.0
    assert by_shift["PM"]["rate_used"] == 700.0


def test_owner_resolve_daily_workday_api_persists_entitlement_not_stamps():
    """Production API path: upsert entitlement; attendance stamps untouched."""
    (
        employee,
        work_date,
        morning,
        evening,
        am_asg,
        pm_asg,
        am_rec,
        pm_rec,
    ) = _daily_conflict_fixture()
    rows = [(am_rec, am_asg, morning), (pm_rec, pm_asg, evening)]
    user = SimpleNamespace(
        id=uuid.uuid4(),
        role=UserRole.owner,
        business_id=employee.business_id,
    )
    db = MagicMock()
    emp_query = MagicMock()
    emp_query.filter.return_value.first.return_value = employee
    att_query = MagicMock()
    att_query.outerjoin.return_value.outerjoin.return_value.filter.return_value.all.return_value = (
        rows
    )
    resolution_query = MagicMock()
    resolution_query.filter.return_value.first.return_value = None

    def query_side_effect(*models):
        from app.models.employee import Employee

        if models and models[0] is Employee:
            return emp_query
        if models and models[0] is AttendanceRecord:
            return att_query
        if models and models[0] is DailyWorkdayRateResolution:
            return resolution_query
        return MagicMock()

    db.query.side_effect = query_side_effect

    with patch(
        "app.services.payroll_snapshot.find_snapshot_run", return_value=None
    ):
        result = owner_resolve_daily_workday_rate(
            body=OwnerResolveDailyWorkdayRequest(
                employee_id=employee.id,
                work_date=work_date,
                daily_rate=500.0,
            ),
            db=db,
            user=user,
        )

    assert result["daily_rate"] == 500.0
    assert result["stamps_unchanged"] is True
    assert result["historical_rate_required"] is False
    assert float(am_rec.daily_rate_at_completion) == 500.0
    assert float(pm_rec.daily_rate_at_completion) == 700.0
    assert db.add.called
    assert db.commit.called
    added = db.add.call_args[0][0]
    assert isinstance(added, DailyWorkdayRateResolution)
    assert float(added.daily_rate) == 500.0
    assert added.work_date == work_date


def test_owner_resolve_daily_workday_api_blocks_finalized_period():
    (
        employee,
        work_date,
        _m,
        _e,
        _aa,
        _pa,
        _ar,
        _pr,
    ) = _daily_conflict_fixture()
    user = SimpleNamespace(
        id=uuid.uuid4(),
        role=UserRole.owner,
        business_id=employee.business_id,
    )
    db = MagicMock()
    db.query.return_value.filter.return_value.first.return_value = employee
    with patch(
        "app.services.payroll_snapshot.find_snapshot_run",
        return_value=SimpleNamespace(id=uuid.uuid4()),
    ):
        with pytest.raises(HTTPException) as exc:
            owner_resolve_daily_workday_rate(
                body=OwnerResolveDailyWorkdayRequest(
                    employee_id=employee.id,
                    work_date=work_date,
                    daily_rate=500.0,
                ),
                db=db,
                user=user,
            )
    assert exc.value.status_code == 400
    assert "finalized" in str(exc.value.detail).lower()


def test_daily_plus_hourly_same_date_no_conflict():
    """Test E: Daily 500 + Hourly 4h×100 — no conflict; both apply."""
    employee = SimpleNamespace(
        id=uuid.uuid4(),
        business_id=uuid.uuid4(),
        full_name="Mixed",
        position_title="Hybrid",
        position_id=uuid.uuid4(),
        employment_type=EmploymentType.full_time,
        pay_basis=PayBasis.daily,
        daily_rate=900.0,
        hourly_rate=200.0,
        monthly_salary=None,
    )
    work_date = date(2026, 8, 4)
    morning = Shift(
        id=uuid.uuid4(),
        business_id=employee.business_id,
        name="AM",
        start_time=time(8, 0),
        end_time=time(17, 0),
    )
    evening = Shift(
        id=uuid.uuid4(),
        business_id=employee.business_id,
        name="PM",
        start_time=time(18, 0),
        end_time=time(22, 0),
    )
    am_asg = ShiftAssignment(
        id=uuid.uuid4(),
        shift_id=morning.id,
        employee_id=employee.id,
        work_date=work_date,
        is_rest_day_work=False,
    )
    pm_asg = ShiftAssignment(
        id=uuid.uuid4(),
        shift_id=evening.id,
        employee_id=employee.id,
        work_date=work_date,
        is_rest_day_work=False,
    )
    am_rec = AttendanceRecord(
        id=uuid.uuid4(),
        business_id=employee.business_id,
        employee_id=employee.id,
        shift_assignment_id=am_asg.id,
        time_in=_ph(8, 0),
        time_out=_ph(17, 0),
        status=AttendanceStatus.complete,
        pay_basis_at_completion=PayBasis.daily,
        daily_rate_at_completion=500.0,
    )
    pm_rec = AttendanceRecord(
        id=uuid.uuid4(),
        business_id=employee.business_id,
        employee_id=employee.id,
        shift_assignment_id=pm_asg.id,
        time_in=_ph(18, 0),
        time_out=_ph(22, 0),
        status=AttendanceStatus.complete,
        pay_basis_at_completion=PayBasis.hourly,
        hourly_rate_at_completion=100.0,
        daily_rate_at_completion=None,
    )
    rows = [(am_rec, am_asg, morning), (pm_rec, pm_asg, evening)]
    assert find_conflicting_daily_work_dates(rows) == set()
    slip = _run_payslip(
        employee=employee,
        rows=rows,
        scheduled=[(am_asg, morning), (pm_asg, evening)],
    )
    assert slip["has_unresolved_historical_rate"] is False
    assert abs(slip["regular_pay"] - 900.0) < 0.01
    by_shift = {r["shift_name"]: r for r in slip["attendance_records"]}
    assert by_shift["AM"]["historical_rate_required"] is False
    assert by_shift["PM"]["historical_rate_required"] is False
    assert abs(by_shift["PM"]["expected_salary_pay"] - 400.0) < 0.01
    assert by_shift["AM"]["rate_used"] == 500.0
    assert by_shift["PM"]["rate_used"] == 100.0
    assert float(am_rec.daily_rate_at_completion) == 500.0
    assert float(pm_rec.hourly_rate_at_completion) == 100.0


def test_agreed_daily_stamps_credit_once_order_independent():
    """Test C: Two Daily stamps at same 500 — one entitlement; no Owner resolve."""
    employee = SimpleNamespace(
        id=uuid.uuid4(),
        business_id=uuid.uuid4(),
        full_name="Agreed",
        position_title="Barista",
        position_id=uuid.uuid4(),
        employment_type=EmploymentType.full_time,
        pay_basis=PayBasis.daily,
        daily_rate=900.0,
        hourly_rate=None,
        monthly_salary=None,
    )
    work_date = date(2026, 8, 4)
    morning = Shift(
        id=uuid.uuid4(),
        business_id=employee.business_id,
        name="AM",
        start_time=time(8, 0),
        end_time=time(12, 0),
    )
    evening = Shift(
        id=uuid.uuid4(),
        business_id=employee.business_id,
        name="PM",
        start_time=time(13, 0),
        end_time=time(17, 0),
    )
    am_asg = ShiftAssignment(
        id=uuid.uuid4(),
        shift_id=morning.id,
        employee_id=employee.id,
        work_date=work_date,
        is_rest_day_work=False,
    )
    pm_asg = ShiftAssignment(
        id=uuid.uuid4(),
        shift_id=evening.id,
        employee_id=employee.id,
        work_date=work_date,
        is_rest_day_work=False,
    )
    am_rec = AttendanceRecord(
        id=uuid.uuid4(),
        business_id=employee.business_id,
        employee_id=employee.id,
        shift_assignment_id=am_asg.id,
        time_in=_ph(8, 0),
        time_out=_ph(12, 0),
        status=AttendanceStatus.complete,
        pay_basis_at_completion=PayBasis.daily,
        daily_rate_at_completion=500.0,
    )
    pm_rec = AttendanceRecord(
        id=uuid.uuid4(),
        business_id=employee.business_id,
        employee_id=employee.id,
        shift_assignment_id=pm_asg.id,
        time_in=_ph(13, 0),
        time_out=_ph(17, 0),
        status=AttendanceStatus.complete,
        pay_basis_at_completion=PayBasis.daily,
        daily_rate_at_completion=500.0,
    )
    for rows in (
        [(am_rec, am_asg, morning), (pm_rec, pm_asg, evening)],
        [(pm_rec, pm_asg, evening), (am_rec, am_asg, morning)],
    ):
        slip = _run_payslip(
            employee=employee,
            rows=rows,
            scheduled=[(am_asg, morning), (pm_asg, evening)],
        )
        assert abs(slip["regular_pay"] - 500.0) < 0.01
        assert slip["has_unresolved_historical_rate"] is False
        by_shift = {r["shift_name"]: r for r in slip["attendance_records"]}
        assert by_shift["AM"]["rate_used"] == 500.0
        assert by_shift["PM"]["rate_used"] == 500.0
        assert float(am_rec.daily_rate_at_completion) == 500.0
        assert float(pm_rec.daily_rate_at_completion) == 500.0


def test_new_stamp_and_role_change_preserve_completed():
    """Completed keeps stamp; new completion stamps current."""
    employee = SimpleNamespace(
        pay_basis=PayBasis.daily,
        daily_rate=500.0,
        hourly_rate=None,
        monthly_salary=None,
    )
    old = AttendanceRecord(
        id=uuid.uuid4(),
        business_id=uuid.uuid4(),
        employee_id=uuid.uuid4(),
        time_in=_ph(8, 0),
        time_out=_ph(17, 0),
        status=AttendanceStatus.complete,
    )
    assert stamp_attendance_completion_pay(old, employee) is True
    employee.daily_rate = 700.0
    assert stamp_attendance_completion_pay(old, employee) is False
    assert float(old.daily_rate_at_completion) == 500.0

    new = AttendanceRecord(
        id=uuid.uuid4(),
        business_id=old.business_id,
        employee_id=old.employee_id,
        time_in=_ph(8, 0, day=5),
        time_out=_ph(17, 0, day=5),
        status=AttendanceStatus.complete,
    )
    assert stamp_attendance_completion_pay(new, employee) is True
    assert float(new.daily_rate_at_completion) == 700.0
    employee.daily_rate = 900.0
    assert stamp_attendance_completion_pay(new, employee) is False
    assert float(new.daily_rate_at_completion) == 700.0
