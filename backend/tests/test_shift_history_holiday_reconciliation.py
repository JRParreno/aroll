"""Shift History explains holiday pay already booked by payroll.

History fields must reconcile to the payslip totals without counting a
premium twice. Mixed-rate worked-holiday cases lock the completion-stamp
premium: one premium per regular component.
"""

from __future__ import annotations

from datetime import date, datetime, time, timezone
from types import SimpleNamespace
from unittest.mock import MagicMock, patch
from uuid import uuid4

from app.api.employee_mobile import (
    _append_today_unworked_holiday_shifts,
    _overlay_shift_history_with_finalized_snapshots,
)
from app.api.owner_reports import shift_history_report
from app.models.attendance import AttendanceRecord
from app.models.business import Business
from app.models.enums import (
    AttendanceStatus,
    HolidayType,
    PayBasis,
)
from app.models.holiday import Holiday
from app.models.scheduling import Shift, ShiftAssignment
from app.services.payroll_snapshot import (
    PAYSLIP_SNAPSHOT_VERSION,
    PayslipLoad,
    freeze_payslip_dict,
)
from tests.test_payroll_engine import _run


WORK = date(2026, 9, 28)


def _utc(hour: int, minute: int = 0) -> datetime:
    """Manila wall time on WORK as UTC."""
    utc_hour = hour - 8
    day = WORK.day
    if utc_hour < 0:
        utc_hour += 24
        day -= 1
    return datetime(WORK.year, WORK.month, day, utc_hour, minute, tzinfo=timezone.utc)


def _shift(start: time, end: time, name: str) -> tuple[Shift, ShiftAssignment]:
    business_id = uuid4()
    employee_id = uuid4()
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
        employee_id=employee_id,
        work_date=WORK,
        is_rest_day_work=False,
    )
    return shift, assignment


def _punch(assignment, start: datetime, end: datetime, status=AttendanceStatus.complete):
    return AttendanceRecord(
        id=uuid4(),
        business_id=uuid4(),
        employee_id=assignment.employee_id,
        shift_assignment_id=assignment.id,
        time_in=start,
        time_out=end,
        status=status,
    )


def _holiday() -> Holiday:
    return Holiday(
        id=uuid4(),
        business_id=uuid4(),
        name="Birthday Ni Diyon",
        holiday_date=WORK,
        is_paid=True,
        pay_multiplier=2,
        holiday_type=HolidayType.company,
        is_active=True,
    )


def _payslip(**kwargs):
    kwargs.setdefault("period_start", date(2026, 9, 1))
    kwargs.setdefault("period_end", date(2026, 9, 30))
    kwargs.setdefault("today", WORK)
    kwargs.setdefault("now", datetime(2026, 9, 28, 22, 30))
    kwargs.setdefault("grace_minutes", 5)
    kwargs.setdefault("ot_minimum", 160)
    return _run(**kwargs)


def _rows(slip):
    return [row for row in slip["attendance_records"] if row["date"] == WORK.isoformat()]


def _sum(rows, key):
    return round(sum(float(row.get(key) or 0.0) for row in rows), 2)


def test_kim_hourly_double_shift_history_reconciles_to_700():
    evening, evening_asg = _shift(time(17, 0), time(19, 0), "Evening")
    morning, morning_asg = _shift(time(19, 30), time(21, 0), "Morning")
    slip = _payslip(
        pay_basis=PayBasis.hourly,
        daily_rate=None,
        hourly_rate=100.0,
        holidays=[_holiday()],
        rows=[
            (_punch(evening_asg, _utc(17, 3), _utc(19, 0)), evening_asg, evening),
            (_punch(morning_asg, _utc(19, 10), _utc(21, 12)), morning_asg, morning),
        ],
        scheduled=[(evening_asg, evening), (morning_asg, morning)],
    )
    rows = _rows(slip)
    assert slip["regular_pay"] == 350.0
    assert slip["holiday_pay"] == 350.0
    assert slip["gross_pay"] == 700.0
    assert _sum(rows, "shift_net") == 350.0
    assert _sum(rows, "holiday_pay") == 350.0
    assert all(row["holiday_included_in_shift_net"] is False for row in rows)
    assert rows[0]["day_holiday_pay"] == 0.0
    assert rows[0]["reconciled_day_total"] == 700.0
    assert _sum(rows, "reconciled_shift_total") == 700.0


