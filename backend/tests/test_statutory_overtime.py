"""Statutory overtime uses the basic hourly rate and the day factor once."""

from datetime import date, time
from types import SimpleNamespace

import pytest
from pydantic import ValidationError

from app.models.enums import OvertimeCalculationMethod
from app.schemas.owner_setup import PayrollConfigUpdate

from app.models.enums import HolidayType, PayBasis
from app.services.payroll_engine import (
    overtime_pay_amount,
    resolve_overtime_calculation_method,
    statutory_overtime_pay_amount,
)
from app.services.payroll_snapshot import freeze_payslip_dict
from tests.test_payroll_engine import _ot_holiday, _ph, _record, _run, _shift_pair


def _statutory_run(**kwargs):
    kwargs["overtime_calculation_method"] = "hourly_statutory"
    return _run(**kwargs)

WORK = date(2026, 8, 4)


def _near(actual, expected: float) -> None:
    assert abs(float(actual) - expected) < 0.01


def test_ordinary_overtime_hourly_is_basic_times_125_percent():
    # ₱120/hour × 1.25 × 1 hour = ₱150. The saved ₱1/minute rate is not used.
    shift, assignment = _shift_pair(time(8, 0), time(16, 0))
    record = _record(assignment, _ph(8, 0), _ph(17, 0))
    slip = _statutory_run(
        pay_basis=PayBasis.hourly,
        daily_rate=None,
        hourly_rate=120.0,
        rows=[(record, assignment, shift)],
        scheduled=[(assignment, shift)],
        overtime_per_minute=1.0,
        ot_minimum=30,
    )
    _near(slip["regular_pay"], 960.0)
    _near(slip["overtime_minutes"], 60.0)
    _near(slip["overtime_pay"], 150.0)
    _near(slip["holiday_pay"], 0.0)
    _near(slip["rest_day_pay"], 0.0)
    _near(slip["gross_pay"], 1110.0)
    assert slip["overtime_per_minute"] == 1.0
    assert slip["overtime_pay"] != overtime_pay_amount(60, 1.0, 0.0)


def test_ordinary_overtime_daily_uses_daily_rate_spread_over_scheduled_hours():
    # ₱800 / 8 hours = ₱100/hour. 1 hour × 1.25 = ₱125. One daily entitlement.
    shift, assignment = _shift_pair(time(8, 0), time(16, 0))
    record = _record(assignment, _ph(8, 0), _ph(17, 0))
    slip = _statutory_run(
        pay_basis=PayBasis.daily,
        daily_rate=800.0,
        hourly_rate=None,
        rows=[(record, assignment, shift)],
        scheduled=[(assignment, shift)],
        overtime_per_minute=2.0,
        ot_minimum=30,
    )
    _near(slip["regular_pay"], 800.0)
    _near(slip["overtime_pay"], 125.0)
    _near(slip["gross_pay"], 925.0)
    assert slip["overtime_per_minute"] == 2.0


def test_regular_holiday_overtime_is_holiday_hourly_rate_times_130_percent():
    # Basic ₱60. Holiday multiple 2. OT = 60 × 2.00 × 1.30 = ₱156.
    # Scheduled holiday premium stays 480 × (2 − 1) = ₱480, not added again.
    shift, assignment = _shift_pair(time(8, 0), time(16, 0), work_date=WORK)
    holiday = _ot_holiday(WORK, holiday_type=HolidayType.regular, pay_multiplier=2.0)
    record = _record(assignment, _ph(8, 0), _ph(17, 0))
    slip = _statutory_run(
        pay_basis=PayBasis.hourly,
        daily_rate=None,
        hourly_rate=60.0,
        rows=[(record, assignment, shift)],
        scheduled=[(assignment, shift)],
        holidays=[holiday],
        overtime_per_minute=1.0,
        ot_minimum=30,
    )
    _near(slip["regular_pay"], 480.0)
    _near(slip["holiday_pay"], 480.0)
    _near(slip["overtime_pay"], 156.0)
    _near(slip["rest_day_pay"], 0.0)
    _near(slip["gross_pay"], 1116.0)


