"""UTC storage vs business-timezone interpretation for attendance punches."""

from datetime import datetime, timezone
from zoneinfo import ZoneInfo

from app.core.timezone import to_business_naive


def test_incident_utc_instant_is_not_corrupted():
    """2026-09-17 04:58 UTC is 21:58 Pacific and 12:58 Manila.

    The stored timestamptz instant is correct. Attendance windows must use the
    business timezone, not the device wall clock.
    """
    instant = datetime(2026, 9, 17, 4, 58, 14, tzinfo=timezone.utc)
    pacific = instant.astimezone(ZoneInfo("America/Los_Angeles"))
    manila = instant.astimezone(ZoneInfo("Asia/Manila"))

    assert pacific.strftime("%Y-%m-%d %H:%M") == "2026-09-16 21:58"
    assert manila.strftime("%Y-%m-%d %H:%M") == "2026-09-17 12:58"
    assert instant.tzinfo is timezone.utc
    assert instant.hour == 4
    assert instant.minute == 58


def test_to_business_naive_uses_configured_timezone_not_device():
    instant = datetime(2026, 9, 17, 4, 58, 14, tzinfo=timezone.utc)
    manila = to_business_naive(instant, "Asia/Manila")
    pacific = to_business_naive(instant, "America/Los_Angeles")

    assert (manila.year, manila.month, manila.day, manila.hour, manila.minute) == (
        2026,
        9,
        17,
        12,
        58,
    )
    assert (
        pacific.year,
        pacific.month,
        pacific.day,
        pacific.hour,
        pacific.minute,
    ) == (
        2026,
        9,
        16,
        21,
        58,
    )
    assert manila.tzinfo is None
    assert pacific.tzinfo is None


def test_pacific_1214am_is_manila_afternoon_not_early_morning():
    """12:14 AM PDT is 3:14 PM Manila — not a 00:14 Time In."""
    utc = datetime(2026, 9, 17, 7, 14, tzinfo=timezone.utc)
    pacific = utc.astimezone(ZoneInfo("America/Los_Angeles"))
    manila = to_business_naive(utc, "Asia/Manila")
    assert (pacific.year, pacific.month, pacific.day, pacific.hour, pacific.minute) == (
        2026,
        9,
        17,
        0,
        14,
    )
    assert (manila.year, manila.month, manila.day, manila.hour, manila.minute) == (
        2026,
        9,
        17,
        15,
        14,
    )


def test_true_manila_0014_is_not_the_pacific_device_clock():
    utc = datetime(2026, 9, 16, 16, 14, tzinfo=timezone.utc)
    manila = to_business_naive(utc, "Asia/Manila")
    pacific = utc.astimezone(ZoneInfo("America/Los_Angeles"))
    assert (manila.year, manila.month, manila.day, manila.hour, manila.minute) == (
        2026,
        9,
        17,
        0,
        14,
    )
    assert (pacific.hour, pacific.minute) != (0, 14)


def test_true_manila_0041_is_not_pacific_device_0041():
    """00:41 Asia/Manila is still before 08:00; 00:41 Pacific is 15:41 Manila."""
    manila_utc = datetime(2026, 9, 16, 16, 41, tzinfo=timezone.utc)
    manila = to_business_naive(manila_utc, "Asia/Manila")
    assert (manila.year, manila.month, manila.day, manila.hour, manila.minute) == (
        2026,
        9,
        17,
        0,
        41,
    )

    pacific_utc = datetime(2026, 9, 17, 7, 41, tzinfo=timezone.utc)
    pacific = pacific_utc.astimezone(ZoneInfo("America/Los_Angeles"))
    manila_from_pacific = to_business_naive(pacific_utc, "Asia/Manila")
    assert (pacific.hour, pacific.minute) == (0, 41)
    assert (manila_from_pacific.hour, manila_from_pacific.minute) == (15, 41)
    assert manila != manila_from_pacific