def test_ali_daily_double_shift_counts_entitlement_and_holiday_once():
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
    rows = _rows(slip)
    assert slip["regular_pay"] == 350.0
    assert slip["holiday_pay"] == 350.0
    assert slip["gross_pay"] == 700.0
    assert all(row["holiday_pay"] == 0.0 for row in rows)
    assert all(row["day_entitlement"] == 350.0 for row in rows)
    assert all(row["day_holiday_pay"] == 350.0 for row in rows)
    assert _sum(rows, "shift_net") == 700.0
    assert rows[0]["reconciled_day_total"] == 700.0
    assert rows[0]["reconciled_day_total"] != _sum(rows, "shift_net") + 350.0


def test_kane_mixed_holiday_is_500_and_gross_1000():
    evening, evening_asg = _shift(time(17, 0), time(19, 0), "Evening")
    morning, morning_asg = _shift(time(19, 30), time(21, 0), "Morning")
    daily_punch = _punch(evening_asg, _utc(16, 43), _utc(19, 2))
    daily_punch.pay_basis_at_completion = PayBasis.daily
    daily_punch.daily_rate_at_completion = 350.0
    daily_punch.hourly_rate_at_completion = None
    hourly_punch = _punch(morning_asg, _utc(19, 10), _utc(21, 13))
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
    rows = _rows(slip)
    assert slip["regular_pay"] == 500.0
    assert slip["holiday_pay"] == 500.0
    assert slip["gross_pay"] == 1000.0
    assert rows[0]["holiday_pay"] == 0.0
    assert rows[1]["holiday_pay"] == 150.0
    assert rows[0]["day_holiday_pay"] == 350.0
    assert rows[0]["reconciled_day_total"] == 1000.0
    booked = _sum(rows, "holiday_pay") + float(rows[0]["day_holiday_pay"])
    assert booked == 500.0


def test_hourly_profile_two_daily_stamps_one_holiday_premium():
    evening, evening_asg = _shift(time(17, 0), time(19, 0), "Evening")
    morning, morning_asg = _shift(time(19, 30), time(21, 0), "Morning")
    first = _punch(evening_asg, _utc(17, 0), _utc(19, 0))
    first.pay_basis_at_completion = PayBasis.daily
    first.daily_rate_at_completion = 350.0
    first.hourly_rate_at_completion = None
    second = _punch(morning_asg, _utc(19, 30), _utc(21, 0))
    second.pay_basis_at_completion = PayBasis.daily
    second.daily_rate_at_completion = 350.0
    second.hourly_rate_at_completion = None
    slip = _payslip(
        pay_basis=PayBasis.hourly,
        daily_rate=None,
        hourly_rate=100.0,
        holidays=[_holiday()],
        rows=[
            (first, evening_asg, evening),
            (second, morning_asg, morning),
        ],
        scheduled=[(evening_asg, evening), (morning_asg, morning)],
    )
    rows = _rows(slip)
    assert slip["regular_pay"] == 350.0
    assert slip["holiday_pay"] == 350.0
    assert slip["gross_pay"] == 700.0
    assert _sum(rows, "holiday_pay") == 0.0
    assert rows[0]["day_holiday_pay"] == 350.0


def test_daily_profile_plus_hourly_stamp_each_gets_one_premium():
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
        pay_basis=PayBasis.daily,
        daily_rate=350.0,
        hourly_rate=100.0,
        holidays=[_holiday()],
        rows=[
            (daily_punch, evening_asg, evening),
            (hourly_punch, morning_asg, morning),
        ],
        scheduled=[(evening_asg, evening), (morning_asg, morning)],
    )
    rows = _rows(slip)
    assert slip["regular_pay"] == 500.0
    assert slip["holiday_pay"] == 500.0
    assert slip["gross_pay"] == 1000.0
    assert rows[0]["holiday_pay"] == 0.0
    assert rows[1]["holiday_pay"] == 150.0
    assert rows[0]["day_holiday_pay"] == 350.0


