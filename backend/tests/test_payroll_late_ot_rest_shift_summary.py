"""Shift-summary components: late, overtime, and rest-day premium.

Locks the existing payroll rules for the combinations an owner shift
summary must show. Does not change late policy, OT approval, or rest
premium rates. Generic fixtures only — no employee names or live dates.
"""

from __future__ import annotations

from datetime import time

from app.models.enums import AttendanceStatus, OvertimeApprovalStatus, PayBasis
from app.services.payroll_engine import overtime_pay_amount
from tests.test_payroll_engine import _ph, _record, _run, _shift_pair


DAILY = 350.0
REST_PCT = 10.0
LATE_RATE = 1.0
OT_RATE = 1.0


def _near(actual, expected) -> None:
    assert abs(float(actual or 0) - expected) < 0.02, (actual, expected)


def _day_shift(*, rest: bool = False):
    shift, assignment = _shift_pair(time(8, 0), time(17, 0), name="Day")
    assignment.is_rest_day_work = rest
    return shift, assignment


def _evening_shift(*, rest: bool = False):
    shift, assignment = _shift_pair(time(18, 30), time(22, 0), name="Evening")
    assignment.is_rest_day_work = rest
    return shift, assignment


def _slip(
    shift,
    assignment,
    time_in,
    time_out,
    *,
    status=AttendanceStatus.complete,
    rest_premium: float | None = None,
    enable_late_overtime_balancing: bool = False,
    overtime_approval_required: bool = False,
    ot_approval_status=None,
    ot_minimum: int = 10,
    grace_minutes: int = 10,
):
    record = _record(assignment, time_in, time_out, status=status)
    if ot_approval_status is not None:
        record.ot_approval_status = ot_approval_status
    return _run(
        pay_basis=PayBasis.daily,
        daily_rate=DAILY,
        rows=[(record, assignment, shift)],
        scheduled=[(assignment, shift)],
        rest_premium=rest_premium,
        enable_late_overtime_balancing=enable_late_overtime_balancing,
        overtime_approval_required=overtime_approval_required,
        ot_minimum=ot_minimum,
        grace_minutes=grace_minutes,
        late_deduction_per_minute=LATE_RATE,
        overtime_per_minute=OT_RATE,
        ordinary_ot=0.0,
        rest_day_ot=0.0,
    )


def _row(slip: dict) -> dict:
    rows = slip["attendance_records"]
    assert len(rows) == 1
    return rows[0]


def test_late_only_applies_configured_deduction():
    """Late employee, configured late deduction, no overtime."""
    shift, assignment = _day_shift()
    slip = _slip(
        shift,
        assignment,
        _ph(8, 30),
        _ph(17, 0),
        status=AttendanceStatus.late,
    )
    row = _row(slip)
    _near(row["late_minutes"], 20.0)
    _near(row["late_deduction"], 20.0 * LATE_RATE)
    _near(slip["late_deductions"], 20.0 * LATE_RATE)
    _near(slip["overtime_pay"], 0.0)
    _near(slip["rest_day_pay"], 0.0)
    _near(row["shift_net"], DAILY - 20.0)


def test_overtime_only_pays_configured_rate():
    """Valid overtime, no lateness."""
    shift, assignment = _day_shift()
    slip = _slip(shift, assignment, _ph(8, 0), _ph(18, 0))
    row = _row(slip)
    expected_ot = overtime_pay_amount(60.0, OT_RATE, 0.0)
    _near(row["late_deduction"], 0.0)
    _near(row["overtime_minutes"], 60.0)
    _near(row["overtime_pay"], expected_ot)
    _near(slip["overtime_pay"], expected_ot)
    _near(row["shift_net"], DAILY + expected_ot)


def test_late_and_overtime_same_shift_are_independent_when_balancing_off():
    """Both lateness and overtime on the same shift, balancing off."""
    shift, assignment = _day_shift()
    slip = _slip(
        shift,
        assignment,
        _ph(8, 30),
        _ph(18, 0),
        status=AttendanceStatus.late,
        enable_late_overtime_balancing=False,
    )
    row = _row(slip)
    expected_ot = overtime_pay_amount(60.0, OT_RATE, 0.0)
    _near(row["late_deduction"], 20.0)
    _near(row["overtime_pay"], expected_ot)
    _near(slip["late_deductions"], 20.0)
    _near(slip["overtime_pay"], expected_ot)
    _near(row["shift_net"], DAILY + expected_ot - 20.0)


def test_rest_day_premium_only():
    """Rest-day premium only — on time, no overtime."""
    shift, assignment = _day_shift(rest=True)
    slip = _slip(
        shift,
        assignment,
        _ph(8, 0),
        _ph(17, 0),
        rest_premium=REST_PCT,
    )
    row = _row(slip)
    rest = DAILY * REST_PCT / 100.0
    _near(slip["rest_day_pay"], rest)
    _near(row["day_rest_day_pay"], rest)
    assert row["rest_day_premium_pay"] in (None, 0.0)
    _near(row["late_deduction"], 0.0)
    _near(row["overtime_pay"], 0.0)
    _near(row["shift_net"], DAILY)
    _near(row["reconciled_day_total"], DAILY + rest)


