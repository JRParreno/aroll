"""Payroll adjustments apply after live payroll computation."""

from datetime import date
from types import SimpleNamespace

from app.services.payroll_adjustments import (
    apply_adjustments_to_slip,
    totals_from_rows,
    adjustments_editable,
)


def test_totals_from_rows_deductions_and_allowances():
    rows = [
        SimpleNamespace(kind="deduction", amount=500),
        SimpleNamespace(kind="deduction", amount=250),
        SimpleNamespace(kind="allowance", amount=100),
    ]
    deduction_total, allowance_total, net_adjustment = totals_from_rows(rows)
    assert deduction_total == 750
    assert allowance_total == 100
    assert net_adjustment == 650


def test_apply_adjustments_preserves_base_net_pay():
    slip = {
        "period_start": "2026-08-01",
        "period_end": "2026-08-15",
        "net_pay": 10000,
    }
    rows = [
        SimpleNamespace(
            id="1",
            employee_id="e1",
            period_start=date(2026, 8, 1),
            period_end=date(2026, 8, 15),
            kind="deduction",
            type_key="cash_shortage",
            custom_name=None,
            description="Till short",
            amount=500,
            created_by=None,
            created_at=None,
            updated_by=None,
            updated_at=None,
            previous_amount=None,
        )
    ]
    enriched = apply_adjustments_to_slip(slip, rows, today=date(2026, 8, 10))
    assert enriched["net_pay"] == 10000
    assert enriched["base_net_pay"] == 10000
    assert enriched["final_net_pay"] == 9500
    assert enriched["adjustments_editable"] is True
    assert len(enriched["payroll_adjustments"]) == 1


def test_adjustments_read_only_after_period_ends():
    assert adjustments_editable(date(2026, 8, 15), today=date(2026, 8, 15)) is True
    assert adjustments_editable(date(2026, 8, 15), today=date(2026, 8, 16)) is False
