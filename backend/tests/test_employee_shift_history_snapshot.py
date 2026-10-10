"""Employee mobile Shift History uses frozen payslip snapshots when finalized."""

from datetime import date
from types import SimpleNamespace
from unittest.mock import MagicMock, patch
from uuid import uuid4

from app.api.employee_mobile import (
    _overlay_shift_history_with_finalized_snapshots,
    shift_history,
)
from app.models.employee import Employee
from app.models.enums import UserRole
from app.models.user import User
from app.services.payroll_snapshot import PAYSLIP_SNAPSHOT_VERSION, PayslipLoad


WORK_DATE = date(2026, 9, 10)
PERIOD_START = date(2026, 9, 1)
PERIOD_END = date(2026, 9, 15)
ASSIGNMENT_ID = uuid4()


def _empty_live_load():
    return PayslipLoad(
        slip=None,
        period_start=PERIOD_START,
        period_end=PERIOD_END,
        from_snapshot=False,
        payroll_run=None,
    )


def _employee():
    return Employee(
        id=uuid4(),
        business_id=uuid4(),
        full_name="Ana Reyes",
        is_active=True,
    )


def _live_item(*, time_in="live-in", time_out="live-out", status="late", ot=120.0):
    return {
        "id": str(uuid4()),
        "assignment_id": str(ASSIGNMENT_ID),
        "attendance_record_id": str(uuid4()),
        "date": WORK_DATE.isoformat(),
        "shift_name": "Morning",
        "shift_start": "8:00 AM",
        "shift_end": "5:00 PM",
        "time_in": time_in,
        "time_out": time_out,
        "status": status,
        "overtime_minutes": ot,
        "holiday_name": None,
        "can_request_correction": True,
        "correction_status": None,
        "correction_id": None,
        "correction_review_note": None,
    }


def _frozen_slip(employee_id, *, time_in, time_out, status, worked_ot, holiday=None):
    return {
        "employee_id": str(employee_id),
        "period_start": PERIOD_START.isoformat(),
        "period_end": PERIOD_END.isoformat(),
        "attendance_records": [
            {
                "date": WORK_DATE.isoformat(),
                "status": status,
                "time_in": time_in,
                "time_out": time_out,
                "shift_name": "Morning",
                "shift_assignment_id": str(ASSIGNMENT_ID),
                "holiday_name": holiday,
                "late_minutes": 20.0,
                "undertime_minutes": 0.0,
                "ot": {
                    "worked_ot_minutes": worked_ot,
                    "payable_ot_minutes": worked_ot,
                },
            }
        ],
        "snapshot_version": PAYSLIP_SNAPSHOT_VERSION,
    }


def _finalized_run():
    return SimpleNamespace(
        id=uuid4(),
        period_start=PERIOD_START,
        period_end=PERIOD_END,
        snapshot_version=PAYSLIP_SNAPSHOT_VERSION,
    )


def test_before_finalization_shift_history_stays_live():
    employee = _employee()
    items = [_live_item()]
    db = MagicMock()

    with patch(
        "app.services.payroll_snapshot.find_snapshot_run",
        return_value=None,
    ) as find_run, patch(
        "app.services.payroll_snapshot.payslips_for_run",
    ) as payslips, patch(
        "app.services.payroll_snapshot.load_period_payslip",
        return_value=_empty_live_load(),
    ):
        result = _overlay_shift_history_with_finalized_snapshots(db, employee, items)

    assert find_run.called
    assert not payslips.called
    assert result[0]["time_in"] == "live-in"
    assert result[0]["time_out"] == "live-out"
    assert result[0]["status"] == "late"
    assert result[0]["overtime_minutes"] == 120.0


def test_after_finalization_uses_frozen_snapshot():
    employee = _employee()
    items = [_live_item()]
    run = _finalized_run()
    frozen = _frozen_slip(
        employee.id,
        time_in="2026-09-10T00:00:00+00:00",
        time_out="2026-09-10T09:00:00+00:00",
        status="late",
        worked_ot=90.0,
        holiday="National Day",
    )
    payslip_row = SimpleNamespace(
        employee_id=employee.id,
        breakdown_json=frozen,
    )
    db = MagicMock()

    with patch(
        "app.services.payroll_snapshot.find_snapshot_run",
        return_value=run,
    ), patch(
        "app.services.payroll_snapshot.payslips_for_run",
        return_value=[payslip_row],
    ), patch(
        "app.services.payroll_snapshot.snapshot_payslip_dict",
        return_value=frozen,
    ):
        result = _overlay_shift_history_with_finalized_snapshots(db, employee, items)

    assert result[0]["time_in"] == frozen["attendance_records"][0]["time_in"]
    assert result[0]["time_out"] == frozen["attendance_records"][0]["time_out"]
    assert result[0]["status"] == "late"
    assert result[0]["overtime_minutes"] == 90.0
    assert result[0]["holiday_name"] == "National Day"
    # Correction UX fields remain from the live item (not invented from snapshot).
    assert result[0]["can_request_correction"] is True
    assert result[0]["shift_start"] == "8:00 AM"