def test_bianca_unworked_holiday_history_is_262_50_not_525():
    evening, evening_asg = _shift(time(17, 0), time(19, 0), "Evening")
    morning, morning_asg = _shift(time(19, 30), time(21, 0), "Morning")
    slip = _payslip(
        pay_basis=PayBasis.hourly,
        daily_rate=None,
        hourly_rate=75.0,
        holidays=[_holiday()],
        rows=[],
        scheduled=[(evening_asg, evening), (morning_asg, morning)],
    )
    rows = _rows(slip)
    assert slip["regular_pay"] == 0.0
    assert slip["holiday_pay"] == 262.5
    assert slip["gross_pay"] == 262.5
    assert len(rows) == 2
    assert {row["shift_assignment_id"] for row in rows} == {
        str(evening_asg.id),
        str(morning_asg.id),
    }
    assert all(row["holiday_included_in_shift_net"] is True for row in rows)
    assert _sum(rows, "shift_net") == 262.5
    assert _sum(rows, "holiday_pay") == 262.5
    assert rows[0]["reconciled_day_total"] == 262.5
    assert rows[0]["reconciled_day_total"] != 525.0
    assert all(row["status"] == "holiday_paid" for row in rows)
    assert all(row["pay_basis_used"] == "hourly" for row in rows)
    assert all(row["rate_used"] == 75.0 for row in rows)
    nets = sorted(float(row["shift_net"]) for row in rows)
    assert nets == [112.5, 150.0]
    assert all(row["time_in"] is None and row["time_out"] is None for row in rows)


def test_daily_unworked_holiday_exposes_daily_basis_and_rate():
    evening, evening_asg = _shift(time(17, 0), time(19, 0), "Evening")
    slip = _payslip(
        pay_basis=PayBasis.daily,
        daily_rate=350.0,
        hourly_rate=None,
        holidays=[_holiday()],
        rows=[],
        scheduled=[(evening_asg, evening)],
    )
    rows = _rows(slip)
    assert slip["holiday_pay"] == rows[0]["shift_net"]
    assert rows[0]["status"] == "holiday_paid"
    assert rows[0]["pay_basis_used"] == "daily"
    assert rows[0]["rate_used"] == 350.0
    assert rows[0]["holiday_included_in_shift_net"] is True
    assert rows[0]["reconciled_shift_total"] == rows[0]["shift_net"]
    assert rows[0]["reconciled_day_total"] == rows[0]["shift_net"]


def test_aina_paid_leave_stays_200_with_zero_holiday():
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
    rows = _rows(slip)
    assert slip["leave_pay"] == 200.0
    assert slip["holiday_pay"] == 0.0
    assert slip["gross_pay"] == 200.0
    assert rows[0]["shift_net"] == 200.0
    assert rows[0]["holiday_pay"] == 0.0
    assert rows[0]["reconciled_day_total"] == 200.0


def test_drew_unpaid_leave_stays_zero():
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
    rows = _rows(slip)
    assert slip["leave_pay"] == 0.0
    assert slip["holiday_pay"] == 0.0
    assert slip["gross_pay"] == 0.0
    assert rows[0]["shift_net"] == 0.0
    assert rows[0]["holiday_pay"] == 0.0
    assert rows[0]["reconciled_day_total"] == 0.0


def test_ordinary_non_holiday_shift_net_is_unchanged():
    evening, evening_asg = _shift(time(17, 0), time(19, 0), "Evening")
    slip = _payslip(
        pay_basis=PayBasis.hourly,
        daily_rate=None,
        hourly_rate=100.0,
        holidays=[],
        rows=[(_punch(evening_asg, _utc(17, 0), _utc(19, 0)), evening_asg, evening)],
        scheduled=[(evening_asg, evening)],
    )
    row = _rows(slip)[0]
    assert slip["holiday_pay"] == 0.0
    assert slip["gross_pay"] == 200.0
    assert row["shift_net"] == 200.0
    assert row["holiday_pay"] == 0.0
    assert row["reconciled_shift_total"] == 200.0
    assert row["reconciled_day_total"] == 200.0


def test_overtime_and_rest_are_not_added_twice():
    evening, evening_asg = _shift(time(17, 0), time(19, 0), "Evening")
    evening_asg.is_rest_day_work = True
    slip = _payslip(
        pay_basis=PayBasis.hourly,
        daily_rate=None,
        hourly_rate=100.0,
        holidays=[],
        ot_minimum=30,
        rest_premium=30.0,
        rows=[(_punch(evening_asg, _utc(17, 0), _utc(20, 0)), evening_asg, evening)],
        scheduled=[(evening_asg, evening)],
    )
    row = _rows(slip)[0]
    earned = float(row["earned"])
    ot = float(row["overtime_pay"] or 0.0)
    rest = float(row["rest_day_premium_pay"] or 0.0)
    assert ot > 0
    assert rest > 0
    assert abs(float(row["shift_net"]) - (earned + ot + rest)) < 0.02
    assert abs(float(row["reconciled_shift_total"]) - float(row["shift_net"])) < 0.02
    assert abs(float(row["reconciled_day_total"]) - float(row["shift_net"])) < 0.02
    assert float(row["reconciled_day_total"]) != round(float(row["shift_net"]) + ot + rest, 2)


