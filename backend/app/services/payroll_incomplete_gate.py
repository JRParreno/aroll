"""Block payroll finalization when incomplete attendance remains in the period."""

from __future__ import annotations

import uuid
from datetime import date, timedelta

from sqlalchemy import and_, or_
from sqlalchemy.orm import Session

from app.models.attendance import AttendanceRecord
from app.models.enums import AttendanceStatus
from app.models.scheduling import ShiftAssignment
from app.services.missing_clock_out import ensure_incomplete_for_business


def count_incomplete_attendance_in_period(
    db: Session,
    *,
    business_id: uuid.UUID,
    period_start: date,
    period_end: date,
    business_timezone: str | None = None,
) -> int:
    """Count incomplete attendance rows overlapping the pay period."""
    ensure_incomplete_for_business(
        db,
        business_id=business_id,
        business_timezone=business_timezone,
    )
    return (
        db.query(AttendanceRecord)
        .outerjoin(
            ShiftAssignment,
            AttendanceRecord.shift_assignment_id == ShiftAssignment.id,
        )
        .filter(
            AttendanceRecord.business_id == business_id,
            AttendanceRecord.status == AttendanceStatus.incomplete,
            or_(
                and_(
                    ShiftAssignment.id.is_not(None),
                    ShiftAssignment.work_date >= period_start,
                    ShiftAssignment.work_date <= period_end,
                ),
                and_(
                    AttendanceRecord.shift_assignment_id.is_(None),
                    AttendanceRecord.created_at >= period_start,
                    AttendanceRecord.created_at
                    < period_end + timedelta(days=1),
                ),
            ),
        )
        .count()
    )
