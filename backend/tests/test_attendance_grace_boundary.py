"""Grace-end minute is inclusive for attendance status and late pay."""

from datetime import date, datetime, time, timezone
from uuid import uuid4
from zoneinfo import ZoneInfo

from app.models.enums import AttendanceStatus
from app.models.scheduling import Shift, ShiftAssignment
from app.services.attendance_clock import _clock_in_status
from app.services.attendance_status import resolve_closed_attendance_status
from app.services.payroll_engine import monetary_late_minutes
from tests.test_attendance_status_percent import _policy


START = datetime(2026, 10, 21, 8, 0)
TZ = ZoneInfo("Asia/Manila")


def _status(arrived: datetime, grace_minutes: int) -> AttendanceStatus:
    return _clock_in_status(
        now_local=arrived,
        scheduled_start=START,
        grace_minutes=grace_minutes,
    )


def test_grace_ten_minutes_keeps_eight_ten_on_time():
    assert _status(datetime(2026, 10, 21, 8, 0), 10) == AttendanceStatus.in_progress
    assert _status(datetime(2026, 10, 21, 8, 9), 10) == AttendanceStatus.in_progress
    assert _status(datetime(2026, 10, 21, 8, 10), 10) == AttendanceStatus.in_progress
    # Seconds inside the grace minute still display as 8:10 and stay on time.
    assert (
        _status(datetime(2026, 10, 21, 8, 10, 6, 832568), 10)
        == AttendanceStatus.in_progress
    )
    assert _status(datetime(2026, 10, 21, 8, 11), 10) == AttendanceStatus.late


def test_grace_period_is_not_hardcoded_to_ten_minutes():
    assert _status(datetime(2026, 10, 21, 8, 5, 59), 5) == AttendanceStatus.in_progress
    assert _status(datetime(2026, 10, 21, 8, 6), 5) == AttendanceStatus.late
    assert _status(datetime(2026, 10, 21, 8, 15, 40), 15) == AttendanceStatus.in_progress
    assert _status(datetime(2026, 10, 21, 8, 16), 15) == AttendanceStatus.late


def test_grace_minute_has_zero_chargeable_late_minutes():
    assert (
        monetary_late_minutes(
            time_in=datetime(2026, 10, 21, 8, 0),
            scheduled_start=START,
            grace_minutes=10,
        )
        == 0
    )
    assert (
        monetary_late_minutes(
            time_in=datetime(2026, 10, 21, 8, 9, 59),
            scheduled_start=START,
            grace_minutes=10,
        )
        == 0
    )
    assert (
        monetary_late_minutes(
            time_in=datetime(2026, 10, 21, 8, 10, 6),
            scheduled_start=START,
            grace_minutes=10,
        )
        == 0
    )
    assert (
        monetary_late_minutes(
            time_in=datetime(2026, 10, 21, 8, 11),
            scheduled_start=START,
            grace_minutes=10,
        )
        == 1
    )
    # After the grace minute, the existing second-based remainder still applies.
    assert (
        monetary_late_minutes(
            time_in=datetime(2026, 10, 21, 8, 11, 30),
            scheduled_start=START,
            grace_minutes=10,
        )
        == 1.5
    )


def test_chargeable_late_minutes_follow_a_different_grace():
    assert (
        monetary_late_minutes(
            time_in=datetime(2026, 10, 21, 8, 5, 59),
            scheduled_start=START,
            grace_minutes=5,
        )
        == 0
    )
    assert (
        monetary_late_minutes(
            time_in=datetime(2026, 10, 21, 8, 6),
            scheduled_start=START,
            grace_minutes=5,
        )
        == 1
    )


def test_closed_shift_at_grace_end_is_complete_not_late():
    employee_id = uuid4()
    business_id = uuid4()
    shift_id = uuid4()
    assignment = ShiftAssignment(
        id=uuid4(),
        shift_id=shift_id,
        employee_id=employee_id,
        work_date=date(2026, 10, 21),
        is_rest_day_work=False,
    )
    shift = Shift(
        id=shift_id,
        business_id=business_id,
        name="Morning",
        start_time=time(8, 0),
        end_time=time(12, 0),
    )
    time_in = datetime(2026, 10, 21, 8, 10, 6, tzinfo=TZ).astimezone(timezone.utc)
    time_out = datetime(2026, 10, 21, 12, 4, tzinfo=TZ).astimezone(timezone.utc)

    status = resolve_closed_attendance_status(
        time_in=time_in,
        time_out=time_out,
        assignment=assignment,
        shift=shift,
        policy=_policy(business_id=business_id, on_time_grace_minutes=10),
        business_timezone="Asia/Manila",
    )
    assert status == AttendanceStatus.complete

    one_minute_late = datetime(2026, 10, 21, 8, 11, tzinfo=TZ).astimezone(timezone.utc)
    late_status = resolve_closed_attendance_status(
        time_in=one_minute_late,
        time_out=time_out,
        assignment=assignment,
        shift=shift,
        policy=_policy(business_id=business_id, on_time_grace_minutes=10),
        business_timezone="Asia/Manila",
    )
    assert late_status == AttendanceStatus.late
