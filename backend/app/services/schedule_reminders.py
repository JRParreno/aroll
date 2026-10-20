"""Upcoming-shift reminders, approximately 24 hours before start.

Safe to rerun: one reminder per employee + assignment + scheduled start.
Does not send for deleted assignments or shifts whose start has passed.
"""

from __future__ import annotations

import json
import logging
from datetime import datetime, timedelta, timezone
from zoneinfo import ZoneInfo

from sqlalchemy.orm import Session

from app.models.business import Business
from app.models.employee import Employee
from app.models.notification import Notification
from app.models.scheduling import Shift, ShiftAssignment
from app.services.activity_notifications import (
    format_clock,
    format_work_date,
)
from app.services.notifications import notification_exists_for_entity, notify_user

logger = logging.getLogger("aroll.reminders")

REMINDER_TYPE = "schedule_reminder"
LOOKAHEAD_MIN_HOURS = 23
LOOKAHEAD_MAX_HOURS = 25


def assignment_start_local(
    *,
    work_date,
    start_time,
    timezone_name: str,
) -> datetime:
    tz = ZoneInfo(timezone_name or "Asia/Manila")
    return datetime.combine(work_date, start_time, tzinfo=tz)


def _existing_reminder_starts(
    db: Session, *, user_id, assignment_id
) -> set[str]:
    rows = (
        db.query(Notification)
        .filter(
            Notification.type == REMINDER_TYPE,
            Notification.entity_type == "shift_assignment",
            Notification.entity_id == assignment_id,
            Notification.recipient_user_id == user_id,
        )
        .all()
    )
    starts: set[str] = set()
    for row in rows:
        if not row.metadata_json:
            starts.add("")
            continue
        try:
            meta = json.loads(row.metadata_json)
        except json.JSONDecodeError:
            starts.add("")
            continue
        starts.add(str(meta.get("scheduled_start") or ""))
    return starts


def _should_remind(*, now_utc: datetime, start_local: datetime) -> tuple[bool, str]:
    start_utc = start_local.astimezone(timezone.utc)
    if start_utc <= now_utc:
        return False, ""
    delta = start_utc - now_utc
    hours = delta.total_seconds() / 3600.0
    if LOOKAHEAD_MIN_HOURS <= hours <= LOOKAHEAD_MAX_HOURS:
        return True, "tomorrow"
    if hours < LOOKAHEAD_MIN_HOURS:
        # Assigned or rescheduled inside the 24-hour window.
        local_now = now_utc.astimezone(start_local.tzinfo)
        word = "tomorrow" if start_local.date() > local_now.date() else "today"
        return True, word
    return False, ""


def run_schedule_reminders(
    db: Session, *, now: datetime | None = None
) -> int:
    """Create due upcoming-shift reminders. Returns rows created."""
    now_utc = now.astimezone(timezone.utc) if now and now.tzinfo else (
        now.replace(tzinfo=timezone.utc) if now else datetime.now(timezone.utc)
    )
    rows = (
        db.query(ShiftAssignment, Employee, Shift, Business)
        .join(Employee, ShiftAssignment.employee_id == Employee.id)
        .join(Shift, ShiftAssignment.shift_id == Shift.id)
        .join(Business, Employee.business_id == Business.id)
        .filter(
            Employee.is_active.is_(True),
            Employee.user_id.is_not(None),
            Shift.is_active.is_(True),
            ShiftAssignment.work_date >= (now_utc.date() - timedelta(days=1)),
            ShiftAssignment.work_date <= (now_utc.date() + timedelta(days=3)),
        )
        .all()
    )
    created = 0
    for assignment, employee, shift, business in rows:
        user = employee.user
        if user is None or not user.is_active:
            continue
        start_local = assignment_start_local(
            work_date=assignment.work_date,
            start_time=shift.start_time,
            timezone_name=business.timezone or "Asia/Manila",
        )
        due, when_word = _should_remind(now_utc=now_utc, start_local=start_local)
        if not due:
            continue
        scheduled_start = start_local.isoformat()
        existing = _existing_reminder_starts(
            db, user_id=user.id, assignment_id=assignment.id
        )
        if scheduled_start in existing:
            continue
        if notification_exists_for_entity(
            db,
            type=REMINDER_TYPE,
            entity_type="shift_assignment",
            entity_id=assignment.id,
            recipient_user_id=user.id,
        ) and scheduled_start in existing:
            continue
        notify_user(
            db,
            user=user,
            type=REMINDER_TYPE,
            title="Upcoming Shift Reminder",
            message=(
                f"Reminder: You are scheduled to work {when_word} at "
                f"{format_clock(shift.start_time)} "
                f"({format_work_date(assignment.work_date)})."
            ),
            entity_type="shift_assignment",
            entity_id=assignment.id,
            deep_link="/schedule",
            metadata={
                "scheduled_start": scheduled_start,
                "work_date": assignment.work_date.isoformat(),
            },
        )
        created += 1
    return created


def reminder_tick() -> int:
    from app.db.session import SessionLocal

    db = SessionLocal()
    try:
        return run_schedule_reminders(db)
    except Exception:
        logger.exception("schedule reminder tick failed")
        return 0
    finally:
        db.close()
