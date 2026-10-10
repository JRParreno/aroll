"""Shift History totals stay aligned with payslip fields.

Payroll money still comes from ``_calculate_employee_payslip``. These tests
check that shift and day history fields do not drop hourly late, subtract
undertime twice, or credit a daily entitlement or date premium twice.
"""

from __future__ import annotations

from datetime import date, time
from types import SimpleNamespace
from unittest.mock import patch
from uuid import uuid4

from app.api.employee_mobile import _overlay_shift_history_with_finalized_snapshots
from app.models.enums import AttendanceStatus, HolidayType, PayBasis
from app.models.holiday import Holiday
from app.services.payroll_snapshot import PAYSLIP_SNAPSHOT_VERSION, freeze_payslip_dict
from tests.test_payroll_engine import _ph, _record, _run, _shift_pair


WORK = date(2026, 8, 4)


def _near(actual, expected) -> None:
    assert abs(float(actual or 0) - expected) < 0.02


def _rows(slip):
    return [row for row in slip["attendance_records"] if row["date"] == WORK.isoformat()]


def _stamp(record, basis: PayBasis, *, daily=None, hourly=None):
    record.pay_basis_at_completion = basis
    record.daily_rate_at_completion = daily
    record.hourly_rate_at_completion = hourly
    record.monthly_salary_at_completion = None
    return record


def _pair(start: time, end: time, name: str, *, rest: bool = False):
    shift, assignment = _shift_pair(start, end, name=name, work_date=WORK)
    assignment.is_rest_day_work = rest
    return shift, assignment


def _full(assignment, shift):
    return _record(
        assignment,
        _ph(shift.start_time.hour, shift.start_time.minute, day=WORK.day),
        _ph(shift.end_time.hour, shift.end_time.minute, day=WORK.day),
    )


def _holiday():
    return Holiday(
        id=uuid4(),
        business_id=uuid4(),
        name="Company Holiday",
        holiday_date=WORK,
        is_paid=True,
        pay_multiplier=2,
        holiday_type=HolidayType.company,
        is_active=True,
    )


def _assert_payslip_identity(slip) -> None:
    gross = (
        float(slip["regular_pay"])
        + float(slip["leave_pay"])
        + float(slip["overtime_pay"])
        + float(slip["holiday_pay"])
        + float(slip["rest_day_pay"])
    )
    _near(slip["gross_pay"], gross)
    _near(
        slip["net_pay"],
        max(
            gross
            - float(slip["late_deductions"])
            - float(slip["undertime_deductions"]),
            0,
        ),
    )


def _assert_day_matches_net(slip) -> None:
    rows = _rows(slip)
    assert rows
    _near(rows[0]["reconciled_day_total"], slip["net_pay"])
    assert all(
        row["reconciled_day_total"] == rows[0]["reconciled_day_total"] for row in rows
    )


def test_a_hourly_plus_hourly_rest_each_row_once():
    first_shift, first_asg = _pair(time(15, 30), time(18, 0), "Evening", rest=True)
    second_shift, second_asg = _pair(time(18, 30), time(20, 0), "Morning", rest=True)
    slip = _run(
        pay_basis=PayBasis.hourly,
        daily_rate=None,
        hourly_rate=100.0,
        rest_premium=30.0,
        rows=[
            (_full(first_asg, first_shift), first_asg, first_shift),
            (_full(second_asg, second_shift), second_asg, second_shift),
        ],
        scheduled=[(first_asg, first_shift), (second_asg, second_shift)],
    )
    rows = _rows(slip)
    _near(slip["regular_pay"], 400)
    _near(slip["rest_day_pay"], 120)
    _near(slip["gross_pay"], 520)
    _near(rows[0]["expected_salary_pay"], 250)
    _near(rows[0]["rest_day_premium_pay"], 75)
    _near(rows[0]["shift_net"], 325)
    _near(rows[1]["expected_salary_pay"], 150)
    _near(rows[1]["rest_day_premium_pay"], 45)
    _near(rows[1]["shift_net"], 195)
    _near(rows[0]["day_rest_day_pay"], 0)
    _assert_payslip_identity(slip)
    _assert_day_matches_net(slip)


