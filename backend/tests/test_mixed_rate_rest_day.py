"""Rest-day premium follows the completion stamp, not the employee profile."""

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


def _money(value) -> float:
    if value is None:
        return 0.0
    return float(value)


def _near(actual, expected) -> None:
    assert abs(_money(actual) - expected) < 0.02


def _stamp(record, basis: PayBasis, *, daily=None, hourly=None):
    record.pay_basis_at_completion = basis
    record.daily_rate_at_completion = daily
    record.hourly_rate_at_completion = hourly
    record.monthly_salary_at_completion = None
    return record


def _rest_shift(start: time, end: time, name: str):
    shift, assignment = _shift_pair(start, end, name=name, work_date=WORK)
    assignment.is_rest_day_work = True
    return shift, assignment


def _full(assignment, shift):
    return _record(
        assignment,
        _ph(shift.start_time.hour, shift.start_time.minute, day=WORK.day),
        _ph(shift.end_time.hour, shift.end_time.minute, day=WORK.day),
    )


def _row_rest(slip) -> float:
    return sum(
        _money(row.get("rest_day_premium_pay"))
        for row in slip["attendance_records"]
        if row["date"] == WORK.isoformat()
    )


def _day_rest(slip) -> float:
    rows = [row for row in slip["attendance_records"] if row["date"] == WORK.isoformat()]
    return _money(rows[0].get("day_rest_day_pay")) if rows else 0.0


def test_a_hourly_profile_hourly_stamp_rest_is_row_once():
    shift, assignment = _rest_shift(time(8, 0), time(10, 0), "Hourly")
    slip = _run(
        pay_basis=PayBasis.hourly,
        daily_rate=None,
        hourly_rate=100.0,
        rest_premium=30.0,
        rows=[(_full(assignment, shift), assignment, shift)],
        scheduled=[(assignment, shift)],
    )
    row = slip["attendance_records"][0]
    _near(slip["regular_pay"], 200)
    _near(slip["rest_day_pay"], 60)
    _near(slip["gross_pay"], 260)
    _near(row["rest_day_premium_pay"], 60)
    _near(row["shift_net"], 260)
    _near(_day_rest(slip), 0)
    _near(row["reconciled_day_total"], 260)


def test_b_hourly_profile_daily_stamp_rest_is_bucket_once():
    shift, assignment = _rest_shift(time(8, 0), time(16, 0), "Daily")
    record = _stamp(_full(assignment, shift), PayBasis.daily, daily=350.0)
    slip = _run(
        pay_basis=PayBasis.hourly,
        daily_rate=None,
        hourly_rate=100.0,
        rest_premium=30.0,
        rows=[(record, assignment, shift)],
        scheduled=[(assignment, shift)],
    )
    row = slip["attendance_records"][0]
    _near(slip["regular_pay"], 350)
    _near(slip["rest_day_pay"], 105)
    _near(slip["gross_pay"], 455)
    assert row.get("rest_day_premium_pay") in (None, 0, 0.0)
    _near(row["shift_net"], 350)
    _near(_day_rest(slip), 105)
    _near(row["reconciled_day_total"], 455)
    _near(_row_rest(slip) + _day_rest(slip), 105)


def test_c_daily_profile_daily_stamp_rest_is_bucket_once():
    shift, assignment = _rest_shift(time(8, 0), time(16, 0), "Daily")
    slip = _run(
        pay_basis=PayBasis.daily,
        daily_rate=350.0,
        hourly_rate=None,
        rest_premium=30.0,
        rows=[(_full(assignment, shift), assignment, shift)],
        scheduled=[(assignment, shift)],
    )
    row = slip["attendance_records"][0]
    _near(slip["regular_pay"], 350)
    _near(slip["rest_day_pay"], 105)
    _near(slip["gross_pay"], 455)
    assert row.get("rest_day_premium_pay") in (None, 0, 0.0)
    _near(row["shift_net"], 350)
    _near(row["reconciled_day_total"], 455)


def test_d_daily_profile_hourly_stamp_rest_is_row_once():
    shift, assignment = _rest_shift(time(8, 0), time(10, 0), "Hourly")
    record = _stamp(_full(assignment, shift), PayBasis.hourly, hourly=100.0)
    slip = _run(
        pay_basis=PayBasis.daily,
        daily_rate=350.0,
        hourly_rate=None,
        rest_premium=30.0,
        rows=[(record, assignment, shift)],
        scheduled=[(assignment, shift)],
    )
    row = slip["attendance_records"][0]
    _near(slip["regular_pay"], 200)
    _near(slip["rest_day_pay"], 60)
    _near(slip["gross_pay"], 260)
    _near(row["rest_day_premium_pay"], 60)
    _near(row["shift_net"], 260)
    _near(_day_rest(slip), 0)
    _near(row["reconciled_day_total"], 260)