def test_late_overtime_and_rest_day_coexist_when_balancing_off():
    """Late + OT + rest-day premium on one shift when existing rules allow it."""
    shift, assignment = _day_shift(rest=True)
    slip = _slip(
        shift,
        assignment,
        _ph(8, 30),
        _ph(18, 0),
        status=AttendanceStatus.late,
        rest_premium=REST_PCT,
        enable_late_overtime_balancing=False,
    )
    row = _row(slip)
    expected_ot = overtime_pay_amount(60.0, OT_RATE, 0.0)
    rest = DAILY * REST_PCT / 100.0
    _near(row["late_deduction"], 20.0)
    _near(row["overtime_pay"], expected_ot)
    _near(slip["late_deductions"], 20.0)
    _near(slip["overtime_pay"], expected_ot)
    _near(slip["rest_day_pay"], rest)
    _near(row["day_rest_day_pay"], rest)
    _near(row["shift_net"], DAILY + expected_ot - 20.0)
    _near(row["reconciled_day_total"], DAILY + expected_ot + rest - 20.0)
    _near(
        slip["net_pay"],
        slip["regular_pay"]
        + slip["overtime_pay"]
        + slip["rest_day_pay"]
        - slip["late_deductions"],
    )
    assert slip["rest_day_days"] == 1


def test_grace_period_has_no_late_deduction():
    """Clock-in inside grace: no late deduction."""
    shift, assignment = _day_shift()
    slip = _slip(
        shift,
        assignment,
        _ph(8, 5),
        _ph(17, 0),
        status=AttendanceStatus.complete,
        grace_minutes=10,
    )
    row = _row(slip)
    _near(row["late_minutes"], 0.0)
    _near(row["late_deduction"], 0.0)
    _near(slip["late_deductions"], 0.0)


def test_unapproved_overtime_is_not_payable():
    """OT approval required and pending: worked OT is not paid."""
    shift, assignment = _day_shift()
    slip = _slip(
        shift,
        assignment,
        _ph(8, 0),
        _ph(18, 0),
        overtime_approval_required=True,
        ot_approval_status=OvertimeApprovalStatus.pending,
    )
    row = _row(slip)
    _near(slip["worked_overtime_minutes"], 60.0)
    _near(slip["pending_overtime_minutes"], 60.0)
    _near(slip["overtime_pay"], 0.0)
    _near(row["overtime_pay"], 0.0)
    _near(row["overtime_minutes"], 0.0)


def test_rest_day_premium_not_changed_or_duplicated_by_late_or_ot():
    """Rest-day premium stays one 10% credit whether late/OT exist or not."""
    on_time_shift, on_time_asg = _day_shift(rest=True)
    mixed_shift, mixed_asg = _day_shift(rest=True)
    on_time = _slip(
        on_time_shift,
        on_time_asg,
        _ph(8, 0),
        _ph(17, 0),
        rest_premium=REST_PCT,
    )
    mixed = _slip(
        mixed_shift,
        mixed_asg,
        _ph(8, 30),
        _ph(18, 0),
        status=AttendanceStatus.late,
        rest_premium=REST_PCT,
        enable_late_overtime_balancing=False,
    )
    rest = DAILY * REST_PCT / 100.0
    _near(on_time["rest_day_pay"], rest)
    _near(mixed["rest_day_pay"], rest)
    assert on_time["rest_day_days"] == 1
    assert mixed["rest_day_days"] == 1
    _near(_row(on_time)["day_rest_day_pay"], rest)
    _near(_row(mixed)["day_rest_day_pay"], rest)


def test_shift_summary_matches_calculated_components():
    """Shift-summary fields agree with the underlying calculated components."""
    shift, assignment = _day_shift(rest=True)
    slip = _slip(
        shift,
        assignment,
        _ph(8, 30),
        _ph(18, 0),
        status=AttendanceStatus.late,
        rest_premium=REST_PCT,
        enable_late_overtime_balancing=False,
    )
    row = _row(slip)
    late = float(row["late_deduction"])
    ot = float(row["overtime_pay"])
    rest = float(row["day_rest_day_pay"])
    expected = float(row["expected_salary_pay"])
    _near(row["shift_net"], expected + ot - late)
    _near(row["reconciled_day_total"], float(row["shift_net"]) + rest)
    _near(
        slip["gross_pay"],
        slip["regular_pay"] + slip["overtime_pay"] + slip["rest_day_pay"],
    )
    _near(slip["net_pay"], slip["gross_pay"] - slip["late_deductions"])
    _near(slip["late_deductions"], late)
    _near(slip["overtime_pay"], ot)
    _near(slip["rest_day_pay"], rest)


def test_balancing_then_ot_minimum_clears_late_and_unqualified_ot_rest_once():
    """Makeup minutes after end offset late; leftover below OT minimum is unpaid.

    Rest-day premium is unchanged and counted once. Mirrors the live evening
    rest-day case where remaining OT after recovery is under the minimum.
    """
    shift, assignment = _evening_shift(rest=True)
    slip = _slip(
        shift,
        assignment,
        _ph(18, 50),
        _ph(22, 24),
        status=AttendanceStatus.late,
        rest_premium=REST_PCT,
        enable_late_overtime_balancing=True,
        overtime_approval_required=True,
        ot_minimum=10,
        grace_minutes=10,
    )
    row = _row(slip)
    rest = DAILY * REST_PCT / 100.0
    _near(row["late_deduction"], 0.0)
    _near(slip["late_deductions"], 0.0)
    _near(row["overtime_pay"], 0.0)
    _near(slip["overtime_pay"], 0.0)
    _near(slip["worked_overtime_minutes"], 0.0)
    assert float(row["ot"]["time_recovered_minutes"]) > 0
    _near(slip["rest_day_pay"], rest)
    _near(row["day_rest_day_pay"], rest)
    _near(row["shift_net"], DAILY)
    _near(row["reconciled_day_total"], DAILY + rest)
    assert slip["rest_day_days"] == 1