def test_b_daily_plus_daily_credits_entitlement_once():
    first_shift, first_asg = _pair(time(15, 30), time(18, 0), "Evening")
    second_shift, second_asg = _pair(time(18, 30), time(20, 0), "Morning")
    slip = _run(
        pay_basis=PayBasis.daily,
        daily_rate=350.0,
        hourly_rate=None,
        rows=[
            (_full(first_asg, first_shift), first_asg, first_shift),
            (_full(second_asg, second_shift), second_asg, second_shift),
        ],
        scheduled=[(first_asg, first_shift), (second_asg, second_shift)],
    )
    rows = _rows(slip)
    _near(slip["regular_pay"], 350)
    _near(slip["gross_pay"], 350)
    assert all(float(row["expected_salary_pay"]) == 350.0 for row in rows)
    assert all(float(row["earned"]) != 350.0 for row in rows)
    assert float(rows[0]["shift_net"]) == 350.0
    assert float(rows[1]["shift_net"]) == 350.0
    _near(rows[0]["reconciled_day_total"], 350)
    assert rows[0]["reconciled_day_total"] != 700
    _assert_payslip_identity(slip)
    _assert_day_matches_net(slip)


def test_c_hourly_plus_daily_rest_day_is_780():
    hourly_shift, hourly_asg = _pair(time(15, 30), time(18, 0), "Evening", rest=True)
    daily_shift, daily_asg = _pair(time(18, 30), time(20, 0), "Morning", rest=True)
    hourly = _stamp(_full(hourly_asg, hourly_shift), PayBasis.hourly, hourly=100.0)
    daily = _stamp(_full(daily_asg, daily_shift), PayBasis.daily, daily=350.0)
    slip = _run(
        pay_basis=PayBasis.daily,
        daily_rate=350.0,
        hourly_rate=100.0,
        rest_premium=30.0,
        rows=[
            (hourly, hourly_asg, hourly_shift),
            (daily, daily_asg, daily_shift),
        ],
        scheduled=[(hourly_asg, hourly_shift), (daily_asg, daily_shift)],
    )
    rows = _rows(slip)
    hourly_row, daily_row = rows
    _near(slip["regular_pay"], 600)
    _near(slip["rest_day_pay"], 180)
    _near(slip["gross_pay"], 780)
    _near(hourly_row["expected_salary_pay"], 250)
    _near(hourly_row["rest_day_premium_pay"], 75)
    _near(hourly_row["shift_net"], 325)
    _near(hourly_row["reconciled_shift_total"], 325)
    _near(daily_row["expected_salary_pay"], 350)
    assert daily_row.get("rest_day_premium_pay") in (None, 0, 0.0)
    assert float(daily_row["earned"]) != 350.0
    _near(daily_row["day_rest_day_pay"], 105)
    _near(daily_row["shift_net"], 350)
    _near(rows[0]["day_rest_day_pay"], 105)
    _near(rows[0]["reconciled_day_total"], 780)
    _assert_payslip_identity(slip)
    _assert_day_matches_net(slip)


def test_d_daily_plus_hourly_rest_day_is_650():
    daily_shift, daily_asg = _pair(time(17, 0), time(19, 0), "Evening", rest=True)
    hourly_shift, hourly_asg = _pair(time(19, 30), time(21, 0), "Morning", rest=True)
    daily = _stamp(_full(daily_asg, daily_shift), PayBasis.daily, daily=350.0)
    hourly = _stamp(_full(hourly_asg, hourly_shift), PayBasis.hourly, hourly=100.0)
    slip = _run(
        pay_basis=PayBasis.hourly,
        daily_rate=None,
        hourly_rate=100.0,
        rest_premium=30.0,
        rows=[
            (daily, daily_asg, daily_shift),
            (hourly, hourly_asg, hourly_shift),
        ],
        scheduled=[(daily_asg, daily_shift), (hourly_asg, hourly_shift)],
    )
    rows = _rows(slip)
    _near(slip["regular_pay"], 500)
    _near(slip["rest_day_pay"], 150)
    _near(slip["gross_pay"], 650)
    _near(rows[0]["expected_salary_pay"], 350)
    _near(rows[0]["day_rest_day_pay"], 105)
    _near(rows[0]["shift_net"], 350)
    _near(rows[1]["expected_salary_pay"], 150)
    _near(rows[1]["rest_day_premium_pay"], 45)
    _near(rows[1]["shift_net"], 195)
    _near(rows[0]["reconciled_day_total"], 650)
    _assert_payslip_identity(slip)
    _assert_day_matches_net(slip)