def test_e_hourly_profile_mixed_stamps_rest_is_150():
    daily_shift, daily_asg = _rest_shift(time(17, 0), time(19, 0), "Daily")
    hourly_shift, hourly_asg = _rest_shift(time(19, 30), time(21, 0), "Hourly")
    daily_punch = _stamp(_full(daily_asg, daily_shift), PayBasis.daily, daily=350.0)
    hourly_punch = _stamp(
        _full(hourly_asg, hourly_shift), PayBasis.hourly, hourly=100.0
    )
    slip = _run(
        pay_basis=PayBasis.hourly,
        daily_rate=None,
        hourly_rate=100.0,
        rest_premium=30.0,
        rows=[
            (daily_punch, daily_asg, daily_shift),
            (hourly_punch, hourly_asg, hourly_shift),
        ],
        scheduled=[(daily_asg, daily_shift), (hourly_asg, hourly_shift)],
    )
    _near(slip["regular_pay"], 500)
    _near(slip["rest_day_pay"], 150)
    _near(slip["gross_pay"], 650)
    _near(_row_rest(slip), 45)
    _near(_day_rest(slip), 105)
    _near(slip["attendance_records"][0]["reconciled_day_total"], 650)


def test_f_daily_profile_mixed_stamps_rest_is_150():
    daily_shift, daily_asg = _rest_shift(time(17, 0), time(19, 0), "Daily")
    hourly_shift, hourly_asg = _rest_shift(time(19, 30), time(21, 0), "Hourly")
    daily_punch = _stamp(_full(daily_asg, daily_shift), PayBasis.daily, daily=350.0)
    hourly_punch = _stamp(
        _full(hourly_asg, hourly_shift), PayBasis.hourly, hourly=100.0
    )
    slip = _run(
        pay_basis=PayBasis.daily,
        daily_rate=350.0,
        hourly_rate=100.0,
        rest_premium=30.0,
        rows=[
            (daily_punch, daily_asg, daily_shift),
            (hourly_punch, hourly_asg, hourly_shift),
        ],
        scheduled=[(daily_asg, daily_shift), (hourly_asg, hourly_shift)],
    )
    _near(slip["regular_pay"], 500)
    _near(slip["rest_day_pay"], 150)
    _near(slip["gross_pay"], 650)
    _near(_row_rest(slip), 45)
    _near(_day_rest(slip), 105)
    _near(slip["attendance_records"][0]["reconciled_day_total"], 650)


def test_g_hourly_profile_two_daily_stamps_one_rest():
    first_shift, first_asg = _rest_shift(time(17, 0), time(19, 0), "One")
    second_shift, second_asg = _rest_shift(time(19, 30), time(21, 0), "Two")
    first = _stamp(_full(first_asg, first_shift), PayBasis.daily, daily=350.0)
    second = _stamp(_full(second_asg, second_shift), PayBasis.daily, daily=350.0)
    slip = _run(
        pay_basis=PayBasis.hourly,
        daily_rate=None,
        hourly_rate=100.0,
        rest_premium=30.0,
        rows=[
            (first, first_asg, first_shift),
            (second, second_asg, second_shift),
        ],
        scheduled=[(first_asg, first_shift), (second_asg, second_shift)],
    )
    _near(slip["regular_pay"], 350)
    _near(slip["rest_day_pay"], 105)
    _near(slip["gross_pay"], 455)
    _near(_row_rest(slip), 0)
    _near(_day_rest(slip), 105)
    _near(slip["attendance_records"][0]["reconciled_day_total"], 455)
    assert slip["attendance_records"][0]["reconciled_day_total"] != 700


def test_h_daily_profile_two_daily_stamps_one_rest():
    first_shift, first_asg = _rest_shift(time(17, 0), time(19, 0), "One")
    second_shift, second_asg = _rest_shift(time(19, 30), time(21, 0), "Two")
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
    _near(slip["regular_pay"], 350)
    _near(slip["rest_day_pay"], 105)
    _near(slip["gross_pay"], 455)
    _near(_row_rest(slip), 0)
    _near(slip["attendance_records"][0]["reconciled_day_total"], 455)


def test_rest_day_ot_stays_separate_and_ignores_rest_ot_percent():
    shift, assignment = _rest_shift(time(8, 0), time(16, 0), "Hourly")
    record = _record(assignment, _ph(8, 0), _ph(17, 0))
    slip = _run(
        pay_basis=PayBasis.hourly,
        daily_rate=None,
        hourly_rate=100.0,
        rest_premium=30.0,
        rest_day_ot=40.0,
        overtime_per_minute=1.0,
        ot_minimum=30,
        rows=[(record, assignment, shift)],
        scheduled=[(assignment, shift)],
    )
    row = slip["attendance_records"][0]
    _near(slip["rest_day_pay"], 240)
    _near(slip["overtime_pay"], 60)
    _near(row["shift_net"], 800 + 60 + 240)
    _near(row["reconciled_day_total"], _money(row["shift_net"]))
    assert abs(_money(row["reconciled_day_total"]) - (
        _money(row["shift_net"]) + _money(row["overtime_pay"]) + _money(row["rest_day_premium_pay"])
    )) > 1