def test_special_day_overtime_is_special_hourly_rate_times_130_percent():
    # Basic ₱60. Special multiple 1.3. OT = 60 × 1.30 × 1.30 = ₱101.40.
    # Scheduled holiday premium stays 480 × 0.30 = ₱144.
    shift, assignment = _shift_pair(time(8, 0), time(16, 0), work_date=WORK)
    holiday = _ot_holiday(
        WORK,
        holiday_type=HolidayType.special_non_working,
        pay_multiplier=1.3,
        ot_premium_percent=99.0,
    )
    record = _record(assignment, _ph(8, 0), _ph(17, 0))
    slip = _statutory_run(
        pay_basis=PayBasis.hourly,
        daily_rate=None,
        hourly_rate=60.0,
        rows=[(record, assignment, shift)],
        scheduled=[(assignment, shift)],
        holidays=[holiday],
        ot_minimum=30,
    )
    _near(slip["regular_pay"], 480.0)
    _near(slip["holiday_pay"], 144.0)
    _near(slip["overtime_pay"], 101.40)
    _near(slip["gross_pay"], 725.40)


def test_rest_day_overtime_is_rest_day_hourly_rate_times_130_percent():
    # Basic ₱100. Rest day rate 130%. OT = 100 × 1.30 × 1.30 = ₱169.
    # Scheduled rest premium stays 800 × 30% = ₱240.
    shift, assignment = _shift_pair(time(8, 0), time(16, 0))
    assignment.is_rest_day_work = True
    record = _record(assignment, _ph(8, 0), _ph(17, 0))
    slip = _statutory_run(
        pay_basis=PayBasis.hourly,
        daily_rate=None,
        hourly_rate=100.0,
        rows=[(record, assignment, shift)],
        scheduled=[(assignment, shift)],
        rest_premium=30.0,
        rest_day_ot=40.0,
        overtime_per_minute=1.0,
        ot_minimum=30,
    )
    _near(slip["regular_pay"], 800.0)
    _near(slip["rest_day_pay"], 240.0)
    _near(slip["holiday_pay"], 0.0)
    _near(slip["overtime_pay"], 169.0)
    _near(slip["gross_pay"], 1209.0)


def test_regular_holiday_rest_day_overtime_uses_combined_day_rate_once():
    # Day rate = ₱100 × 2.00 × 1.30 = ₱260. OT = 260 × 1.30 = ₱338.
    # Scheduled hours: basic ₱800 + holiday ₱800 + rest ₱480 (30% of the
    # ₱1,600 holiday rate) = 260% of basic. Rest is not 30% of basic again.
    shift, assignment = _shift_pair(time(8, 0), time(16, 0), work_date=WORK)
    assignment.is_rest_day_work = True
    holiday = _ot_holiday(WORK, holiday_type=HolidayType.regular, pay_multiplier=2.0)
    record = _record(assignment, _ph(8, 0), _ph(17, 0))
    slip = _statutory_run(
        pay_basis=PayBasis.hourly,
        daily_rate=None,
        hourly_rate=100.0,
        rows=[(record, assignment, shift)],
        scheduled=[(assignment, shift)],
        holidays=[holiday],
        rest_premium=30.0,
        ot_minimum=30,
    )
    _near(slip["regular_pay"], 800.0)
    _near(slip["holiday_pay"], 800.0)
    _near(slip["rest_day_pay"], 480.0)
    _near(slip["overtime_pay"], 338.0)
    _near(slip["gross_pay"], 2418.0)


def test_special_rest_day_overtime_uses_150_percent_day_rate_once():
    # Combined special rest day is 150% of basic, then × 1.30 = ₱195.
    # Scheduled hours are 150% once: ₱400 holiday premium and no second rest premium.
    shift, assignment = _shift_pair(time(8, 0), time(16, 0), work_date=WORK)
    assignment.is_rest_day_work = True
    holiday = _ot_holiday(
        WORK, holiday_type=HolidayType.special_non_working, pay_multiplier=1.3
    )
    record = _record(assignment, _ph(8, 0), _ph(17, 0))
    slip = _statutory_run(
        pay_basis=PayBasis.hourly,
        daily_rate=None,
        hourly_rate=100.0,
        rows=[(record, assignment, shift)],
        scheduled=[(assignment, shift)],
        holidays=[holiday],
        rest_premium=30.0,
        ot_minimum=30,
    )
    _near(slip["regular_pay"], 800.0)
    _near(slip["holiday_pay"], 400.0)
    _near(slip["rest_day_pay"], 0.0)
    _near(slip["overtime_pay"], 195.0)
    _near(slip["gross_pay"], 1395.0)


