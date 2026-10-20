"""Employee Payroll rows expose stamp rate and engine shift_net.

These tests do not change payroll totals. They check the employee payroll
projection the Basic Daily Wage card displays.
"""

from __future__ import annotations

from datetime import date, time
from types import SimpleNamespace
from unittest.mock import MagicMock, patch
from uuid import uuid4

from app.api.employee_mobile import _payroll_response
from app.models.attendance import AttendanceRecord
from app.models.enums import AttendanceStatus, PayBasis
from app.services.payroll_snapshot import PayslipLoad
from tests.test_shift_history_holiday_reconciliation import (
    WORK,
    _holiday,
    _payslip,
    _punch,
    _shift,
    _utc,
)


def _rows_for(slip, *, hourly_rate=100.0, daily_rate=350.0, pay_basis=PayBasis.hourly):
    employee = SimpleNamespace(
        id=uuid4(),
        business_id=uuid4(),
        full_name="Emp",
        hourly_rate=hourly_rate,
        daily_rate=daily_rate,
        pay_basis=pay_basis,
    )
    business = SimpleNamespace(
        name="Cafe",
        id=employee.business_id,
        theme_settings={},
        logo_url=None,
        owner_profile_image_url=None,
        display_image_url=None,
    )
    db = MagicMock()
    db.get.return_value = None
    loaded = PayslipLoad(
        slip=slip,
        period_start=date(2026, 9, 1),
        period_end=date(2026, 9, 30),
        from_snapshot=True,
        payroll_run=None,
    )
    with patch("app.api.employee_mobile.load_period_payslip", return_value=loaded):
        return _payroll_response(db, employee, business, history_limit=0)


def _work_rows(payload):
    return [row for row in payload["rows"] if row["date"] == WORK.isoformat()]


def test_hourly_rows_use_stamp_rate_and_shift_net():
    evening, evening_asg = _shift(time(17, 0), time(19, 0), "Evening")
    morning, morning_asg = _shift(time(19, 30), time(21, 0), "Morning")
    slip = _payslip(
        pay_basis=PayBasis.hourly,
        daily_rate=None,
        hourly_rate=100.0,
        holidays=[_holiday()],
        rows=[
            (_punch(evening_asg, _utc(17, 0), _utc(19, 0)), evening_asg, evening),
            (_punch(morning_asg, _utc(19, 30), _utc(21, 0)), morning_asg, morning),
        ],
        scheduled=[(evening_asg, evening), (morning_asg, morning)],
    )
    payload = _rows_for(slip, hourly_rate=999.0)
    rows = _work_rows(payload)
    assert payload["summary"]["regular_pay"] == 350.0
    assert payload["summary"]["holiday_pay"] == 350.0
    assert payload["summary"]["gross_pay"] == 700.0
    assert [row["pay_basis_used"] for row in rows] == ["hourly", "hourly"]
    assert [row["rate_used"] for row in rows] == [100.0, 100.0]
    assert [row["shift_net"] for row in rows] == [200.0, 150.0]
    assert sum(row["shift_net"] for row in rows) != payload["summary"]["gross_pay"]


def test_daily_rows_keep_one_entitlement_in_regular_pay():
    evening, evening_asg = _shift(time(17, 0), time(19, 0), "Evening")
    morning, morning_asg = _shift(time(19, 30), time(21, 0), "Morning")
    slip = _payslip(
        pay_basis=PayBasis.daily,
        daily_rate=350.0,
        hourly_rate=None,
        holidays=[_holiday()],
        rows=[
            (_punch(evening_asg, _utc(17, 0), _utc(19, 0)), evening_asg, evening),
            (_punch(morning_asg, _utc(19, 30), _utc(21, 0)), morning_asg, morning),
        ],
        scheduled=[(evening_asg, evening), (morning_asg, morning)],
    )
    payload = _rows_for(slip, pay_basis=PayBasis.daily, daily_rate=999.0)
    rows = _work_rows(payload)
    assert payload["summary"]["regular_pay"] == 350.0
    assert payload["summary"]["holiday_pay"] == 350.0
    assert [row["pay_basis_used"] for row in rows] == ["daily", "daily"]
    assert [row["rate_used"] for row in rows] == [350.0, 350.0]
    assert [row["shift_net"] for row in rows] == [350.0, 350.0]
    assert rows[0]["earned"] != rows[0]["shift_net"]