def test_live_attendance_change_does_not_change_finalized_display():
    employee = _employee()
    items = [
        _live_item(
            time_in="CHANGED-LIVE-IN",
            time_out="CHANGED-LIVE-OUT",
            status="complete",
            ot=999.0,
        )
    ]
    run = _finalized_run()
    frozen = _frozen_slip(
        employee.id,
        time_in="SNAP-IN",
        time_out="SNAP-OUT",
        status="late",
        worked_ot=45.0,
    )
    db = MagicMock()

    with patch(
        "app.services.payroll_snapshot.find_snapshot_run",
        return_value=run,
    ), patch(
        "app.services.payroll_snapshot.payslips_for_run",
        return_value=[SimpleNamespace(employee_id=employee.id, breakdown_json=frozen)],
    ), patch(
        "app.services.payroll_snapshot.snapshot_payslip_dict",
        return_value=frozen,
    ):
        result = _overlay_shift_history_with_finalized_snapshots(db, employee, items)

    assert result[0]["time_in"] == "SNAP-IN"
    assert result[0]["time_out"] == "SNAP-OUT"
    assert result[0]["status"] == "late"
    assert result[0]["overtime_minutes"] == 45.0


def test_after_unfinalize_returns_to_live():
    employee = _employee()
    items = [
        _live_item(
            time_in="live-again",
            time_out="live-out-2",
            status="complete",
            ot=30.0,
        )
    ]
    db = MagicMock()

    with patch(
        "app.services.payroll_snapshot.find_snapshot_run",
        return_value=None,
    ), patch(
        "app.services.payroll_snapshot.load_period_payslip",
        return_value=_empty_live_load(),
    ):
        result = _overlay_shift_history_with_finalized_snapshots(db, employee, items)

    assert result[0]["time_in"] == "live-again"
    assert result[0]["status"] == "complete"
    assert result[0]["overtime_minutes"] == 30.0


def test_after_refinalize_uses_new_snapshot():
    employee = _employee()
    old_run = _finalized_run()
    new_run = _finalized_run()
    old_frozen = _frozen_slip(
        employee.id,
        time_in="OLD-IN",
        time_out="OLD-OUT",
        status="late",
        worked_ot=10.0,
    )
    new_frozen = _frozen_slip(
        employee.id,
        time_in="NEW-IN",
        time_out="NEW-OUT",
        status="complete",
        worked_ot=120.0,
    )
    db = MagicMock()

    with patch(
        "app.services.payroll_snapshot.find_snapshot_run",
        side_effect=[old_run, new_run],
    ), patch(
        "app.services.payroll_snapshot.payslips_for_run",
        side_effect=[
            [SimpleNamespace(employee_id=employee.id, breakdown_json=old_frozen)],
            [SimpleNamespace(employee_id=employee.id, breakdown_json=new_frozen)],
        ],
    ), patch(
        "app.services.payroll_snapshot.snapshot_payslip_dict",
        side_effect=[old_frozen, new_frozen],
    ):
        first = _overlay_shift_history_with_finalized_snapshots(
            db, employee, [_live_item()]
        )
        second = _overlay_shift_history_with_finalized_snapshots(
            db, employee, [_live_item()]
        )

    assert first[0]["time_in"] == "OLD-IN"
    assert first[0]["overtime_minutes"] == 10.0
    assert second[0]["time_in"] == "NEW-IN"
    assert second[0]["status"] == "complete"
    assert second[0]["overtime_minutes"] == 120.0


def test_overlay_does_not_call_live_payslip_calculation():
    employee = _employee()
    items = [_live_item()]
    run = _finalized_run()
    frozen = _frozen_slip(
        employee.id,
        time_in="SNAP-IN",
        time_out="SNAP-OUT",
        status="late",
        worked_ot=60.0,
    )
    db = MagicMock()

    with patch(
        "app.services.payroll_snapshot.find_snapshot_run",
        return_value=run,
    ), patch(
        "app.services.payroll_snapshot.payslips_for_run",
        return_value=[SimpleNamespace(employee_id=employee.id, breakdown_json=frozen)],
    ), patch(
        "app.services.payroll_snapshot.snapshot_payslip_dict",
        return_value=frozen,
    ), patch(
        "app.api.employee_mobile._calculate_employee_payslip",
    ) as calc:
        _overlay_shift_history_with_finalized_snapshots(db, employee, items)

    assert not calc.called


def test_employee_shift_history_endpoint_uses_current_employee_only():
    """Endpoint scopes history through _current_employee — no other-employee param."""
    employee = _employee()
    business = SimpleNamespace(id=employee.business_id, timezone="Asia/Manila")
    user = User(
        id=uuid4(),
        business_id=employee.business_id,
        role=UserRole.employee,
        is_active=True,
    )
    db = MagicMock()

    with patch(
        "app.api.employee_mobile._current_employee",
        return_value=(employee, business),
    ) as current, patch(
        "app.api.employee_mobile.business_today",
        return_value=WORK_DATE,
    ), patch(
        "app.api.employee_mobile._shift_history_rows",
        return_value=[_live_item()],
    ) as rows:
        payload = shift_history(db=db, user=user)

    current.assert_called_once()
    assert current.call_args.args[1] is user
    rows.assert_called_once()
    assert rows.call_args.args[1] is employee
    assert "items" in payload
    assert rows.call_args.kwargs.get("employee_id") is None