def test_zero_overtime_when_the_punch_ends_at_the_scheduled_end():
    shift, assignment = _shift_pair(time(8, 0), time(16, 0))
    record = _record(assignment, _ph(8, 0), _ph(16, 0))
    slip = _statutory_run(
        pay_basis=PayBasis.hourly,
        daily_rate=None,
        hourly_rate=100.0,
        rows=[(record, assignment, shift)],
        scheduled=[(assignment, shift)],
        ot_minimum=0,
    )
    _near(slip["regular_pay"], 800.0)
    _near(slip["overtime_minutes"], 0.0)
    _near(slip["overtime_pay"], 0.0)
    _near(slip["gross_pay"], 800.0)


def test_two_shifts_price_only_the_shift_that_actually_ran_past_its_end():
    # Each shift is ₱100 × 4 hours. Only the second runs 1 hour past its end.
    # OT = 100 × 1.25 = ₱125 once, not twice, and regular pay stays ₱800.
    morning, morning_asg = _shift_pair(time(8, 0), time(12, 0), name="AM")
    evening, evening_asg = _shift_pair(time(13, 0), time(17, 0), name="PM")
    rows = [
        (_record(morning_asg, _ph(8, 0), _ph(12, 0)), morning_asg, morning),
        (_record(evening_asg, _ph(13, 0), _ph(18, 0)), evening_asg, evening),
    ]
    slip = _statutory_run(
        pay_basis=PayBasis.hourly,
        daily_rate=None,
        hourly_rate=100.0,
        rows=rows,
        scheduled=[(morning_asg, morning), (evening_asg, evening)],
        ot_minimum=30,
    )
    _near(slip["regular_pay"], 800.0)
    _near(slip["overtime_minutes"], 60.0)
    _near(slip["overtime_pay"], 125.0)
    _near(slip["holiday_pay"], 0.0)
    _near(slip["rest_day_pay"], 0.0)
    by_shift = {row["shift_name"]: row for row in slip["attendance_records"]}
    _near(by_shift["AM"]["overtime_pay"], 0.0)
    _near(by_shift["PM"]["overtime_pay"], 125.0)


def test_daily_two_shifts_keep_one_entitlement_and_one_overtime_amount():
    # Day is 8 scheduled hours, so ₱800 becomes ₱100/hour. One hour of OT = ₱125.
    morning, morning_asg = _shift_pair(time(8, 0), time(12, 0), name="AM")
    evening, evening_asg = _shift_pair(time(13, 0), time(17, 0), name="PM")
    rows = [
        (_record(morning_asg, _ph(8, 0), _ph(12, 0)), morning_asg, morning),
        (_record(evening_asg, _ph(13, 0), _ph(18, 0)), evening_asg, evening),
    ]
    slip = _statutory_run(
        pay_basis=PayBasis.daily,
        daily_rate=800.0,
        hourly_rate=None,
        rows=rows,
        scheduled=[(morning_asg, morning), (evening_asg, evening)],
        ot_minimum=30,
    )
    _near(slip["regular_pay"], 800.0)
    _near(slip["overtime_pay"], 125.0)
    _near(slip["gross_pay"], 925.0)


def test_missing_hourly_rate_does_not_fall_back_to_the_saved_minute_rate():
    assert statutory_overtime_pay_amount(60, 0.0) == 0.0
    assert statutory_overtime_pay_amount(0, 100.0) == 0.0


def test_default_method_uses_the_saved_peso_per_minute_rate():
    shift, assignment = _shift_pair(time(8, 0), time(12, 0))
    record = _record(assignment, _ph(8, 0), _ph(13, 0))
    slip = _run(
        pay_basis=PayBasis.hourly,
        daily_rate=None,
        hourly_rate=100.0,
        rows=[(record, assignment, shift)],
        scheduled=[(assignment, shift)],
        overtime_per_minute=1.0,
        ot_minimum=30,
    )
    _near(slip["overtime_minutes"], 60.0)
    _near(slip["overtime_pay"], 60.0)
    _near(slip["regular_pay"], 400.0)
    assert slip["overtime_per_minute"] == 1.0
    assert slip["overtime_calculation_method"] == "flat_per_minute"
    assert resolve_overtime_calculation_method(None) == "flat_per_minute"


