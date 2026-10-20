"""Shift History shift_net must not double-count undertime.

Daily ``earned`` is prorated from payable minutes (already reduced by early
departure). Subtracting undertime pesos again produced shift_net ₱0 while
period payroll correctly kept day_value − undertime ≈ earned.

Hourly ``earned`` already nets undertime from scheduled_day_value. Subtracting
shift_deductions (late + undertime) again produced the same ₱0 Shift Net bug
while Earned remained positive.
"""

from __future__ import annotations

from datetime import date, datetime, time, timezone
from types import SimpleNamespace
from unittest.mock import MagicMock, patch
from uuid import uuid4

from app.api.owner_reports import shift_history_report
from app.models.attendance import AttendanceRecord
from app.models.business import Business
from app.models.enums import AttendanceStatus, EmploymentType, PayBasis
from app.models.scheduling import Shift, ShiftAssignment
from app.services.payroll_snapshot import PeriodPayrollLoad, freeze_payslip_dict
from tests.test_payroll_engine import _run
from tests.test_same_day_historical_rates import _run_payslip


def _ph(hour: int, minute: int = 0, *, day: int = 4) -> datetime:
    utc_hour = hour - 8
    d = day
    if utc_hour < 0:
        utc_hour += 24
        d = day - 1
    return datetime(2026, 8, d, utc_hour, minute, tzinfo=timezone.utc)


