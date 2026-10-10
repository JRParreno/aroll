"""Employee Shift History shows a same-day no-show after that shift's deadline.

Visibility only. These tests do not calculate payroll or create attendance.
"""

from __future__ import annotations

from datetime import date, datetime, time, timedelta
from types import SimpleNamespace
from unittest.mock import MagicMock, patch
from uuid import uuid4

from app.api.employee_mobile import _shift_history_rows
from app.models.attendance import AttendanceRecord
from app.models.enums import AttendanceStatus, HolidayType
from app.models.holiday import Holiday
from app.models.scheduling import Shift, ShiftAssignment
from app.services.payroll_snapshot import PAYSLIP_SNAPSHOT_VERSION, PayslipLoad


WORK = date(2026, 9, 28)
GRACE = 5


def _employee_shift(start: time, end: time, name: str, *, employee_id, business_id, work_date=WORK):
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
        work_date=work_date,
        is_rest_day_work=False,
    )
    return shift, assignment


def _record(assignment, shift, status, *, punched: bool):
    start = datetime.combine(assignment.work_date, shift.start_time)
    return AttendanceRecord(
        id=uuid4(),
        business_id=shift.business_id,
        employee_id=assignment.employee_id,
        shift_assignment_id=assignment.id,
        time_in=start if punched else None,
        time_out=(start + timedelta(hours=2)) if punched else None,
        status=status,
    )


def _paid_holiday() -> Holiday:
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


def _ids():
    return uuid4(), uuid4()


def _rows(
    *,
    now: datetime,
    past,
    today_rows,
    employee_id,
    business_id,
    holidays=None,
    on_approved_leave=False,
    on_payroll_leave=False,
    live_slip=None,
    snapshot=None,
):
    """Run history with the main query and the today-only query separated."""
    employee = SimpleNamespace(id=employee_id, business_id=business_id)
    db = MagicMock()
    query = MagicMock()
    db.query.return_value = query
    filtered = query.join.return_value.outerjoin.return_value.filter.return_value
    filtered.order_by.return_value.limit.return_value.all.return_value = past
    filtered.all.return_value = today_rows
    db.get.return_value = SimpleNamespace(
        holiday_rules_mode=None,
        on_time_grace_minutes=GRACE,
    )

    patches = [
        patch("app.api.employee_mobile.ensure_incomplete_for_employee"),
        patch("app.api.employee_mobile._holiday_map", return_value=holidays or {}),
        patch(
            "app.services.attendance_correction.latest_corrections_by_assignment",
            return_value={},
        ),
        patch(
            "app.services.leave_requests.employee_on_approved_leave",
            return_value=on_approved_leave,
        ),
        patch(
            "app.services.leave_requests.employee_on_payroll_active_leave",
            return_value=on_payroll_leave,
        ),
        patch("app.core.timezone.business_now", return_value=now),
    ]
    if snapshot is None and live_slip is None:
        patches.append(
            patch(
                "app.api.employee_mobile._overlay_shift_history_with_finalized_snapshots",
                side_effect=lambda _db, _employee, items: items,
            )
        )
    else:
        patches.append(
            patch(
                "app.services.payroll_snapshot.find_snapshot_run",
                return_value=None if snapshot is None else snapshot["run"],
            )
        )
        if snapshot is not None:
            patches.append(
                patch(
                    "app.services.payroll_snapshot.payslips_for_run",
                    return_value=[snapshot["payslip_row"]],
                )
            )
            patches.append(
                patch(
                    "app.services.payroll_snapshot.snapshot_payslip_dict",
                    return_value=snapshot["frozen"],
                )
            )
        if live_slip is not None:
            patches.append(
                patch(
                    "app.services.payroll_snapshot.load_period_payslip",
                    return_value=PayslipLoad(
                        slip=live_slip,
                        period_start=date(2026, 9, 1),
                        period_end=date(2026, 9, 30),
                        from_snapshot=False,
                        payroll_run=None,
                    ),
                )
            )
        else:
            live = MagicMock()
            patches.append(
                patch(
                    "app.services.payroll_snapshot.load_period_payslip",
                    live,
                )
            )

    for item in patches:
        item.start()
    try:
        items = _shift_history_rows(
            db,
            employee,
            today=WORK,
            business_timezone="Asia/Manila",
        )
    finally:
        for item in reversed(patches):
            item.stop()
    assert not db.add.called
    assert not db.commit.called
    return items, db