def test_short_shift_qualifies_past_its_own_end_in_both_methods():
    # Four scheduled hours. One hour past the end is overtime. Eight hours is not required.
    shift, assignment = _shift_pair(time(8, 0), time(12, 0))
    record = _record(assignment, _ph(8, 0), _ph(13, 0))
    kwargs = dict(
        pay_basis=PayBasis.hourly,
        daily_rate=None,
        hourly_rate=100.0,
        rows=[(record, assignment, shift)],
        scheduled=[(assignment, shift)],
        overtime_per_minute=1.0,
        ot_minimum=30,
    )
    flat = _run(**kwargs)
    hourly = _statutory_run(**kwargs)
    _near(flat["overtime_minutes"], 60.0)
    _near(hourly["overtime_minutes"], 60.0)
    _near(flat["overtime_pay"], 60.0)
    _near(hourly["overtime_pay"], 125.0)
    _near(flat["regular_pay"], 400.0)
    _near(hourly["regular_pay"], 400.0)


def test_flat_rest_day_and_holiday_keep_the_saved_minute_rate():
    shift, assignment = _shift_pair(time(8, 0), time(16, 0))
    assignment.is_rest_day_work = True
    rest = _run(
        pay_basis=PayBasis.hourly,
        daily_rate=None,
        hourly_rate=100.0,
        rows=[(_record(assignment, _ph(8, 0), _ph(17, 0)), assignment, shift)],
        scheduled=[(assignment, shift)],
        rest_premium=30.0,
        overtime_per_minute=1.0,
        ot_minimum=30,
    )
    _near(rest["rest_day_pay"], 240.0)
    _near(rest["overtime_pay"], 60.0)

    holiday_shift, holiday_asg = _shift_pair(time(8, 0), time(16, 0), work_date=WORK)
    holiday = _ot_holiday(
        WORK, holiday_type=HolidayType.regular, pay_multiplier=2.0, ot_premium_percent=30.0
    )
    holiday_slip = _run(
        pay_basis=PayBasis.hourly,
        daily_rate=None,
        hourly_rate=60.0,
        rows=[(_record(holiday_asg, _ph(8, 0), _ph(17, 0)), holiday_asg, holiday_shift)],
        scheduled=[(holiday_asg, holiday_shift)],
        holidays=[holiday],
        overtime_per_minute=1.0,
        ot_minimum=30,
    )
    _near(holiday_slip["holiday_pay"], 480.0)
    _near(holiday_slip["overtime_pay"], overtime_pay_amount(60, 1.0, 30.0))
    assert holiday_slip["overtime_calculation_method"] == "flat_per_minute"


def test_flat_rate_ignores_the_completion_hourly_rate():
    shift, assignment = _shift_pair(time(8, 0), time(16, 0))
    low = _run(
        pay_basis=PayBasis.hourly,
        daily_rate=None,
        hourly_rate=100.0,
        rows=[(_record(assignment, _ph(8, 0), _ph(17, 0)), assignment, shift)],
        scheduled=[(assignment, shift)],
        overtime_per_minute=1.0,
        ot_minimum=30,
    )
    high_shift, high_asg = _shift_pair(time(8, 0), time(16, 0))
    high = _run(
        pay_basis=PayBasis.hourly,
        daily_rate=None,
        hourly_rate=200.0,
        rows=[(_record(high_asg, _ph(8, 0), _ph(17, 0)), high_asg, high_shift)],
        scheduled=[(high_asg, high_shift)],
        overtime_per_minute=1.0,
        ot_minimum=30,
    )
    _near(low["overtime_pay"], 60.0)
    _near(high["overtime_pay"], 60.0)
    _near(low["regular_pay"], 800.0)
    _near(high["regular_pay"], 1600.0)


def test_pending_approval_still_withholds_overtime_pay():
    shift, assignment = _shift_pair(time(8, 0), time(16, 0))
    slip = _run(
        pay_basis=PayBasis.hourly,
        daily_rate=None,
        hourly_rate=100.0,
        rows=[(_record(assignment, _ph(8, 0), _ph(17, 0)), assignment, shift)],
        scheduled=[(assignment, shift)],
        overtime_per_minute=1.0,
        ot_minimum=30,
        overtime_approval_required=True,
    )
    _near(slip["worked_overtime_minutes"], 60.0)
    _near(slip["overtime_minutes"], 0.0)
    _near(slip["overtime_pay"], 0.0)