def test_e_hourly_late_is_in_shift_net_once():
    shift, assignment = _pair(time(8, 0), time(12, 0), "Hourly")
    record = _record(assignment, _ph(8, 30), _ph(12, 0), status=AttendanceStatus.late)
    slip = _run(
        pay_basis=PayBasis.hourly,
        daily_rate=None,
        hourly_rate=100.0,
        rows=[(record, assignment, shift)],
        scheduled=[(assignment, shift)],
    )
    row = _rows(slip)[0]
    late = float(row["late_deduction"])
    assert late == 20.0
    _near(slip["regular_pay"], 400)
    _near(slip["gross_pay"], 400)
    _near(slip["late_deductions"], 20)
    _near(slip["net_pay"], 380)
    _near(row["expected_salary_pay"], 400)
    _near(row["earned"], 400)
    _near(row["shift_net"], 380)
    _near(row["reconciled_shift_total"], 380)
    assert abs(float(row["shift_net"]) - (float(row["earned"]) - late)) < 0.01
    _assert_payslip_identity(slip)
    _assert_day_matches_net(slip)


def test_f_hourly_undertime_is_not_subtracted_twice():
    shift, assignment = _pair(time(8, 0), time(12, 0), "Hourly")
    record = _record(assignment, _ph(8, 0), _ph(11, 0))
    slip = _run(
        pay_basis=PayBasis.hourly,
        daily_rate=None,
        hourly_rate=100.0,
        rows=[(record, assignment, shift)],
        scheduled=[(assignment, shift)],
    )
    row = _rows(slip)[0]
    ut = float(row["undertime_deduction"])
    assert ut > 0
    assert float(row["late_deduction"]) == 0.0
    _near(row["expected_salary_pay"], 400)
    _near(row["earned"], 400 - ut)
    _near(row["shift_net"], float(row["earned"]))
    assert abs(float(row["shift_net"]) - max(float(row["earned"]) - ut, 0)) > 1
    _assert_payslip_identity(slip)
    _assert_day_matches_net(slip)


def test_g_hourly_late_and_undertime_each_once():
    shift, assignment = _pair(time(8, 0), time(12, 0), "Hourly")
    record = _record(assignment, _ph(8, 30), _ph(11, 0), status=AttendanceStatus.late)
    slip = _run(
        pay_basis=PayBasis.hourly,
        daily_rate=None,
        hourly_rate=100.0,
        rows=[(record, assignment, shift)],
        scheduled=[(assignment, shift)],
    )
    row = _rows(slip)[0]
    late = float(row["late_deduction"])
    ut = float(row["undertime_deduction"])
    assert late == 20.0
    assert ut > 0
    _near(slip["gross_pay"], 400)
    _near(row["earned"], 400 - ut)
    _near(row["shift_net"], float(row["earned"]) - late)
    _near(slip["net_pay"], 400 - late - ut)
    _assert_payslip_identity(slip)
    _assert_day_matches_net(slip)


def test_h_daily_late_stays_on_shift_one():
    first_shift, first_asg = _pair(time(8, 0), time(12, 0), "One")
    second_shift, second_asg = _pair(time(13, 0), time(17, 0), "Two")
    late = _record(first_asg, _ph(8, 30), _ph(12, 0), status=AttendanceStatus.late)
    slip = _run(
        pay_basis=PayBasis.daily,
        daily_rate=350.0,
        hourly_rate=None,
        rows=[
            (late, first_asg, first_shift),
            (_full(second_asg, second_shift), second_asg, second_shift),
        ],
        scheduled=[(first_asg, first_shift), (second_asg, second_shift)],
    )
    rows = _rows(slip)
    assert float(rows[0]["late_deduction"]) == 20.0
    assert float(rows[1]["late_deduction"]) == 0.0
    _near(slip["regular_pay"], 350)
    _near(slip["gross_pay"], 350)
    _near(slip["net_pay"], 330)
    _near(rows[0]["shift_net"], 330)
    _near(rows[1]["shift_net"], 350)
    _near(rows[0]["reconciled_day_total"], 330)
    _assert_payslip_identity(slip)
    _assert_day_matches_net(slip)


def test_i_daily_undertime_stays_on_shift_two():
    first_shift, first_asg = _pair(time(8, 0), time(12, 0), "One")
    second_shift, second_asg = _pair(time(13, 0), time(17, 0), "Two")
    early = _record(second_asg, _ph(13, 0), _ph(16, 0))
    slip = _run(
        pay_basis=PayBasis.daily,
        daily_rate=350.0,
        hourly_rate=None,
        rows=[
            (_full(first_asg, first_shift), first_asg, first_shift),
            (early, second_asg, second_shift),
        ],
        scheduled=[(first_asg, first_shift), (second_asg, second_shift)],
    )
    rows = _rows(slip)
    assert float(rows[0]["undertime_deduction"]) == 0.0
    ut = float(rows[1]["undertime_deduction"])
    assert ut > 0
    _near(slip["regular_pay"], 350)
    _near(slip["net_pay"], 350 - ut)
    _near(rows[1]["shift_net"], 350 - ut)
    _near(rows[0]["reconciled_day_total"], 350 - ut)
    _assert_payslip_identity(slip)
    _assert_day_matches_net(slip)