def test_same_day_ordinary_absence_stays_hidden_before_deadline():
    employee_id, business_id = _ids()
    shift, assignment = _employee_shift(
        time(17, 0), time(19, 0), "Evening",
        employee_id=employee_id, business_id=business_id,
    )
    # 7:05 PM is scheduled end + 5 minutes. The shared helper includes a shift
    # only once now is strictly past that instant.
    for minute in (4, 5):
        items, _db = _rows(
            now=datetime(2026, 9, 28, 19, minute),
            past=[],
            today_rows=[(assignment, shift, None)],
            employee_id=employee_id,
            business_id=business_id,
        )
        assert items == []


def test_same_day_ordinary_absence_appears_after_deadline():
    employee_id, business_id = _ids()
    shift, assignment = _employee_shift(
        time(17, 0), time(19, 0), "Evening",
        employee_id=employee_id, business_id=business_id,
    )
    items, _db = _rows(
        now=datetime(2026, 9, 28, 19, 6),
        past=[],
        today_rows=[(assignment, shift, None)],
        employee_id=employee_id,
        business_id=business_id,
    )
    assert len(items) == 1
    assert items[0]["assignment_id"] == str(assignment.id)
    assert items[0]["status"] == "absent"
    assert items[0]["attendance_record_id"] is None
    assert items[0]["time_in"] is None
    assert items[0]["shift_start"] == "5:00 PM"
    assert items[0]["shift_end"] == "7:00 PM"


def test_two_same_day_shifts_use_their_own_deadlines():
    employee_id, business_id = _ids()
    first, first_asg = _employee_shift(
        time(17, 0), time(19, 0), "Evening",
        employee_id=employee_id, business_id=business_id,
    )
    second, second_asg = _employee_shift(
        time(19, 30), time(21, 0), "Morning",
        employee_id=employee_id, business_id=business_id,
    )
    items, _db = _rows(
        now=datetime(2026, 9, 28, 19, 6),
        past=[],
        today_rows=[
            (first_asg, first, None),
            (second_asg, second, None),
        ],
        employee_id=employee_id,
        business_id=business_id,
    )
    assert [item["assignment_id"] for item in items] == [str(first_asg.id)]
    assert items[0]["status"] == "absent"


def test_same_day_worked_shift_is_unchanged():
    employee_id, business_id = _ids()
    shift, assignment = _employee_shift(
        time(17, 0), time(19, 0), "Evening",
        employee_id=employee_id, business_id=business_id,
    )
    record = _record(assignment, shift, AttendanceStatus.complete, punched=True)
    items, _db = _rows(
        now=datetime(2026, 9, 28, 19, 6),
        past=[(assignment, shift, record)],
        today_rows=[(assignment, shift, record)],
        employee_id=employee_id,
        business_id=business_id,
    )
    assert len(items) == 1
    assert items[0]["status"] == "complete"
    assert items[0]["attendance_record_id"] == str(record.id)
    assert items[0]["time_in"] is not None


