"""Downloaded payslip receipt: rates, rest-day earnings, no rest-day dates."""

from app.api.employee_mobile import (
    PAYSLIP_RECEIPT_WIDTH,
    _payslip_display_rates,
    _simple_payslip_pdf,
)


def _base(**overrides):
    data = {
        "business_name": "Test Cafe",
        "employee_name": "Sample Emp",
        "position_title": "Cashier",
        "period_start": "2026-08-01",
        "period_end": "2026-08-15",
        "worked_days": 2,
        "hours_worked": 8.0,
        "pay_basis": "daily",
        "daily_rate": 350.0,
        "hourly_rate": None,
        "regular_pay": 700.0,
        "leave_pay": 0.0,
        "overtime_pay": 0.0,
        "holiday_pay": 0.0,
        "rest_day_pay": 35.0,
        "gross_pay": 735.0,
        "deductions": 0.0,
        "net_pay": 735.0,
        "rest_day_records": [
            {
                "date": "2026-08-02",
                "weekday": "sunday",
                "time_in": "2026-08-02T10:00:00+00:00",
                "time_out": "2026-08-02T18:00:00+00:00",
                "shift_name": "Evening",
                "premium_pay": 35.0,
            }
        ],
    }
    data.update(overrides)
    return data


def test_rest_day_attendance_details_are_omitted_from_employee_pdf():
    pdf = _simple_payslip_pdf(_base())
    assert b"Rest day premium: PHP 35.00" in pdf
    assert b"Rest Day Work" not in pdf
    assert b"2026-08-02" not in pdf
    assert b"Evening" not in pdf
    assert b"sunday" not in pdf
    assert b"Gross pay: PHP 735.00" in pdf
    assert b"Final net pay: PHP 735.00" in pdf


def test_daily_rate_populated_hourly_rate_blank():
    daily, hourly = _payslip_display_rates(_base(pay_basis="daily", daily_rate=350.0, hourly_rate=80.0))
    assert daily == 350.0
    assert hourly is None
    pdf = _simple_payslip_pdf(_base(pay_basis="daily", daily_rate=350.0, hourly_rate=80.0))
    assert b"Daily Rate: PHP 350.00" in pdf
    assert b"Hourly Rate:" in pdf
    assert b"Hourly Rate: PHP" not in pdf
    assert b"80.00" not in pdf


def test_hourly_rate_populated_daily_rate_blank():
    daily, hourly = _payslip_display_rates(
        _base(pay_basis="hourly", daily_rate=650.0, hourly_rate=100.0)
    )
    assert daily is None
    assert hourly == 100.0
    pdf = _simple_payslip_pdf(
        _base(pay_basis="hourly", daily_rate=650.0, hourly_rate=100.0, regular_pay=800.0)
    )
    assert b"Hourly Rate: PHP 100.00" in pdf
    assert b"Daily Rate:" in pdf
    assert b"Daily Rate: PHP" not in pdf
    assert b"650.00" not in pdf


def test_missing_rate_stays_blank():
    daily, hourly = _payslip_display_rates(
        _base(pay_basis="daily", daily_rate=None, hourly_rate=None)
    )
    assert daily is None
    assert hourly is None
    pdf = _simple_payslip_pdf(_base(pay_basis="daily", daily_rate=None, hourly_rate=None))
    assert b"Daily Rate:" in pdf
    assert b"Hourly Rate:" in pdf
    assert b"Daily Rate: PHP" not in pdf
    assert b"Hourly Rate: PHP" not in pdf
    assert b"0.00" not in pdf.split(b"Daily Rate:")[1][:20]


def test_both_rates_when_no_exclusive_basis():
    daily, hourly = _payslip_display_rates(
        {
            "pay_basis": "",
            "daily_rate": 350.0,
            "hourly_rate": 100.0,
        }
    )
    assert daily == 350.0
    assert hourly == 100.0


def test_receipt_page_is_narrow_and_single_page():
    pdf = _simple_payslip_pdf(_base())
    assert f"/MediaBox [0 0 {PAYSLIP_RECEIPT_WIDTH} ".encode() in pdf
    assert b"/MediaBox [0 0 612 792]" not in pdf
    assert b"/Count 1" in pdf
    assert b"Rest Day Work" not in pdf
