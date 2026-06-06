from datetime import datetime, timedelta, timezone
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError

MANILA_TZ_NAME = "Asia/Manila"


def get_manila_tz() -> timezone | ZoneInfo:
    try:
        return ZoneInfo(MANILA_TZ_NAME)
    except ZoneInfoNotFoundError:
        # Windows may lack IANA tzdata unless the tzdata package is installed.
        return timezone(timedelta(hours=8), name=MANILA_TZ_NAME)


def manila_now() -> datetime:
    return datetime.now(get_manila_tz())
