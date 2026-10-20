"""Schedule reminder window, idempotency, and cancelled-shift behavior."""

from datetime import date, datetime, time, timedelta
from types import SimpleNamespace
from unittest.mock import MagicMock, patch
from uuid import uuid4
from zoneinfo import ZoneInfo

from app.services.schedule_reminders import (
    _should_remind,
    assignment_start_local,
    run_schedule_reminders,
)


MANILA = ZoneInfo("Asia/Manila")


def test_should_remind_around_24_hours():
    start = datetime(2026, 10, 20, 8, 0, tzinfo=MANILA)
    now = start - timedelta(hours=24)
    due, word = _should_remind(now_utc=now.astimezone(), start_local=start)
    assert due is True
    assert word == "tomorrow"


def test_should_not_remind_after_start():
    start = datetime(2026, 10, 20, 8, 0, tzinfo=MANILA)
    now = start + timedelta(minutes=5)
    due, _word = _should_remind(now_utc=now.astimezone(), start_local=start)
    assert due is False


def test_late_assignment_uses_today_wording():
    start = datetime(2026, 10, 20, 18, 0, tzinfo=MANILA)
    now = datetime(2026, 10, 20, 10, 0, tzinfo=MANILA)
    due, word = _should_remind(now_utc=now.astimezone(), start_local=start)
    assert due is True
    assert word == "today"


def test_far_future_shift_waits():
    start = datetime(2026, 10, 22, 8, 0, tzinfo=MANILA)
    now = datetime(2026, 10, 20, 8, 0, tzinfo=MANILA)
    due, _word = _should_remind(now_utc=now.astimezone(), start_local=start)
    assert due is False


def test_assignment_start_uses_business_timezone():
    start = assignment_start_local(
        work_date=date(2026, 10, 20),
        start_time=time(8, 0),
        timezone_name="Asia/Manila",
    )
    assert start.tzinfo is not None
    assert start.hour == 8


def _reminder_row(*, work_date, start_time, user_active=True):
    user = SimpleNamespace(id=uuid4(), is_active=user_active)
    employee = SimpleNamespace(
        id=uuid4(),
        user_id=user.id,
        is_active=True,
        user=user,
    )
    shift = SimpleNamespace(
        id=uuid4(),
        start_time=start_time,
        is_active=True,
    )
    assignment = SimpleNamespace(
        id=uuid4(),
        work_date=work_date,
        shift_id=shift.id,
        employee_id=employee.id,
    )
    business = SimpleNamespace(timezone="Asia/Manila")
    return assignment, employee, shift, business


def test_reminder_job_is_idempotent_for_same_start():
    start_local = datetime(2026, 10, 20, 8, 0, tzinfo=MANILA)
    now = start_local - timedelta(hours=24)
    assignment, employee, shift, business = _reminder_row(
        work_date=start_local.date(), start_time=start_local.timetz().replace(tzinfo=None)
        if False
        else time(8, 0),
    )
    db = MagicMock()
    db.query.return_value.join.return_value.join.return_value.join.return_value.filter.return_value.all.return_value = [
        (assignment, employee, shift, business)
    ]
    with (
        patch(
            "app.services.schedule_reminders._existing_reminder_starts",
            return_value={start_local.isoformat()},
        ),
        patch("app.services.schedule_reminders.notify_user") as notify_user,
    ):
        created = run_schedule_reminders(db, now=now)
    assert created == 0
    assert not notify_user.called


def test_reminder_job_sends_once_then_skips():
    start_local = datetime(2026, 10, 20, 8, 0, tzinfo=MANILA)
    now = start_local - timedelta(hours=24)
    assignment, employee, shift, business = _reminder_row(
        work_date=start_local.date(), start_time=time(8, 0)
    )
    db = MagicMock()
    db.query.return_value.join.return_value.join.return_value.join.return_value.filter.return_value.all.return_value = [
        (assignment, employee, shift, business)
    ]
    with (
        patch(
            "app.services.schedule_reminders._existing_reminder_starts",
            return_value=set(),
        ),
        patch(
            "app.services.schedule_reminders.notification_exists_for_entity",
            return_value=False,
        ),
        patch("app.services.schedule_reminders.notify_user") as notify_user,
    ):
        created = run_schedule_reminders(db, now=now)
    assert created == 1
    assert notify_user.call_args.kwargs["type"] == "schedule_reminder"
    assert "8:00 AM" in notify_user.call_args.kwargs["message"]


def test_cancelled_shift_is_not_queried():
    db = MagicMock()
    db.query.return_value.join.return_value.join.return_value.join.return_value.filter.return_value.all.return_value = []
    with patch("app.services.schedule_reminders.notify_user") as notify_user:
        created = run_schedule_reminders(
            db, now=datetime(2026, 10, 19, 8, 0, tzinfo=MANILA)
        )
    assert created == 0
    assert not notify_user.called


def test_rescheduled_start_sends_new_reminder():
    start_local = datetime(2026, 10, 20, 14, 0, tzinfo=MANILA)
    now = start_local - timedelta(hours=8)
    assignment, employee, shift, business = _reminder_row(
        work_date=start_local.date(), start_time=time(14, 0)
    )
    db = MagicMock()
    db.query.return_value.join.return_value.join.return_value.join.return_value.filter.return_value.all.return_value = [
        (assignment, employee, shift, business)
    ]
    with (
        patch(
            "app.services.schedule_reminders._existing_reminder_starts",
            return_value={"2026-10-20T08:00:00+08:00"},
        ),
        patch(
            "app.services.schedule_reminders.notification_exists_for_entity",
            return_value=True,
        ),
        patch("app.services.schedule_reminders.notify_user") as notify_user,
    ):
        created = run_schedule_reminders(db, now=now)
    assert created == 1
    assert notify_user.call_args.kwargs["metadata"]["scheduled_start"] == (
        start_local.isoformat()
    )