def test_frozen_snapshot_keeps_the_overtime_amount_that_was_stored():
    shift, assignment = _shift_pair(time(8, 0), time(16, 0))
    live = _run(
        pay_basis=PayBasis.hourly,
        daily_rate=None,
        hourly_rate=100.0,
        rows=[(_record(assignment, _ph(8, 0), _ph(17, 0)), assignment, shift)],
        scheduled=[(assignment, shift)],
        overtime_per_minute=1.0,
        ot_minimum=30,
    )
    frozen = freeze_payslip_dict(live)
    later_shift, later_asg = _shift_pair(time(8, 0), time(16, 0))
    later = _statutory_run(
        pay_basis=PayBasis.hourly,
        daily_rate=None,
        hourly_rate=100.0,
        rows=[(_record(later_asg, _ph(8, 0), _ph(17, 0)), later_asg, later_shift)],
        scheduled=[(later_asg, later_shift)],
        overtime_per_minute=1.0,
        ot_minimum=30,
    )
    _near(frozen["overtime_pay"], 60.0)
    _near(later["overtime_pay"], 125.0)
    assert frozen["overtime_pay"] != later["overtime_pay"]
    assert frozen["overtime_calculation_method"] == "flat_per_minute"


@pytest.mark.parametrize(
    ("end_hour", "daily_rate"),
    [(12, 400.0), (14, 600.0), (15, 700.0), (16, 800.0)],
)
def test_daily_overtime_uses_that_shifts_scheduled_hours(end_hour, daily_rate):
    # ₱400/4h, ₱600/6h, ₱700/7h, and ₱800/8h are each ₱100 per hour.
    # One ordinary hour × 1.25 = ₱125. The flat method stays ₱60.
    hours = end_hour - 8
    shift, assignment = _shift_pair(time(8, 0), time(end_hour, 0))
    record = _record(assignment, _ph(8, 0), _ph(end_hour + 1, 0))
    kwargs = dict(
        pay_basis=PayBasis.daily,
        daily_rate=daily_rate,
        hourly_rate=None,
        rows=[(record, assignment, shift)],
        scheduled=[(assignment, shift)],
        overtime_per_minute=1.0,
        ot_minimum=30,
    )
    statutory = _statutory_run(**kwargs)
    flat = _run(**kwargs)
    _near(statutory["overtime_minutes"], 60.0)
    _near(flat["overtime_minutes"], 60.0)
    _near(statutory["regular_pay"], daily_rate)
    _near(flat["regular_pay"], daily_rate)
    _near(statutory["overtime_pay"], 125.0)
    _near(flat["overtime_pay"], 60.0)
    assert hours in (4, 6, 7, 8)


def test_daily_six_hour_shift_uses_its_own_rate_not_an_eight_hour_divisor():
    # ₱600 / 6 hours = ₱100. ₱900 / 6 hours = ₱150. Neither uses 8 hours.
    def _one(daily_rate: float):
        shift, assignment = _shift_pair(time(8, 0), time(14, 0))
        record = _record(assignment, _ph(8, 0), _ph(15, 0))
        return _statutory_run(
            pay_basis=PayBasis.daily,
            daily_rate=daily_rate,
            hourly_rate=None,
            rows=[(record, assignment, shift)],
            scheduled=[(assignment, shift)],
            overtime_per_minute=1.0,
            ot_minimum=30,
        )

    six_hundred = _one(600.0)
    nine_hundred = _one(900.0)
    _near(six_hundred["overtime_pay"], 125.0)
    _near(nine_hundred["overtime_pay"], 187.50)
    _near(six_hundred["regular_pay"], 600.0)
    _near(nine_hundred["regular_pay"], 900.0)


def test_missing_scheduled_hours_do_not_invent_an_hourly_overtime_rate():
    # A 60-minute span with a 90-minute unpaid break has no paid hours.
    # The clock-out is still one hour after the scheduled end.
    shift, assignment = _shift_pair(time(8, 0), time(9, 0), break_minutes=90)
    record = _record(assignment, _ph(8, 0), _ph(10, 0))
    kwargs = dict(
        pay_basis=PayBasis.daily,
        daily_rate=600.0,
        hourly_rate=None,
        rows=[(record, assignment, shift)],
        scheduled=[(assignment, shift)],
        overtime_per_minute=1.0,
        ot_minimum=0,
    )
    statutory = _statutory_run(**kwargs)
    flat = _run(**kwargs)
    _near(statutory["overtime_minutes"], 60.0)
    _near(flat["overtime_minutes"], 60.0)
    _near(statutory["overtime_pay"], 0.0)
    _near(flat["overtime_pay"], 60.0)
    _near(statutory["regular_pay"], 600.0)


