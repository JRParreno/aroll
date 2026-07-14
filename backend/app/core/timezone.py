from datetime import date, datetime, timedelta, timezone
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError

MANILA_TZ_NAME = "Asia/Manila"


def get_manila_tz() -> timezone | ZoneInfo:
    try:
        return ZoneInfo(MANILA_TZ_NAME)
    except ZoneInfoNotFoundError:
        # Windows may lack IANA tzdata unless the tzdata package is installed.
        return timezone(timedelta(hours=8), name=MANILA_TZ_NAME)


def get_business_tz(tz_name: str | None) -> timezone | ZoneInfo:
    """Resolve a business IANA timezone, defaulting to Asia/Manila."""
    name = (tz_name or MANILA_TZ_NAME).strip() or MANILA_TZ_NAME
    try:
        return ZoneInfo(name)
    except ZoneInfoNotFoundError:
        if name == MANILA_TZ_NAME:
            return get_manila_tz()
        return get_manila_tz()


def business_now(tz_name: str | None) -> datetime:
    return datetime.now(get_business_tz(tz_name))


def business_today(tz_name: str | None) -> date:
    return business_now(tz_name).date()


def manila_now() -> datetime:
    return datetime.now(get_manila_tz())