def test_same_day_approved_leave_is_unchanged():
    employee_id, business_id = _ids()
    shift, assignment = _employee_shift(
        time(17, 0), time(19, 0), "Evening",
        employee_id=employee_id, business_id=business_id,
    )
    record = _record(assignment, shift, AttendanceStatus.on_leave, punched=False)
    recorded, _db = _rows(
        now=datetime(2026, 9, 28, 19, 6),
        past=[(assignment, shift, record)],
        today_rows=[(assignment, shift, record)],
        employee_id=employee_id,
        business_id=business_id,
    )
    assert len(recorded) == 1
    assert recorded[0]["status"] == "on_leave"
    assert recorded[0]["attendance_record_id"] == str(record.id)

    hidden, _db = _rows(
        now=datetime(2026, 9, 28, 19, 6),
        past=[],
        today_rows=[(assignment, shift, None)],
        employee_id=employee_id,
        business_id=business_id,
        on_approved_leave=True,
        on_payroll_leave=True,
    )
    assert hidden == []


def test_paid_holiday_absence_is_not_duplicated():
    employee_id, business_id = _ids()
    shift, assignment = _employee_shift(
        time(17, 0), time(19, 0), "Evening",
        employee_id=employee_id, business_id=business_id,
    )
    slip = {
        "employee_id": str(employee_id),
        "attendance_records": [
            {
                "shift_assignment_id": str(assignment.id),
                "status": "holiday_paid",
                "shift_net": 150.0,
                "holiday_pay": 150.0,
                "holiday_included_in_shift_net": True,
                "pay_basis_used": "hourly",
                "rate_used": 75.0,
                "worked_minutes": 0.0,
            }
        ],
    }
    items, _db = _rows(
        now=datetime(2026, 9, 28, 19, 6),
        past=[],
        today_rows=[(assignment, shift, None)],
        employee_id=employee_id,
        business_id=business_id,
        holidays={WORK: _paid_holiday()},
        live_slip=slip,
    )
    assert len(items) == 1
    assert items[0]["assignment_id"] == str(assignment.id)
    assert items[0]["status"] == "holiday_paid"
    assert items[0]["shift_net"] == 150.0
    assert items[0]["holiday_pay"] == 150.0
    assert items[0]["attendance_record_id"] is None


def test_next_day_ordinary_absence_stays_visible():
    employee_id, business_id = _ids()
    yesterday = WORK - timedelta(days=1)
    shift, assignment = _employee_shift(
        time(17, 0), time(19, 0), "Evening",
        employee_id=employee_id, business_id=business_id, work_date=yesterday,
    )
    items, _db = _rows(
        now=datetime(2026, 9, 28, 8, 0),
        past=[(assignment, shift, None)],
        today_rows=[],
        employee_id=employee_id,
        business_id=business_id,
    )
    assert len(items) == 1
    assert items[0]["assignment_id"] == str(assignment.id)
    assert items[0]["date"] == yesterday.isoformat()
    assert items[0]["status"] == "absent"


def test_finalized_snapshot_is_not_repriced():
    employee_id, business_id = _ids()
    yesterday = WORK - timedelta(days=1)
    shift, assignment = _employee_shift(
        time(9, 0), time(17, 0), "Day",
        employee_id=employee_id, business_id=business_id, work_date=yesterday,
    )
    frozen = {
        "employee_id": str(employee_id),
        "snapshot_version": PAYSLIP_SNAPSHOT_VERSION,
        "attendance_records": [
            {
                "shift_assignment_id": str(assignment.id),
                "status": "complete",
                "shift_net": 80.0,
                "time_in": "9:00 AM",
                "time_out": "5:00 PM",
            }
        ],
    }
    items, _db = _rows(
        now=datetime(2026, 9, 28, 12, 0),
        past=[(assignment, shift, None)],
        today_rows=[],
        employee_id=employee_id,
        business_id=business_id,
        snapshot={
            "run": SimpleNamespace(id=uuid4(), snapshot_version=PAYSLIP_SNAPSHOT_VERSION),
            "payslip_row": SimpleNamespace(employee_id=employee_id),
            "frozen": frozen,
        },
    )
    assert len(items) == 1
    assert items[0]["status"] == "complete"
    assert items[0]["shift_net"] == 80.0
    assert "holiday_pay" not in items[0]