def _holiday() -> Holiday:
    return Holiday(
        id=uuid4(),
        business_id=uuid4(),
        name="Rest Holiday",
        holiday_date=WORK,
        is_paid=True,
        pay_multiplier=2,
        holiday_type=HolidayType.company,
        is_active=True,
    )


def test_rest_and_holiday_hourly_stamp_each_once_on_the_row():
    shift, assignment = _rest_shift(time(8, 0), time(10, 0), "Hourly")
    slip = _run(
        pay_basis=PayBasis.hourly,
        daily_rate=None,
        hourly_rate=100.0,
        rest_premium=30.0,
        holidays=[_holiday()],
        rows=[(_full(assignment, shift), assignment, shift)],
        scheduled=[(assignment, shift)],
    )
    row = slip["attendance_records"][0]
    _near(slip["regular_pay"], 200)
    _near(slip["holiday_pay"], 200)
    _near(slip["rest_day_pay"], 60)
    _near(slip["gross_pay"], 460)
    _near(row["holiday_pay"], 200)
    _near(row["rest_day_premium_pay"], 60)
    _near(row["shift_net"], 260)
    _near(row["reconciled_shift_total"], 460)
    _near(row["reconciled_day_total"], 460)


def test_rest_and_holiday_daily_stamp_each_once_from_the_bucket():
    shift, assignment = _rest_shift(time(8, 0), time(16, 0), "Daily")
    slip = _run(
        pay_basis=PayBasis.daily,
        daily_rate=350.0,
        hourly_rate=None,
        rest_premium=30.0,
        holidays=[_holiday()],
        rows=[(_full(assignment, shift), assignment, shift)],
        scheduled=[(assignment, shift)],
    )
    row = slip["attendance_records"][0]
    _near(slip["regular_pay"], 350)
    _near(slip["holiday_pay"], 350)
    _near(slip["rest_day_pay"], 105)
    _near(slip["gross_pay"], 805)
    assert row.get("rest_day_premium_pay") in (None, 0, 0.0)
    _near(row["holiday_pay"], 0)
    _near(row["day_holiday_pay"], 350)
    _near(row["day_rest_day_pay"], 105)
    _near(row["shift_net"], 350)
    _near(row["reconciled_day_total"], 805)


def test_paid_leave_on_rest_assignment_has_no_rest_premium():
    shift, assignment = _rest_shift(time(8, 0), time(10, 0), "Leave")
    record = _record(assignment, None, None, status=AttendanceStatus.on_leave)
    slip = _run(
        pay_basis=PayBasis.hourly,
        daily_rate=None,
        hourly_rate=100.0,
        rest_premium=30.0,
        leave_paid=True,
        rows=[(record, assignment, shift)],
        scheduled=[(assignment, shift)],
    )
    _near(slip["rest_day_pay"], 0)
    _near(slip["leave_pay"], 200)
    _near(slip["regular_pay"], 0)


def test_unpaid_leave_on_rest_assignment_has_no_rest_premium():
    shift, assignment = _rest_shift(time(8, 0), time(10, 0), "Leave")
    record = _record(assignment, None, None, status=AttendanceStatus.on_leave)
    slip = _run(
        pay_basis=PayBasis.hourly,
        daily_rate=None,
        hourly_rate=100.0,
        rest_premium=30.0,
        leave_paid=False,
        rows=[(record, assignment, shift)],
        scheduled=[(assignment, shift)],
    )
    _near(slip["rest_day_pay"], 0)
    _near(slip["leave_pay"], 0)
    _near(slip["gross_pay"], 0)


def test_finalized_snapshot_keeps_rest_result():
    shift, assignment = _rest_shift(time(8, 0), time(16, 0), "Daily")
    record = _stamp(_full(assignment, shift), PayBasis.daily, daily=350.0)
    slip = _run(
        pay_basis=PayBasis.hourly,
        daily_rate=None,
        hourly_rate=100.0,
        rest_premium=30.0,
        rows=[(record, assignment, shift)],
        scheduled=[(assignment, shift)],
    )
    frozen = freeze_payslip_dict(slip)
    _near(frozen["rest_day_pay"], 105)
    _near(frozen["gross_pay"], 455)
    stored = frozen["attendance_records"][0]
    _near(stored["shift_net"], 350)
    _near(stored["reconciled_day_total"], 455)

    employee = SimpleNamespace(id=uuid4(), business_id=uuid4())
    frozen["employee_id"] = str(employee.id)
    run = SimpleNamespace(id=uuid4(), snapshot_version=PAYSLIP_SNAPSHOT_VERSION)
    with (
        patch("app.services.payroll_snapshot.find_snapshot_run", return_value=run),
        patch(
            "app.services.payroll_snapshot.payslips_for_run",
            return_value=[SimpleNamespace(employee_id=employee.id, breakdown_json=frozen)],
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
                    "status": "complete",
                    "shift_net": 999.0,
                    "rest_day_premium_pay": 999.0,
                }
            ],
        )
    assert not recalc.called
    _near(overlaid[0]["shift_net"], 350)
    _near(overlaid[0]["reconciled_day_total"], 455)
    assert overlaid[0].get("rest_day_premium_pay") in (None, 0, 0.0)
