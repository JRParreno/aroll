"""Incomplete cutoff uses maximum_overtime_minutes, not late grace."""

from datetime import date, datetime, time, timezone
from types import SimpleNamespace
from unittest.mock import MagicMock, patch
from uuid import uuid4

import pytest
from fastapi import HTTPException

from app.models.attendance import AttendanceRecord
from app.models.enums import AttendanceStatus
from app.models.scheduling import Shift, ShiftAssignment
from app.services.missing_clock_out import (
    is_past_clock_out_deadline,
    mark_record_incomplete_if_needed,
    raise_if_incomplete_clock_out,
)


class _FakeShift:
    def __init__(self, start: time, end: time):
        self.start_time = start
        self.end_time = end


def test_deadline_helper_respects_provided_window():
    """Generic helper: callers pass either grace or max OT minutes."""
    shift = _FakeShift(time(8, 0), time(17, 0))
    work_date = date(2026, 8, 4)
    # Past late grace (10) but inside max OT (180).
    assert is_past_clock_out_deadline(
        now_local=datetime(2026, 8, 4, 17, 11),
        work_date=work_date,
        shift=shift,  # type: ignore[arg-type]
        grace_minutes=10,
    )
    assert not is_past_clock_out_deadline(
        now_local=datetime(2026, 8, 4, 17, 11),
        work_date=work_date,
        shift=shift,  # type: ignore[arg-type]
        grace_minutes=180,
    )
    # Past max OT window (17:00 + 180 = 20:00).
    assert is_past_clock_out_deadline(
        now_local=datetime(2026, 8, 4, 20, 1),
        work_date=work_date,
        shift=shift,  # type: ignore[arg-type]
        grace_minutes=180,
    )


def _open_record_bundle(*, status=AttendanceStatus.in_progress):
    business_id = uuid4()
    employee_id = uuid4()
    work_date = date(2026, 8, 4)
    shift = Shift(
        id=uuid4(),
        business_id=business_id,
        name="Day",
        start_time=time(8, 0),
        end_time=time(17, 0),
    )
    assignment = ShiftAssignment(
        id=uuid4(),
        shift_id=shift.id,
        employee_id=employee_id,
        work_date=work_date,
    )
    record = AttendanceRecord(
        id=uuid4(),
        business_id=business_id,
        employee_id=employee_id,
        shift_assignment_id=assignment.id,
        time_in=datetime(2026, 8, 4, 0, 20, tzinfo=timezone.utc),  # 08:20 PH
        time_out=None,
        status=status,
    )
    policy = SimpleNamespace(
        business_id=business_id,
        on_time_grace_minutes=10,
        maximum_overtime_minutes=180,
    )
    return record, assignment, shift, policy


def test_incomplete_not_triggered_inside_max_ot_window():
    """Scenario 2-ish: after shift end but before 20:00 — still not incomplete."""
    record, assignment, shift, policy = _open_record_bundle(
        status=AttendanceStatus.late
    )
    db = MagicMock()
    db.query.return_value.join.return_value.filter.return_value.first.return_value = (
        assignment,
        shift,
    )

    with patch(
        "app.services.missing_clock_out.business_now",
        return_value=datetime(2026, 8, 4, 18, 0),  # 6 PM local
    ):
        changed = mark_record_incomplete_if_needed(
            db,
            record,
            business_timezone="Asia/Manila",
            policy=policy,  # type: ignore[arg-type]
        )

    assert changed is False
    assert record.status == AttendanceStatus.late


def test_incomplete_triggered_after_maximum_overtime_window():
    """Scenario 3: after 8 PM with max OT 180 → incomplete."""
    record, assignment, shift, policy = _open_record_bundle(
        status=AttendanceStatus.in_progress
    )
    db = MagicMock()
    db.query.return_value.join.return_value.filter.return_value.first.return_value = (
        assignment,
        shift,
    )

    with patch(
        "app.services.missing_clock_out.business_now",
        return_value=datetime(2026, 8, 4, 20, 1),
    ):
        changed = mark_record_incomplete_if_needed(
            db,
            record,
            business_timezone="Asia/Manila",
            policy=policy,  # type: ignore[arg-type]
        )

    assert changed is True
    assert record.status == AttendanceStatus.incomplete


def test_late_grace_alone_does_not_mark_incomplete():
    """17:11 is past grace(10) but inside max OT(180) — stay Late/in_progress."""
    record, assignment, shift, policy = _open_record_bundle(
        status=AttendanceStatus.late
    )
    db = MagicMock()
    db.query.return_value.join.return_value.filter.return_value.first.return_value = (
        assignment,
        shift,
    )

    with patch(
        "app.services.missing_clock_out.business_now",
        return_value=datetime(2026, 8, 4, 17, 11),
    ):
        changed = mark_record_incomplete_if_needed(
            db,
            record,
            business_timezone="Asia/Manila",
            policy=policy,  # type: ignore[arg-type]
        )

    assert changed is False
    assert record.status == AttendanceStatus.late


def test_raise_if_incomplete_allows_clock_out_inside_ot_window():
    record, assignment, shift, policy = _open_record_bundle(
        status=AttendanceStatus.late
    )
    db = MagicMock()
    db.get.return_value = policy
    db.query.return_value.join.return_value.filter.return_value.first.return_value = (
        assignment,
        shift,
    )

    with patch(
        "app.services.missing_clock_out.business_now",
        return_value=datetime(2026, 8, 4, 18, 30),
    ):
        raise_if_incomplete_clock_out(
            db, record, business_timezone="Asia/Manila"
        )

    assert record.status == AttendanceStatus.late


def test_raise_if_incomplete_blocks_after_max_ot_window():
    record, assignment, shift, policy = _open_record_bundle()
    db = MagicMock()
    db.get.return_value = policy
    db.query.return_value.join.return_value.filter.return_value.first.return_value = (
        assignment,
        shift,
    )

    with (
        patch(
            "app.services.missing_clock_out.business_now",
            return_value=datetime(2026, 8, 4, 20, 5),
        ),
        patch(
            "app.services.incomplete_attendance_notify.notify_incomplete_attendance"
        ),
        pytest.raises(HTTPException) as exc,
    ):
        raise_if_incomplete_clock_out(
            db, record, business_timezone="Asia/Manila"
        )

    assert exc.value.status_code == 400
    assert exc.value.detail["code"] == "incomplete_attendance"
    assert record.status == AttendanceStatus.incomplete


def test_no_clock_in_never_marked_incomplete_by_helper():
    """Scenario 4: incomplete path requires time_in; no-show uses other rules."""
    record, assignment, shift, policy = _open_record_bundle()
    record.time_in = None
    record.status = AttendanceStatus.in_progress
    db = MagicMock()

    changed = mark_record_incomplete_if_needed(
        db,
        record,
        business_timezone="Asia/Manila",
        policy=policy,  # type: ignore[arg-type]
    )
    assert changed is False