def test_owner_and_employee_history_share_holiday_breakdown():
    evening, evening_asg = _shift(time(17, 0), time(19, 0), "Evening")
    slip = _payslip(
        pay_basis=PayBasis.hourly,
        daily_rate=None,
        hourly_rate=100.0,
        holidays=[_holiday()],
        rows=[(_punch(evening_asg, _utc(17, 0), _utc(19, 0)), evening_asg, evening)],
        scheduled=[(evening_asg, evening)],
    )
    loaded = SimpleNamespace(
        period_start=date(2026, 9, 1),
        period_end=date(2026, 9, 30),
        from_snapshot=False,
        payroll_run=None,
        entries=[(None, slip)],
    )
    db = MagicMock()
    db.get.side_effect = lambda model, key=None: (
        SimpleNamespace(timezone="Asia/Manila") if model is Business else None
    )
    user = SimpleNamespace(business_id=uuid4(), id=uuid4())
    with patch("app.api.owner_reports.load_period_payroll", return_value=loaded):
        owner = shift_history_report(db=db, user=user, as_of=WORK)
    owner_row = owner["items"][0]
    employee = SimpleNamespace(id=uuid4(), business_id=uuid4())
    live = {
        "assignment_id": owner_row["attendance_record_id"] and str(evening_asg.id),
        "date": WORK.isoformat(),
        "status": "complete",
        "holiday_name": "Birthday Ni Diyon",
    }
    live["assignment_id"] = str(evening_asg.id)
    with (
        patch("app.services.payroll_snapshot.find_snapshot_run", return_value=None),
        patch(
            "app.services.payroll_snapshot.load_period_payslip",
            return_value=PayslipLoad(
                slip=slip,
                period_start=date(2026, 9, 1),
                period_end=date(2026, 9, 30),
                from_snapshot=False,
                payroll_run=None,
            ),
        ),
    ):
        employee_rows = _overlay_shift_history_with_finalized_snapshots(
            db, employee, [live]
        )
    assert owner_row["holiday_pay"] == employee_rows[0]["holiday_pay"]
    assert owner_row["reconciled_day_total"] == employee_rows[0]["reconciled_day_total"]
    assert owner_row["holiday_pay"] == 200.0
    assert owner_row["reconciled_day_total"] == 400.0


def test_today_unworked_holiday_assignment_is_included_for_employee():
    evening, evening_asg = _shift(time(17, 0), time(19, 0), "Evening")
    holiday = _holiday()
    db = MagicMock()
    query = MagicMock()
    query.join.return_value.outerjoin.return_value.filter.return_value.all.return_value = [
        (evening_asg, evening, None)
    ]
    db.query.return_value = query
    db.get.return_value = SimpleNamespace(
        holiday_rules_mode=None,
        on_time_grace_minutes=5,
    )
    deduped = []
    seen = set()
    with (
        patch(
            "app.services.missing_clock_out.is_past_clock_out_deadline",
            return_value=True,
        ),
        patch(
            "app.services.leave_requests.employee_on_payroll_active_leave",
            return_value=False,
        ),
        patch(
            "app.core.timezone.business_now",
            return_value=datetime(2026, 9, 28, 22, 0),
        ),
    ):
        _append_today_unworked_holiday_shifts(
            db,
            SimpleNamespace(id=evening_asg.employee_id, business_id=uuid4()),
            deduped,
            seen,
            today=WORK,
            holidays={WORK: holiday},
            business_timezone="Asia/Manila",
        )
    assert len(deduped) == 1
    assert deduped[0][0].id == evening_asg.id

    deduped.clear()
    seen.clear()
    ordinary = _holiday()
    ordinary.holiday_type = HolidayType.special_non_working
    with (
        patch(
            "app.services.missing_clock_out.is_past_clock_out_deadline",
            return_value=True,
        ),
        patch(
            "app.services.leave_requests.employee_on_payroll_active_leave",
            return_value=False,
        ),
        patch(
            "app.core.timezone.business_now",
            return_value=datetime(2026, 9, 28, 22, 0),
        ),
    ):
        _append_today_unworked_holiday_shifts(
            db,
            SimpleNamespace(id=evening_asg.employee_id, business_id=uuid4()),
            deduped,
            seen,
            today=WORK,
            holidays={WORK: ordinary},
            business_timezone="Asia/Manila",
        )
    assert deduped == []