def test_company_holiday_overtime_keeps_scheduled_premium_outside_the_ot_amount():
    shift, assignment = _shift_pair(time(8, 0), time(16, 0), work_date=WORK)
    holiday = _ot_holiday(
        WORK,
        holiday_type=HolidayType.company,
        pay_multiplier=1.5,
        ot_premium_percent=20.0,
    )
    kwargs = dict(
        pay_basis=PayBasis.hourly,
        daily_rate=None,
        hourly_rate=100.0,
        rows=[(_record(assignment, _ph(8, 0), _ph(17, 0)), assignment, shift)],
        scheduled=[(assignment, shift)],
        holidays=[holiday],
        overtime_per_minute=1.0,
        ot_minimum=30,
    )
    statutory = _statutory_run(**kwargs)
    flat = _run(**kwargs)
    _near(statutory["holiday_pay"], 400.0)
    _near(flat["holiday_pay"], 400.0)
    _near(statutory["regular_pay"], 800.0)
    # ₱100 × saved 1.50 × 1.30. The ₱400 holiday premium is not added again.
    _near(statutory["overtime_pay"], 195.0)
    _near(flat["overtime_pay"], overtime_pay_amount(60, 1.0, 20.0))


def test_daily_regular_holiday_on_a_rest_day_pays_260_percent_of_basic():
    shift, assignment = _shift_pair(time(8, 0), time(16, 0), work_date=WORK)
    assignment.is_rest_day_work = True
    holiday = _ot_holiday(WORK, holiday_type=HolidayType.regular, pay_multiplier=2.0)
    record = _record(assignment, _ph(8, 0), _ph(16, 0))
    slip = _run(
        pay_basis=PayBasis.daily,
        daily_rate=800.0,
        hourly_rate=None,
        rows=[(record, assignment, shift)],
        scheduled=[(assignment, shift)],
        holidays=[holiday],
        rest_premium=30.0,
        ot_minimum=30,
    )
    _near(slip["regular_pay"], 800.0)
    _near(slip["holiday_pay"], 800.0)
    _near(slip["rest_day_pay"], 480.0)
    _near(slip["overtime_pay"], 0.0)
    _near(slip["gross_pay"], 2080.0)


def test_daily_special_day_on_a_rest_day_pays_150_percent_once():
    shift, assignment = _shift_pair(time(8, 0), time(16, 0), work_date=WORK)
    assignment.is_rest_day_work = True
    holiday = _ot_holiday(
        WORK, holiday_type=HolidayType.special_non_working, pay_multiplier=1.3
    )
    record = _record(assignment, _ph(8, 0), _ph(16, 0))
    slip = _run(
        pay_basis=PayBasis.daily,
        daily_rate=600.0,
        hourly_rate=None,
        rows=[(record, assignment, shift)],
        scheduled=[(assignment, shift)],
        holidays=[holiday],
        rest_premium=30.0,
        ot_minimum=30,
    )
    _near(slip["regular_pay"], 600.0)
    _near(slip["holiday_pay"], 300.0)
    _near(slip["rest_day_pay"], 0.0)
    _near(slip["gross_pay"], 900.0)


def test_unknown_method_stays_on_the_saved_flat_rate():
    assert resolve_overtime_calculation_method(
        SimpleNamespace(overtime_calculation_method="not-a-method")
    ) == "flat_per_minute"
    assert (
        resolve_overtime_calculation_method(
            SimpleNamespace(
                overtime_calculation_method=OvertimeCalculationMethod.hourly_statutory
            )
        )
        == "hourly_statutory"
    )
    first = SimpleNamespace(overtime_calculation_method="hourly_statutory")
    second = SimpleNamespace(overtime_calculation_method=None)
    assert resolve_overtime_calculation_method(first) == "hourly_statutory"
    assert resolve_overtime_calculation_method(second) == "flat_per_minute"


def test_payroll_config_rejects_an_unknown_overtime_method():
    with pytest.raises(ValidationError):
        PayrollConfigUpdate(overtime_calculation_method="double_time")
    kept = PayrollConfigUpdate(overtime_per_minute=3.5)
    assert kept.overtime_calculation_method is None
    assert kept.overtime_per_minute == 3.5