def _shift_pair(start: time, end: time, *, name="Shift", work_date=None):
    business_id = uuid4()
    shift = Shift(
        id=uuid4(),
        business_id=business_id,
        name=name,
        start_time=start,
        end_time=end,
        break_minutes=0,
    )
    assignment = ShiftAssignment(
        id=uuid4(),
        shift_id=shift.id,
        employee_id=uuid4(),
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


def test_daily_shift_net_with_undertime_matches_period_contribution():
    """₱250 / 120 scheduled / early out → shift_net ≈ period day net, not ₱0."""
    shift, assignment = _shift_pair(time(13, 0), time(15, 0))
    record = _record(
        assignment,
        _ph(13, 0),
        datetime(2026, 8, 4, 5, 42, 42, 395035, tzinfo=timezone.utc),
    )
    slip = _run(
        rows=[(record, assignment, shift)],
        scheduled=[(assignment, shift)],
        daily_rate=250.0,
        grace_minutes=5,
        late_deduction_per_minute=1.0,
    )
    row = slip["attendance_records"][0]
    earned = float(row["earned"])
    shift_net = float(row["shift_net"])
    period_day_net = (
        float(slip["regular_pay"])
        - float(slip["undertime_deductions"])
        - float(slip["late_deductions"])
    )

    assert abs(float(slip["regular_pay"]) - 250.0) < 0.01
    assert abs(shift_net - period_day_net) < 0.05
    assert shift_net > 1.0
    # earned remains prorated; shift_net follows entitlement − late − UT
    assert abs(float(row["expected_salary_pay"]) - 250.0) < 0.01
    assert abs(
        shift_net
        - (
            float(row["expected_salary_pay"])
            - float(row["late_deduction"])
            - float(row["undertime_deduction"])
        )
    ) < 0.05


def test_daily_shift_net_full_shift_no_undertime():
    shift, assignment = _shift_pair(time(13, 0), time(15, 0))
    record = _record(assignment, _ph(13, 0), _ph(15, 0))
    slip = _run(
        rows=[(record, assignment, shift)],
        scheduled=[(assignment, shift)],
        daily_rate=250.0,
    )
    row = slip["attendance_records"][0]
    assert abs(float(row["shift_net"]) - 250.0) < 0.01
    assert abs(float(slip["regular_pay"]) - 250.0) < 0.01
    assert float(slip["undertime_deductions"]) == 0.0


def test_daily_shift_net_late_and_undertime_not_double_applied():
    shift, assignment = _shift_pair(time(8, 0), time(16, 0))
    record = _record(assignment, _ph(8, 20), _ph(15, 0))
    slip = _run(
        rows=[(record, assignment, shift)],
        scheduled=[(assignment, shift)],
        daily_rate=480.0,
        grace_minutes=10,
        late_deduction_per_minute=1.0,
    )
    row = slip["attendance_records"][0]
    late_ded = float(row["late_deduction"])
    ut_ded = float(row["undertime_deduction"])
    earned = float(row["earned"])
    shift_net = float(row["shift_net"])
    period_net = (
        float(slip["regular_pay"])
        - float(slip["late_deductions"])
        - float(slip["undertime_deductions"])
    )

    assert late_ded > 0
    assert ut_ded > 0
    assert abs(shift_net - period_net) < 0.05
    assert abs(
        shift_net
        - (
            float(row["expected_salary_pay"])
            - late_ded
            - ut_ded
        )
    ) < 0.05
    # Old bug: earned − late − UT collapsed far below period contribution.
    assert shift_net > earned - late_ded - ut_ded + 1.0


def test_hourly_shift_net_with_undertime_equals_earned():
    """Hourly earned already nets UT; shift_net must not subtract UT again."""
    shift, assignment = _shift_pair(time(8, 0), time(12, 0))
    record = _record(assignment, _ph(8, 0), _ph(11, 0))
    slip = _run(
        pay_basis=PayBasis.hourly,
        daily_rate=None,
        hourly_rate=100.0,
        rows=[(record, assignment, shift)],
        scheduled=[(assignment, shift)],
    )
    row = slip["attendance_records"][0]
    earned = float(row["earned"])
    ut_ded = float(row["undertime_deduction"])
    late_ded = float(row["late_deduction"])
    ot_pay = float(row.get("overtime_pay") or 0.0)
    rest_pay = float(row.get("rest_day_premium_pay") or 0.0)
    shift_net = float(row["shift_net"])

    assert ut_ded > 0
    assert abs(earned - (400.0 - ut_ded)) < 0.01
    assert earned > 0
    assert abs(shift_net - (earned + ot_pay + rest_pay)) < 0.01
    # Old bug: earned − late − UT collapsed toward ₱0.
    assert abs(shift_net - max(earned - late_ded - ut_ded, 0.0)) > 1.0


def test_hourly_shift_net_with_overtime_adds_ot_once():
    shift, assignment = _shift_pair(time(8, 0), time(12, 0))
    record = _record(assignment, _ph(8, 0), _ph(13, 0))
    slip = _run(
        pay_basis=PayBasis.hourly,
        daily_rate=None,
        hourly_rate=100.0,
        overtime_per_minute=1.0,
        ot_minimum=30,
        rows=[(record, assignment, shift)],
        scheduled=[(assignment, shift)],
    )
    row = slip["attendance_records"][0]
    earned = float(row["earned"])
    ut_ded = float(row["undertime_deduction"])
    ot_pay = float(row.get("overtime_pay") or 0.0)
    rest_pay = float(row.get("rest_day_premium_pay") or 0.0)
    shift_net = float(row["shift_net"])

    assert ut_ded == 0.0
    assert ot_pay > 0
    assert abs(earned - 400.0) < 0.01
    assert abs(shift_net - (earned + ot_pay + rest_pay)) < 0.01
    assert abs(shift_net - (earned + ot_pay)) < 0.01


def test_hourly_shift_net_undertime_plus_rest_premium_once():
    shift, assignment = _shift_pair(time(8, 0), time(12, 0))
    assignment.is_rest_day_work = True
    record = _record(assignment, _ph(8, 0), _ph(11, 0))
    slip = _run(
        pay_basis=PayBasis.hourly,
        daily_rate=None,
        hourly_rate=100.0,
        rest_premium=25.0,
        rows=[(record, assignment, shift)],
        scheduled=[(assignment, shift)],
    )
    row = slip["attendance_records"][0]
    earned = float(row["earned"])
    ut_ded = float(row["undertime_deduction"])
    ot_pay = float(row.get("overtime_pay") or 0.0)
    rest_pay = float(row.get("rest_day_premium_pay") or 0.0)
    shift_net = float(row["shift_net"])

    assert ut_ded > 0
    assert rest_pay > 0
    assert abs(rest_pay - earned * 0.25) < 0.02
    assert abs(shift_net - (earned + ot_pay + rest_pay)) < 0.01
    assert abs(shift_net - max(earned - ut_ded + rest_pay, 0.0)) > 1.0


def test_hourly_shift_net_undertime_and_overtime_adds_ot_without_double_ut():
    """When both UT and OT appear, shift_net = earned + OT (UT already in earned).

    Constructed as early leave relative to a long schedule is not combined with
    post-end OT on the same window; instead verify an OT-bearing full shift then
    confirm the Hourly formula never re-subtracts undertime_deduction.
    """
    shift, assignment = _shift_pair(time(8, 0), time(12, 0))
    # Partial shift (UT) — baseline already-netted earned.
    partial = _record(assignment, _ph(8, 0), _ph(11, 0))
    partial_slip = _run(
        pay_basis=PayBasis.hourly,
        daily_rate=None,
        hourly_rate=100.0,
        rows=[(partial, assignment, shift)],
        scheduled=[(assignment, shift)],
    )
    partial_row = partial_slip["attendance_records"][0]
    assert float(partial_row["undertime_deduction"]) > 0
    assert abs(
        float(partial_row["shift_net"]) - float(partial_row["earned"])
    ) < 0.01

    # Full + OT: OT added once; UT is zero so double-subtraction cannot hide.
    full_ot = _record(assignment, _ph(8, 0), _ph(13, 0))
    ot_slip = _run(
        pay_basis=PayBasis.hourly,
        daily_rate=None,
        hourly_rate=100.0,
        overtime_per_minute=1.0,
        ot_minimum=30,
        rows=[(full_ot, assignment, shift)],
        scheduled=[(assignment, shift)],
    )
    ot_row = ot_slip["attendance_records"][0]
    earned = float(ot_row["earned"])
    ot_pay = float(ot_row.get("overtime_pay") or 0.0)
    assert ot_pay > 0
    assert float(ot_row["undertime_deduction"]) == 0.0
    assert abs(float(ot_row["shift_net"]) - (earned + ot_pay)) < 0.01


def test_hourly_shift_net_full_shift_no_undertime():
    shift, assignment = _shift_pair(time(8, 0), time(12, 0))
    record = _record(assignment, _ph(8, 0), _ph(12, 0))
    slip = _run(
        pay_basis=PayBasis.hourly,
        daily_rate=None,
        hourly_rate=100.0,
        rows=[(record, assignment, shift)],
        scheduled=[(assignment, shift)],
    )
    row = slip["attendance_records"][0]
    assert float(row["undertime_deduction"]) == 0.0
    assert abs(float(row["earned"]) - 400.0) < 0.01
    assert abs(float(row["shift_net"]) - float(row["earned"])) < 0.01


def test_hourly_shift_net_bianca_pattern_long_schedule_undertime():
    """Synthetic Bianca-style Hourly: long schedule, ~9.5h worked, positive earned.

    Expected salary ₱1500 (1200 min × ₱75/h), undertime pesos large, earned ≈
    ₱716.75; shift_net must match earned (not ₱0 from double UT).
    """
    shift, assignment = _shift_pair(time(3, 40), time(23, 40))
    record = _record(assignment, _ph(3, 41), _ph(13, 13))
    slip = _run(
        pay_basis=PayBasis.hourly,
        daily_rate=None,
        hourly_rate=75.0,
        rows=[(record, assignment, shift)],
        scheduled=[(assignment, shift)],
        grace_minutes=5,
    )
    row = slip["attendance_records"][0]
    earned = float(row["earned"])
    expected = float(row["expected_salary_pay"])
    ut_ded = float(row["undertime_deduction"])
    shift_net = float(row["shift_net"])
    ot_pay = float(row.get("overtime_pay") or 0.0)
    rest_pay = float(row.get("rest_day_premium_pay") or 0.0)

    assert abs(expected - 1500.0) < 0.01
    assert abs(ut_ded - 783.25) < 1.0
    assert abs(earned - 716.75) < 1.0
    assert earned > 700.0
    assert ot_pay == 0.0
    assert rest_pay == 0.0
    assert abs(shift_net - earned) < 0.01
    assert abs(shift_net - (expected - ut_ded)) < 0.01
    assert shift_net > 700.0
    # Old bug: double-subtract UT → ₱0
    assert abs(shift_net - max(earned - ut_ded, 0.0)) > 1.0


# Back-compat alias for the renamed Hourly undertime regression.
def test_hourly_shift_net_unchanged_with_undertime():
    test_hourly_shift_net_with_undertime_equals_earned()


def test_daily_shift_net_uses_historical_stamp_not_current_rate():
    employee_id = uuid4()
    business_id = uuid4()
    employee = SimpleNamespace(
        id=employee_id,
        business_id=business_id,
        full_name="Hist",
        position_title="Staff",
        position_id=uuid4(),
        employment_type=EmploymentType.full_time,
        pay_basis=PayBasis.daily,
        daily_rate=999.0,
        hourly_rate=None,
        monthly_salary=None,
    )
    shift = Shift(
        id=uuid4(),
        business_id=business_id,
        name="Shift",
        start_time=time(8, 0),
        end_time=time(16, 0),
        break_minutes=0,
    )
    assignment = ShiftAssignment(
        id=uuid4(),
        shift_id=shift.id,
        employee_id=employee_id,
        work_date=date(2026, 8, 4),
        is_rest_day_work=False,
    )
    record = AttendanceRecord(
        id=uuid4(),
        business_id=business_id,
        employee_id=employee_id,
        shift_assignment_id=assignment.id,
        time_in=_ph(8, 0),
        time_out=_ph(15, 0),
        status=AttendanceStatus.complete,
        pay_basis_at_completion=PayBasis.daily,
        daily_rate_at_completion=480.0,
        hourly_rate_at_completion=None,
        monthly_salary_at_completion=None,
    )
    slip = _run_payslip(
        employee=employee,
        rows=[(record, assignment, shift)],
        scheduled=[(assignment, shift)],
    )
    row = slip["attendance_records"][0]
    assert row["rate_used"] == 480.0
    assert abs(float(slip["regular_pay"]) - 480.0) < 0.01
    period_net = (
        float(slip["regular_pay"])
        - float(slip["late_deductions"])
        - float(slip["undertime_deductions"])
    )
    assert abs(float(row["shift_net"]) - period_net) < 0.05
    assert abs(float(row["expected_salary_pay"]) - 480.0) < 0.01


def test_finalized_snapshot_preserves_shift_net_immutably():
    frozen = freeze_payslip_dict(
        {
            "regular_pay": 250.0,
            "net_pay": 88.97,
            "attendance_records": [
                {"earned": 88.97, "shift_net": 88.97, "undertime_deduction": 161.03}
            ],
        }
    )
    assert frozen["attendance_records"][0]["shift_net"] == 88.97
    assert frozen["snapshot_version"] == 1


def test_shift_history_report_exposes_corrected_daily_shift_net():
    slip = {
        "employee_id": str(uuid4()),
        "employee_name": "N",
        "position_title": "Staff",
        "pay_basis": "daily",
        "daily_rate": 250.0,
        "hourly_rate": None,
        "monthly_salary": None,
        "attendance_records": [
            {
                "date": "2026-08-04",
                "status": "complete",
                "shift_name": "Afternoon",
                "time_in": "2026-08-04T05:00:00+00:00",
                "time_out": "2026-08-04T05:42:42+00:00",
                "worked_minutes": 42.71,
                "earned": 88.97,
                "expected_salary_pay": 250.0,
                "late_deduction": 0.0,
                "undertime_deduction": 161.03,
                "shortfall_deduction": 161.03,
                "shift_net": 88.97,
                "historical_rate_required": False,
                "payroll_status": "finalized",
                "pay_basis_used": "daily",
                "rate_used": 250.0,
            }
        ],
    }
    loaded = PeriodPayrollLoad(
        period_start=date(2026, 8, 1),
        period_end=date(2026, 8, 15),
        from_snapshot=True,
        payroll_run=None,
        entries=[(None, slip)],
    )
    db = MagicMock()
    db.get.side_effect = lambda model, key=None: (
        SimpleNamespace(timezone="Asia/Manila") if model is Business else None
    )
    user = SimpleNamespace(business_id=uuid4(), id=uuid4())
    with patch("app.api.owner_reports.load_period_payroll", return_value=loaded):
        result = shift_history_report(db=db, user=user, as_of=date(2026, 8, 4))
    item = result["items"][0]
    assert abs(float(item["shift_net"]) - 88.97) < 0.01
    assert abs(float(item["earned"]) - 88.97) < 0.01
