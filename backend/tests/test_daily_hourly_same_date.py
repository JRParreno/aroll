"""Lock existing Daily+Hourly same-work-date payroll behavior (no new policy).

Stacking Daily entitlement + independent Hourly shift pay is established by
``test_daily_plus_hourly_same_date_no_conflict``. These tests extend coverage
without changing engine formulas.
"""

from __future__ import annotations

import uuid
from datetime import date, datetime, time, timezone
from types import SimpleNamespace

from app.models.attendance import AttendanceRecord
from app.models.enums import AttendanceStatus, EmploymentType, PayBasis
from app.models.scheduling import Shift, ShiftAssignment
from app.services.employee_pay import find_conflicting_daily_work_dates
from app.services.schedule_overlap import shifts_times_overlap
from tests.test_same_day_historical_rates import _ph, _run_payslip


def _employee(**kwargs):
    base = dict(
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
    base.update(kwargs)
    return SimpleNamespace(**base)


def test_daily_plus_hourly_different_historical_hourly_rate():
    """Daily ₱500 + Hourly ₱150×4h = ₱1100; current employee rates unused."""
    employee = _employee()
    work_date = date(2026, 8, 4)
    daily_shift = Shift(
        id=uuid.uuid4(),
        business_id=employee.business_id,
        name="Day",
        start_time=time(8, 0),
        end_time=time(14, 0),
    )
    hourly_shift = Shift(
        id=uuid.uuid4(),
        business_id=employee.business_id,
        name="Eve",
        start_time=time(14, 0),
        end_time=time(18, 0),
    )
    assert not shifts_times_overlap(daily_shift, hourly_shift)  # adjacent OK
    day_asg = ShiftAssignment(
        id=uuid.uuid4(),
        shift_id=daily_shift.id,
        employee_id=employee.id,
        work_date=work_date,
        is_rest_day_work=False,
    )
    eve_asg = ShiftAssignment(
        id=uuid.uuid4(),
        shift_id=hourly_shift.id,
        employee_id=employee.id,
        work_date=work_date,
        is_rest_day_work=False,
    )
    day_rec = AttendanceRecord(
        id=uuid.uuid4(),
        business_id=employee.business_id,
        employee_id=employee.id,
        shift_assignment_id=day_asg.id,
        time_in=_ph(8, 0),
        time_out=_ph(14, 0),
        status=AttendanceStatus.complete,
        pay_basis_at_completion=PayBasis.daily,
        daily_rate_at_completion=500.0,
    )
    eve_rec = AttendanceRecord(
        id=uuid.uuid4(),
        business_id=employee.business_id,
        employee_id=employee.id,
        shift_assignment_id=eve_asg.id,
        time_in=_ph(14, 0),
        time_out=_ph(18, 0),
        status=AttendanceStatus.complete,
        pay_basis_at_completion=PayBasis.hourly,
        hourly_rate_at_completion=150.0,
        daily_rate_at_completion=None,
    )
    rows = [(day_rec, day_asg, daily_shift), (eve_rec, eve_asg, hourly_shift)]
    assert find_conflicting_daily_work_dates(rows) == set()
    slip = _run_payslip(
        employee=employee,
        rows=rows,
        scheduled=[(day_asg, daily_shift), (eve_asg, hourly_shift)],
    )
    assert abs(slip["regular_pay"] - 1100.0) < 0.01
    by_shift = {r["shift_name"]: r for r in slip["attendance_records"]}
    assert by_shift["Day"]["rate_used"] == 500.0
    assert by_shift["Eve"]["rate_used"] == 150.0
    assert abs(by_shift["Eve"]["expected_salary_pay"] - 600.0) < 0.01


def test_daily_plus_hourly_undertime_on_hourly_is_independent():
    """Hourly early-out deducts from Hourly entitlement; Daily stays full."""
    employee = _employee()
    work_date = date(2026, 8, 4)
    daily_shift = Shift(
        id=uuid.uuid4(),
        business_id=employee.business_id,
        name="Day",
        start_time=time(8, 0),
        end_time=time(12, 0),
    )
    hourly_shift = Shift(
        id=uuid.uuid4(),
        business_id=employee.business_id,
        name="Eve",
        start_time=time(13, 0),
        end_time=time(17, 0),
    )
    day_asg = ShiftAssignment(
        id=uuid.uuid4(),
        shift_id=daily_shift.id,
        employee_id=employee.id,
        work_date=work_date,
        is_rest_day_work=False,
    )
    eve_asg = ShiftAssignment(
        id=uuid.uuid4(),
        shift_id=hourly_shift.id,
        employee_id=employee.id,
        work_date=work_date,
        is_rest_day_work=False,
    )
    day_rec = AttendanceRecord(
        id=uuid.uuid4(),
        business_id=employee.business_id,
        employee_id=employee.id,
        shift_assignment_id=day_asg.id,
        time_in=_ph(8, 0),
        time_out=_ph(12, 0),
        status=AttendanceStatus.complete,
        pay_basis_at_completion=PayBasis.daily,
        daily_rate_at_completion=500.0,
    )
    # Hourly ₱100 × 4h entitlement = ₱400; leave 1h early → UT ₱100
    eve_rec = AttendanceRecord(
        id=uuid.uuid4(),
        business_id=employee.business_id,
        employee_id=employee.id,
        shift_assignment_id=eve_asg.id,
        time_in=_ph(13, 0),
        time_out=_ph(16, 0),
        status=AttendanceStatus.complete,
        pay_basis_at_completion=PayBasis.hourly,
        hourly_rate_at_completion=100.0,
        daily_rate_at_completion=None,
    )
    slip = _run_payslip(
        employee=employee,
        rows=[(day_rec, day_asg, daily_shift), (eve_rec, eve_asg, hourly_shift)],
        scheduled=[(day_asg, daily_shift), (eve_asg, hourly_shift)],
    )
    # Regular still stacks full entitlements; UT is a separate deduction.
    assert abs(slip["regular_pay"] - 900.0) < 0.01
    assert abs(slip["undertime_deductions"] - 100.0) < 0.01
    assert abs(slip["net_pay"] - 800.0) < 0.01


def test_overlapping_shift_windows_detected_for_assignment_layer():
    """Assignment validation uses shifts_times_overlap; overlap is true here."""
    a = SimpleNamespace(start_time=time(8, 0), end_time=time(17, 0))
    b = SimpleNamespace(start_time=time(16, 0), end_time=time(20, 0))
    assert shifts_times_overlap(a, b) is True


def test_adjacent_shift_windows_are_not_overlap():
    a = SimpleNamespace(start_time=time(8, 0), end_time=time(14, 0))
    b = SimpleNamespace(start_time=time(14, 0), end_time=time(18, 0))
    assert shifts_times_overlap(a, b) is False


def test_mixed_basis_does_not_create_daily_conflict():
    employee = _employee()
    work_date = date(2026, 8, 4)
    d_shift = Shift(
        id=uuid.uuid4(),
        business_id=employee.business_id,
        name="D",
        start_time=time(8, 0),
        end_time=time(12, 0),
    )
    h_shift = Shift(
        id=uuid.uuid4(),
        business_id=employee.business_id,
        name="H",
        start_time=time(13, 0),
        end_time=time(17, 0),
    )
    d_asg = ShiftAssignment(
        id=uuid.uuid4(),
        shift_id=d_shift.id,
        employee_id=employee.id,
        work_date=work_date,
        is_rest_day_work=False,
    )
    h_asg = ShiftAssignment(
        id=uuid.uuid4(),
        shift_id=h_shift.id,
        employee_id=employee.id,
        work_date=work_date,
        is_rest_day_work=False,
    )
    d_rec = AttendanceRecord(
        id=uuid.uuid4(),
        business_id=employee.business_id,
        employee_id=employee.id,
        shift_assignment_id=d_asg.id,
        time_in=_ph(8, 0),
        time_out=_ph(12, 0),
        status=AttendanceStatus.complete,
        pay_basis_at_completion=PayBasis.daily,
        daily_rate_at_completion=500.0,
    )
    h_rec = AttendanceRecord(
        id=uuid.uuid4(),
        business_id=employee.business_id,
        employee_id=employee.id,
        shift_assignment_id=h_asg.id,
        time_in=_ph(13, 0),
        time_out=_ph(17, 0),
        status=AttendanceStatus.complete,
        pay_basis_at_completion=PayBasis.hourly,
        hourly_rate_at_completion=100.0,
    )
    assert (
        find_conflicting_daily_work_dates(
            [(d_rec, d_asg, d_shift), (h_rec, h_asg, h_shift)]
        )
        == set()
    )