def test_j_daily_late_and_undertime_stay_on_their_shifts():
    first_shift, first_asg = _pair(time(8, 0), time(12, 0), "One")
    second_shift, second_asg = _pair(time(13, 0), time(17, 0), "Two")
    late = _record(first_asg, _ph(8, 30), _ph(12, 0), status=AttendanceStatus.late)
    early = _record(second_asg, _ph(13, 0), _ph(16, 0))
    slip = _run(
        pay_basis=PayBasis.daily,
        daily_rate=350.0,
        hourly_rate=None,
        rows=[
            (late, first_asg, first_shift),
            (early, second_asg, second_shift),
        ],
        scheduled=[(first_asg, first_shift), (second_asg, second_shift)],
    )
    rows = _rows(slip)
    late_pay = float(rows[0]["late_deduction"])
    ut = float(rows[1]["undertime_deduction"])
    assert late_pay == 20.0
    assert ut > 0
    assert float(rows[1]["late_deduction"]) == 0.0
    assert float(rows[0]["undertime_deduction"]) == 0.0
    _near(slip["regular_pay"], 350)
    _near(slip["net_pay"], 350 - late_pay - ut)
    _near(rows[0]["shift_net"], 350 - late_pay)
    _near(rows[1]["shift_net"], 350 - ut)
    _near(rows[0]["reconciled_day_total"], 350 - late_pay - ut)
    _assert_payslip_identity(slip)
    _assert_day_matches_net(slip)


def test_k_mixed_rest_day_premium_is_not_paid_twice():
    hourly_shift, hourly_asg = _pair(time(15, 30), time(18, 0), "Evening", rest=True)
    daily_shift, daily_asg = _pair(time(18, 30), time(20, 0), "Morning", rest=True)
    slip = _run(
        pay_basis=PayBasis.hourly,
        daily_rate=None,
        hourly_rate=100.0,
        rest_premium=30.0,
        rows=[
            (
                _stamp(_full(hourly_asg, hourly_shift), PayBasis.hourly, hourly=100.0),
                hourly_asg,
                hourly_shift,
            ),
            (
                _stamp(_full(daily_asg, daily_shift), PayBasis.daily, daily=350.0),
                daily_asg,
                daily_shift,
            ),
        ],
        scheduled=[(hourly_asg, hourly_shift), (daily_asg, daily_shift)],
    )
    rows = _rows(slip)
    _near(slip["rest_day_pay"], 180)
    _near(sum(float(row.get("rest_day_premium_pay") or 0) for row in rows), 75)
    _near(rows[0]["day_rest_day_pay"], 105)
    _near(rows[1]["day_rest_day_pay"], 105)
    _near(rows[0]["reconciled_day_total"], 780)
    assert rows[0]["reconciled_day_total"] != 780 + 105


def test_l_two_daily_rest_premium_once():
    first_shift, first_asg = _pair(time(15, 30), time(18, 0), "One", rest=True)
    second_shift, second_asg = _pair(time(18, 30), time(20, 0), "Two", rest=True)
    slip = _run(
        pay_basis=PayBasis.daily,
        daily_rate=350.0,
        hourly_rate=None,
        rest_premium=30.0,
        rows=[
            (_full(first_asg, first_shift), first_asg, first_shift),
            (_full(second_asg, second_shift), second_asg, second_shift),
        ],
        scheduled=[(first_asg, first_shift), (second_asg, second_shift)],
    )
    rows = _rows(slip)
    _near(slip["regular_pay"], 350)
    _near(slip["rest_day_pay"], 105)
    _near(slip["gross_pay"], 455)
    assert all(row.get("rest_day_premium_pay") in (None, 0, 0.0) for row in rows)
    assert all(float(row["day_rest_day_pay"]) == 105.0 for row in rows)
    _near(rows[0]["reconciled_day_total"], 455)
    assert rows[0]["reconciled_day_total"] != 455 + 105
    _assert_day_matches_net(slip)