def test_old_snapshot_without_holiday_field_is_not_rewritten():
    old = {
        "regular_pay": 200.0,
        "holiday_pay": 0.0,
        "gross_pay": 200.0,
        "net_pay": 200.0,
        "attendance_records": [
            {"date": "2026-08-04", "earned": 200.0, "shift_net": 200.0}
        ],
    }
    frozen = freeze_payslip_dict(old)
    assert "holiday_pay" not in frozen["attendance_records"][0]
    assert frozen["attendance_records"][0]["shift_net"] == 200.0
    assert frozen["snapshot_version"] == PAYSLIP_SNAPSHOT_VERSION
    assert old["attendance_records"][0] == {
        "date": "2026-08-04",
        "earned": 200.0,
        "shift_net": 200.0,
    }

    frozen["employee_id"] = str(uuid4())
    frozen["employee_name"] = "Old Snapshot"
    loaded = SimpleNamespace(
        period_start=date(2026, 8, 1),
        period_end=date(2026, 8, 15),
        from_snapshot=True,
        payroll_run=None,
        entries=[(None, frozen)],
    )
    db = MagicMock()
    db.get.side_effect = lambda model, key=None: (
        SimpleNamespace(timezone="Asia/Manila") if model is Business else None
    )
    user = SimpleNamespace(business_id=uuid4(), id=uuid4())
    with patch("app.api.owner_reports.load_period_payroll", return_value=loaded):
        result = shift_history_report(db=db, user=user, as_of=date(2026, 8, 4))
    item = result["items"][0]
    assert item["shift_net"] == 200.0
    assert "holiday_pay" not in item
    assert "reconciled_day_total" not in item

    employee = SimpleNamespace(id=uuid4(), business_id=uuid4())
    assignment_id = uuid4()
    frozen["attendance_records"][0]["shift_assignment_id"] = str(assignment_id)
    run = SimpleNamespace(id=uuid4(), snapshot_version=PAYSLIP_SNAPSHOT_VERSION)
    with (
        patch("app.services.payroll_snapshot.find_snapshot_run", return_value=run),
        patch(
            "app.services.payroll_snapshot.payslips_for_run",
            return_value=[
                SimpleNamespace(
                    employee_id=employee.id,
                    breakdown_json=frozen,
                )
            ],
        ),
    ):
        overlaid = _overlay_shift_history_with_finalized_snapshots(
            db,
            employee,
            [
                {
                    "assignment_id": str(assignment_id),
                    "date": "2026-08-04",
                    "status": "complete",
                    "shift_net": 200.0,
                }
            ],
        )
    assert overlaid[0]["shift_net"] == 200.0
    assert "holiday_pay" not in overlaid[0]


def test_scenario_1_ordinary_day_hourly_double_shift_on_time():
    """Kim: 2026-09-28, ₱100/hr, two evening shifts on time, no holiday or rest."""
    evening, evening_asg = _shift(time(17, 0), time(19, 0), "Evening")
    morning, morning_asg = _shift(time(19, 30), time(21, 0), "Morning")
    slip = _payslip(
        pay_basis=PayBasis.hourly,
        daily_rate=None,
        hourly_rate=100.0,
        holidays=[],
        rows=[
            (_punch(evening_asg, _utc(17, 0), _utc(19, 0)), evening_asg, evening),
            (_punch(morning_asg, _utc(19, 30), _utc(21, 0)), morning_asg, morning),
        ],
        scheduled=[(evening_asg, evening), (morning_asg, morning)],
    )
    rows = _rows(slip)
    assert len(rows) == 2
    assert {row["shift_assignment_id"] for row in rows} == {
        str(evening_asg.id),
        str(morning_asg.id),
    }
    assert slip["regular_pay"] == 350.0
    assert slip["overtime_pay"] == 0.0
    assert slip["holiday_pay"] == 0.0
    assert slip["rest_day_pay"] == 0.0
    assert slip["gross_pay"] == 350.0