def test_mixed_rate_rows_follow_each_stamp():
    evening, evening_asg = _shift(time(17, 0), time(19, 0), "Evening")
    morning, morning_asg = _shift(time(19, 30), time(21, 0), "Morning")
    daily_punch = _punch(evening_asg, _utc(17, 0), _utc(19, 0))
    daily_punch.pay_basis_at_completion = PayBasis.daily
    daily_punch.daily_rate_at_completion = 350.0
    daily_punch.hourly_rate_at_completion = None
    hourly_punch = _punch(morning_asg, _utc(19, 30), _utc(21, 0))
    hourly_punch.pay_basis_at_completion = PayBasis.hourly
    hourly_punch.hourly_rate_at_completion = 100.0
    hourly_punch.daily_rate_at_completion = None
    slip = _payslip(
        pay_basis=PayBasis.hourly,
        daily_rate=None,
        hourly_rate=100.0,
        holidays=[_holiday()],
        rows=[
            (daily_punch, evening_asg, evening),
            (hourly_punch, morning_asg, morning),
        ],
        scheduled=[(evening_asg, evening), (morning_asg, morning)],
    )
    payload = _rows_for(slip, hourly_rate=999.0)
    rows = _work_rows(payload)
    assert payload["summary"]["regular_pay"] == 500.0
    assert payload["summary"]["holiday_pay"] == 500.0
    assert payload["summary"]["gross_pay"] == 1000.0
    assert rows[0]["pay_basis_used"] == "daily"
    assert rows[0]["rate_used"] == 350.0
    assert rows[0]["shift_net"] == 350.0
    assert rows[0]["earned"] != 350.0
    assert rows[1]["pay_basis_used"] == "hourly"
    assert rows[1]["rate_used"] == 100.0
    assert rows[1]["shift_net"] == 150.0


def test_paid_leave_shift_net_matches_leave_pay():
    evening, evening_asg = _shift(time(17, 0), time(19, 0), "Evening")
    record = AttendanceRecord(
        id=uuid4(),
        business_id=uuid4(),
        employee_id=evening_asg.employee_id,
        shift_assignment_id=evening_asg.id,
        time_in=None,
        time_out=None,
        status=AttendanceStatus.on_leave,
    )
    slip = _payslip(
        pay_basis=PayBasis.hourly,
        daily_rate=None,
        hourly_rate=100.0,
        holidays=[_holiday()],
        rows=[(record, evening_asg, evening)],
        scheduled=[(evening_asg, evening)],
        leave_paid=True,
    )
    payload = _rows_for(slip)
    rows = _work_rows(payload)
    assert payload["summary"]["leave_pay"] == 200.0
    assert payload["summary"]["holiday_pay"] == 0.0
    assert rows[0]["status"] == "on_leave"
    assert rows[0]["shift_net"] == 200.0
    assert payload["summary"]["pay_basis"] == "hourly"
    assert payload["summary"]["hourly_rate"] == 100.0


def test_unpaid_leave_shift_net_stays_zero():
    evening, evening_asg = _shift(time(17, 0), time(19, 0), "Evening")
    record = AttendanceRecord(
        id=uuid4(),
        business_id=uuid4(),
        employee_id=evening_asg.employee_id,
        shift_assignment_id=evening_asg.id,
        time_in=None,
        time_out=None,
        status=AttendanceStatus.on_leave,
    )
    slip = _payslip(
        pay_basis=PayBasis.hourly,
        daily_rate=None,
        hourly_rate=100.0,
        holidays=[_holiday()],
        rows=[(record, evening_asg, evening)],
        scheduled=[(evening_asg, evening)],
        leave_paid=False,
    )
    payload = _rows_for(slip)
    rows = _work_rows(payload)
    assert payload["summary"]["leave_pay"] == 0.0
    assert payload["summary"]["holiday_pay"] == 0.0
    assert rows[0]["shift_net"] == 0.0


def test_finalized_rows_keep_snapshot_rate_after_profile_change():
    evening, evening_asg = _shift(time(17, 0), time(19, 0), "Evening")
    slip = _payslip(
        pay_basis=PayBasis.hourly,
        daily_rate=None,
        hourly_rate=100.0,
        holidays=[],
        rows=[(_punch(evening_asg, _utc(17, 0), _utc(19, 0)), evening_asg, evening)],
        scheduled=[(evening_asg, evening)],
    )
    payload = _rows_for(slip, hourly_rate=250.0, pay_basis=PayBasis.daily, daily_rate=900.0)
    row = _work_rows(payload)[0]
    assert row["pay_basis_used"] == "hourly"
    assert row["rate_used"] == 100.0
    assert row["shift_net"] == 200.0
    assert payload["summary"]["regular_pay"] == 200.0


def test_historical_row_hides_stamp_and_shift_net():
    slip = {
        "period_start": "2026-09-01",
        "period_end": "2026-09-30",
        "daily_rate": 350.0,
        "pay_basis": "daily",
        "hourly_rate": None,
        "attendance_records": [
            {
                "date": WORK.isoformat(),
                "status": "complete",
                "expected_salary_pay": 350.0,
                "earned": 200.0,
                "holiday_name": None,
                "historical_rate_required": True,
                "pay_basis_used": "daily",
                "rate_used": 350.0,
                "shift_net": 350.0,
                "payroll_status": "historical_rate_required",
            }
        ],
    }
    payload = _rows_for(slip)
    row = payload["rows"][0]
    assert row["pay_basis_used"] is None
    assert row["rate_used"] is None
    assert row["shift_net"] is None
    assert row["earned"] is None