def test_m_mixed_holiday_premium_once():
    hourly_shift, hourly_asg = _pair(time(15, 30), time(18, 0), "Evening")
    daily_shift, daily_asg = _pair(time(18, 30), time(20, 0), "Morning")
    slip = _run(
        pay_basis=PayBasis.hourly,
        daily_rate=None,
        hourly_rate=100.0,
        holidays=[_holiday()],
        rows=[
            (
                _stamp(_full(hourly_asg, hourly_shift), PayBasis.hourly, hourly=100.0),
                hourly_asg,
                hourly_shift,
            ),
            (
                _stamp(_full(daily_asg, daily_shift), PayBasis.daily, daily=350.0),
                daily_asg,
                daily_shift,
            ),
        ],
        scheduled=[(hourly_asg, hourly_shift), (daily_asg, daily_shift)],
    )
    rows = _rows(slip)
    _near(slip["regular_pay"], 600)
    _near(slip["holiday_pay"], 600)
    _near(slip["gross_pay"], 1200)
    _near(rows[0]["holiday_pay"], 250)
    _near(rows[1]["holiday_pay"], 0)
    _near(rows[0]["day_holiday_pay"], 350)
    _near(rows[1]["day_holiday_pay"], 350)
    assert rows[1]["holiday_included_in_shift_net"] is False
    _near(rows[0]["reconciled_day_total"], 1200)
    assert rows[0]["reconciled_day_total"] != 1200 + 350
    _assert_payslip_identity(slip)
    _assert_day_matches_net(slip)


def test_n_two_daily_holiday_premium_once():
    first_shift, first_asg = _pair(time(15, 30), time(18, 0), "One")
    second_shift, second_asg = _pair(time(18, 30), time(20, 0), "Two")
    slip = _run(
        pay_basis=PayBasis.daily,
        daily_rate=350.0,
        hourly_rate=None,
        holidays=[_holiday()],
        rows=[
            (_full(first_asg, first_shift), first_asg, first_shift),
            (_full(second_asg, second_shift), second_asg, second_shift),
        ],
        scheduled=[(first_asg, first_shift), (second_asg, second_shift)],
    )
    rows = _rows(slip)
    _near(slip["regular_pay"], 350)
    _near(slip["holiday_pay"], 350)
    _near(slip["gross_pay"], 700)
    assert all(float(row["holiday_pay"]) == 0.0 for row in rows)
    assert all(float(row["day_holiday_pay"]) == 350.0 for row in rows)
    _near(rows[0]["reconciled_day_total"], 700)
    assert rows[0]["reconciled_day_total"] != sum(
        float(row["shift_net"]) for row in rows
    ) + 350
    _assert_day_matches_net(slip)


def test_o_holiday_and_rest_together_once():
    first_shift, first_asg = _pair(time(15, 30), time(18, 0), "One", rest=True)
    second_shift, second_asg = _pair(time(18, 30), time(20, 0), "Two", rest=True)
    slip = _run(
        pay_basis=PayBasis.daily,
        daily_rate=350.0,
        hourly_rate=None,
        rest_premium=30.0,
        holidays=[_holiday()],
        rows=[
            (_full(first_asg, first_shift), first_asg, first_shift),
            (_full(second_asg, second_shift), second_asg, second_shift),
        ],
        scheduled=[(first_asg, first_shift), (second_asg, second_shift)],
    )
    rows = _rows(slip)
    _near(slip["regular_pay"], 350)
    _near(slip["holiday_pay"], 350)
    _near(slip["rest_day_pay"], 105)
    _near(slip["gross_pay"], 805)
    assert all(float(row["day_holiday_pay"]) == 350.0 for row in rows)
    assert all(float(row["day_rest_day_pay"]) == 105.0 for row in rows)
    _near(rows[0]["reconciled_day_total"], 805)
    _assert_day_matches_net(slip)


def test_p_paid_leave_is_credited_once():
    first_shift, first_asg = _pair(time(8, 0), time(12, 0), "One")
    second_shift, second_asg = _pair(time(13, 0), time(17, 0), "Two")
    slip = _run(
        pay_basis=PayBasis.daily,
        daily_rate=350.0,
        hourly_rate=None,
        leave_paid=True,
        rows=[
            (
                _record(first_asg, None, None, status=AttendanceStatus.on_leave),
                first_asg,
                first_shift,
            ),
            (
                _record(second_asg, None, None, status=AttendanceStatus.on_leave),
                second_asg,
                second_shift,
            ),
        ],
        scheduled=[(first_asg, first_shift), (second_asg, second_shift)],
    )
    rows = _rows(slip)
    _near(slip["leave_pay"], 350)
    _near(slip["regular_pay"], 0)
    _near(slip["holiday_pay"], 0)
    _near(slip["gross_pay"], 350)
    assert all(row["status"] == "on_leave" for row in rows)
    _near(rows[0]["shift_net"], 350)
    _near(rows[1]["shift_net"], 0)
    _near(rows[0]["reconciled_day_total"], 350)
    _assert_payslip_identity(slip)
    _assert_day_matches_net(slip)