def test_scenario_2_rest_day_daily_double_shift_on_time():
    """Ali: ₱350/day, both evening shifts on rest day, 30% rest premium."""
    evening, evening_asg = _shift(time(17, 0), time(19, 0), "Evening")
    morning, morning_asg = _shift(time(19, 30), time(21, 0), "Morning")
    evening_asg.is_rest_day_work = True
    morning_asg.is_rest_day_work = True
    slip = _payslip(
        pay_basis=PayBasis.daily,
        daily_rate=350.0,
        hourly_rate=None,
        rest_premium=30.0,
        holidays=[],
        rows=[
            (_punch(evening_asg, _utc(17, 0), _utc(19, 0)), evening_asg, evening),
            (_punch(morning_asg, _utc(19, 30), _utc(21, 0)), morning_asg, morning),
        ],
        scheduled=[(evening_asg, evening), (morning_asg, morning)],
    )
    assert slip["regular_pay"] == 350.0
    assert slip["rest_day_pay"] == 105.0
    assert slip["overtime_pay"] == 0.0
    assert slip["gross_pay"] == 455.0


def test_scenario_6_company_holiday_hourly_double_shift_on_time():
    """Kim: company holiday mult 2, paid scheduled day, on-time hourly double shift."""
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
    assert slip["regular_pay"] == 350.0
    assert slip["holiday_pay"] == 350.0
    assert slip["overtime_pay"] == 0.0
    assert slip["gross_pay"] == 700.0


def test_scenario_3_mixed_rates_undertime_only_reduces_hourly_shift():
    """Daily shift 1 keeps ₱350; shift 2 hourly undertime does not touch shift 1."""
    evening, evening_asg = _shift(time(17, 0), time(19, 0), "Shift 1")
    late, late_asg = _shift(time(19, 30), time(21, 0), "Shift 2")
    late_asg.is_rest_day_work = True
    daily_punch = _punch(evening_asg, _utc(17, 0), _utc(19, 0))
    daily_punch.pay_basis_at_completion = PayBasis.daily
    daily_punch.daily_rate_at_completion = 350.0
    daily_punch.hourly_rate_at_completion = None
    hourly_punch = _punch(late_asg, _utc(19, 30), _utc(20, 0))
    hourly_punch.pay_basis_at_completion = PayBasis.hourly
    hourly_punch.hourly_rate_at_completion = 100.0
    hourly_punch.daily_rate_at_completion = None
    slip = _payslip(
        pay_basis=PayBasis.hourly,
        daily_rate=None,
        hourly_rate=100.0,
        rest_premium=30.0,
        rows=[
            (daily_punch, evening_asg, evening),
            (hourly_punch, late_asg, late),
        ],
        scheduled=[(evening_asg, evening), (late_asg, late)],
    )
    rows = _rows(slip)
    assert len(rows) == 2
    daily_row = next(r for r in rows if r.get("pay_basis_used") == "daily")
    hourly_row = next(r for r in rows if r.get("pay_basis_used") == "hourly")
    assert slip["regular_pay"] == 500.0
    assert daily_row["shift_net"] == 350.0
    assert hourly_row["undertime_minutes"] == 60.0
    assert hourly_row["shift_net"] == 65.0
    assert slip["deductions"] == 100.0
    assert slip["net_pay"] == 415.0
    assert slip["rest_day_pay"] == 15.0


def test_scenario_8_company_holiday_and_rest_day_additive_premiums():
    """Two evening shifts: regular ₱350 + holiday ₱350 + rest ₱105 = ₱805 gross."""
    first, first_asg = _shift(time(17, 0), time(19, 0), "Shift 1")
    second, second_asg = _shift(time(19, 30), time(21, 0), "Shift 2")
    first_asg.is_rest_day_work = True
    second_asg.is_rest_day_work = True
    slip = _payslip(
        pay_basis=PayBasis.hourly,
        daily_rate=None,
        hourly_rate=100.0,
        holidays=[_holiday()],
        rest_premium=30.0,
        rows=[
            (_punch(first_asg, _utc(17, 0), _utc(19, 0)), first_asg, first),
            (_punch(second_asg, _utc(19, 30), _utc(21, 0)), second_asg, second),
        ],
        scheduled=[(first_asg, first), (second_asg, second)],
    )
    assert slip["regular_pay"] == 350.0
    assert slip["holiday_pay"] == 350.0
    assert slip["rest_day_pay"] == 105.0
    assert slip["gross_pay"] == 805.0