def test_q_unpaid_leave_is_zero():
    shift, assignment = _pair(time(8, 0), time(12, 0), "Leave")
    slip = _run(
        pay_basis=PayBasis.daily,
        daily_rate=350.0,
        hourly_rate=None,
        leave_paid=False,
        holidays=[_holiday()],
        rows=[
            (
                _record(assignment, None, None, status=AttendanceStatus.on_leave),
                assignment,
                shift,
            )
        ],
        scheduled=[(assignment, shift)],
    )
    row = _rows(slip)[0]
    _near(slip["leave_pay"], 0)
    _near(slip["holiday_pay"], 0)
    _near(slip["gross_pay"], 0)
    _near(slip["net_pay"], 0)
    _near(row["shift_net"], 0)
    _near(row["reconciled_day_total"], 0)


def test_r_unworked_paid_holiday_is_credited_once():
    first_shift, first_asg = _pair(time(8, 0), time(12, 0), "One")
    second_shift, second_asg = _pair(time(13, 0), time(17, 0), "Two")
    slip = _run(
        pay_basis=PayBasis.daily,
        daily_rate=350.0,
        hourly_rate=None,
        holidays=[_holiday()],
        rows=[],
        scheduled=[(first_asg, first_shift), (second_asg, second_shift)],
    )
    rows = _rows(slip)
    _near(slip["holiday_pay"], 350)
    _near(slip["regular_pay"], 0)
    _near(slip["gross_pay"], 350)
    assert all(row["status"] == "holiday_paid" for row in rows)
    included = [row for row in rows if row["holiday_included_in_shift_net"]]
    assert len(included) == 1
    _near(sum(float(row["shift_net"]) for row in included), 350)
    _near(rows[0]["reconciled_day_total"], 350)
    _assert_day_matches_net(slip)


def test_finalized_snapshot_keeps_hourly_late_shift_net():
    shift, assignment = _pair(time(8, 0), time(12, 0), "Hourly")
    record = _record(assignment, _ph(8, 30), _ph(12, 0), status=AttendanceStatus.late)
    slip = _run(
        pay_basis=PayBasis.hourly,
        daily_rate=None,
        hourly_rate=100.0,
        rows=[(record, assignment, shift)],
        scheduled=[(assignment, shift)],
    )
    frozen = freeze_payslip_dict(slip)
    stored = frozen["attendance_records"][0]
    _near(frozen["gross_pay"], 400)
    _near(frozen["net_pay"], 380)
    _near(stored["shift_net"], 380)
    _near(stored["reconciled_day_total"], 380)
    slip["net_pay"] = 0
    slip["attendance_records"][0]["shift_net"] = 0
    _near(frozen["net_pay"], 380)
    _near(stored["shift_net"], 380)

    employee = SimpleNamespace(id=uuid4(), business_id=uuid4())
    frozen["employee_id"] = str(employee.id)
    run = SimpleNamespace(id=uuid4(), snapshot_version=PAYSLIP_SNAPSHOT_VERSION)
    with (
        patch("app.services.payroll_snapshot.find_snapshot_run", return_value=run),
        patch(
            "app.services.payroll_snapshot.payslips_for_run",
            return_value=[
                SimpleNamespace(employee_id=employee.id, breakdown_json=frozen)
            ],
        ),
        patch("app.services.payroll_snapshot.snapshot_payslip_dict", return_value=frozen),
        patch("app.api.employee_mobile._calculate_employee_payslip") as recalc,
    ):
        overlaid = _overlay_shift_history_with_finalized_snapshots(
            SimpleNamespace(),
            employee,
            [
                {
                    "assignment_id": stored["shift_assignment_id"],
                    "date": WORK.isoformat(),
                    "status": "late",
                    "shift_net": 999.0,
                    "late_deduction": 999.0,
                }
            ],
        )
    assert not recalc.called
    _near(overlaid[0]["shift_net"], 380)
    _near(overlaid[0]["reconciled_day_total"], 380)
