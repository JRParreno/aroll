"""Workplace Wi-Fi fallback for a small worksite.

A GPS fix inside the geofence does not need Wi-Fi. Wi-Fi can authorize
attendance only when the client submits no coordinates, the radius is
strictly under 20 m, and the BSSID matches an enabled access point for that
worksite. Exactly 20 m stays on the GPS geofence. Coordinates that fall
outside the geofence are rejected by the caller before this match is allowed
to matter.
"""

from __future__ import annotations

import logging
import uuid

from fastapi import HTTPException
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from app.models.business import BusinessLocation
from app.models.enums import UserRole
from app.models.user import User
from app.models.workplace_wifi import WorkplaceWifiAccessPoint
from app.services.demo_tenant import business_is_demo

logger = logging.getLogger("aroll.attendance")

SMALL_RADIUS_M = 20
# Android reports an unknown connected-network RSSI as this value.
INVALID_RSSI_DBM = -127
MIN_CONFIGURABLE_RSSI_DBM = -120
MAX_CONFIGURABLE_RSSI_DBM = -20
SUGGESTED_MINIMUM_RSSI_DBM = -50


def wifi_fallback_radius_allows(radius_m: float | int) -> bool:
    """Wi-Fi fallback is allowed only when the configured radius is under 20 m.

    Exactly 20 m stays on the GPS geofence. ``SMALL_RADIUS_M`` remains the
    small-fence marker used elsewhere; this comparison is stricter.
    """
    return float(radius_m) < SMALL_RADIUS_M
WIFI_NOT_CONFIGURED = "not_configured"
WIFI_MATCHED = "matched"
WIFI_UNAVAILABLE = "unavailable"

_UNKNOWN_BSSIDS = {
    "00:00:00:00:00:00",
    "02:00:00:00:00:00",
}


class WorkplaceWifiMismatchError(HTTPException):
    def __init__(self) -> None:
        super().__init__(
            status_code=409,
            detail={
                "code": "workplace_wifi_mismatch",
                "message": (
                    "Connect to the workplace Wi-Fi registered by your employer, "
                    "then try again."
                ),
            },
        )


class WorkplaceWifiFallbackRejected(HTTPException):
    def __init__(self, code: str, message: str) -> None:
        super().__init__(
            status_code=403,
            detail={"code": code, "message": message},
        )


def normalize_bssid(value: str | None) -> str | None:
    """Return a colon-separated lowercase MAC, or None when it is not usable."""
    if value is None:
        return None
    text = value.strip().lower().replace("-", ":")
    if not text or "unknown" in text or text.startswith("<"):
        return None
    parts = text.split(":")
    if len(parts) != 6:
        return None
    octets: list[int] = []
    for part in parts:
        if len(part) > 2:
            return None
        try:
            octets.append(int(part, 16))
        except ValueError:
            return None
    if any(octet < 0 or octet > 255 for octet in octets):
        return None
    normalized = ":".join(f"{octet:02x}" for octet in octets)
    if normalized in _UNKNOWN_BSSIDS:
        return None
    return normalized


def clean_ssid(value: str | None) -> str | None:
    if value is None:
        return None
    text = value.strip()
    if len(text) >= 2 and text.startswith('"') and text.endswith('"'):
        text = text[1:-1].strip()
    if not text or text.lower() in {"<unknown ssid>", "unknown ssid"}:
        return None
    return text[:64]


def decide_workplace_wifi(
    *,
    radius_m: float | int,
    is_demo: bool,
    enabled_bssids: dict[str, uuid.UUID],
    observed_bssid: str | None,
) -> tuple[str | None, uuid.UUID | None]:
    """Return (outcome, matched access-point id).

    ``None`` means Wi-Fi evidence is ignored and must not be stored.
    A usable BSSID that is not on this worksite's enabled list raises
    ``WorkplaceWifiMismatchError`` and must not create a punch.
    """
    if is_demo or not wifi_fallback_radius_allows(radius_m):
        return None, None
    if not enabled_bssids:
        return WIFI_NOT_CONFIGURED, None
    normalized = normalize_bssid(observed_bssid)
    if normalized is None:
        return WIFI_UNAVAILABLE, None
    matched_id = enabled_bssids.get(normalized)
    if matched_id is None:
        raise WorkplaceWifiMismatchError()
    return WIFI_MATCHED, matched_id


def enabled_bssid_map(
    db: Session, location_id: uuid.UUID
) -> dict[str, uuid.UUID]:
    rows = (
        db.query(WorkplaceWifiAccessPoint)
        .filter(
            WorkplaceWifiAccessPoint.location_id == location_id,
            WorkplaceWifiAccessPoint.enabled.is_(True),
        )
        .all()
    )
    found: dict[str, uuid.UUID] = {}
    for row in rows:
        normalized = normalize_bssid(row.bssid)
        if normalized is not None:
            found[normalized] = row.id
    return found


def observed_rssi_is_usable(observed_rssi_dbm: int | None) -> bool:
    """A live reading in dBm. Unknown and non-negative values are not usable."""
    if observed_rssi_dbm is None:
        return False
    if observed_rssi_dbm <= INVALID_RSSI_DBM or observed_rssi_dbm >= 0:
        return False
    return True


def require_configured_rssi(
    minimum_rssi_dbm: int | None,
    observed_rssi_dbm: int | None,
) -> None:
    """Apply an owner threshold. A null threshold leaves BSSID-only fallback."""
    if minimum_rssi_dbm is None:
        return
    if not observed_rssi_is_usable(observed_rssi_dbm) or observed_rssi_dbm is None:
        raise WorkplaceWifiFallbackRejected(
            "workplace_wifi_rssi_unavailable",
            "The phone could not read the workplace Wi-Fi signal strength. "
            "Move closer to the access point and try again.",
        )
    if observed_rssi_dbm < int(minimum_rssi_dbm):
        raise WorkplaceWifiFallbackRejected(
            "workplace_wifi_rssi_weak",
            "The workplace Wi-Fi signal is too weak. "
            "Move closer to the access point and try again.",
        )


def assert_wifi_fallback(
    db: Session,
    location: BusinessLocation,
    observed_bssid: str | None,
    observed_rssi_dbm: int | None = None,
) -> tuple[str, uuid.UUID]:
    """Require a matching enabled BSSID. A caller-supplied mode flag is not enough.

    Returns ``(matched, access_point_id)``. Raises when the radius is 20 m
    or more, no enabled access point exists, the BSSID cannot be read, it
    belongs to a different network, or a configured RSSI floor is not met.
    Does not create a punch. A null floor does not check RSSI.
    """
    if not wifi_fallback_radius_allows(location.geofence_radius_m):
        raise WorkplaceWifiFallbackRejected(
            "wifi_fallback_unavailable",
            "This workplace checks the map boundary. "
            "Turn on location and try again from the work area.",
        )
    allow_list = enabled_bssid_map(db, location.id)
    if not allow_list:
        raise WorkplaceWifiFallbackRejected(
            "workplace_wifi_not_configured",
            "Workplace Wi-Fi is not set up for this worksite. "
            "Turn on location and try again from the work area.",
        )
    normalized = normalize_bssid(observed_bssid)
    if normalized is None:
        raise WorkplaceWifiFallbackRejected(
            "workplace_wifi_unavailable",
            "Join the workplace Wi-Fi registered by your employer, then try again.",
        )
    matched_id = allow_list.get(normalized)
    if matched_id is None:
        logger.info(
            "WIFI_VERIFICATION result=not_matched employee_business_id=%s location_id=%s",
            location.business_id,
            location.id,
        )
        raise WorkplaceWifiMismatchError()
    require_configured_rssi(location.minimum_rssi_dbm, observed_rssi_dbm)
    return WIFI_MATCHED, matched_id


def resolve_workplace_wifi(
    db: Session,
    *,
    business,
    location: BusinessLocation,
    observed_bssid: str | None,
) -> tuple[str | None, uuid.UUID | None]:
    radius = location.geofence_radius_m
    if business_is_demo(business) or not wifi_fallback_radius_allows(radius):
        return None, None
    allow_list = enabled_bssid_map(db, location.id)
    try:
        return decide_workplace_wifi(
            radius_m=radius,
            is_demo=False,
            enabled_bssids=allow_list,
            observed_bssid=observed_bssid,
        )
    except WorkplaceWifiMismatchError:
        logger.info(
            "WIFI_VERIFICATION result=not_matched employee_business_id=%s location_id=%s",
            location.business_id,
            location.id,
        )
        raise


def wifi_verification_enabled(db: Session, location: BusinessLocation, *, is_demo: bool) -> bool:
    if is_demo or not wifi_fallback_radius_allows(location.geofence_radius_m):
        return False
    return bool(enabled_bssid_map(db, location.id))


def require_owner_business(user: User) -> uuid.UUID:
    if user.role != UserRole.owner or user.business_id is None:
        raise HTTPException(
            status_code=403,
            detail="Only the business owner can manage workplace Wi-Fi.",
        )
    return user.business_id


def primary_location_for_business(db: Session, business_id: uuid.UUID) -> BusinessLocation:
    location = (
        db.query(BusinessLocation)
        .filter(
            BusinessLocation.business_id == business_id,
            BusinessLocation.is_primary.is_(True),
        )
        .first()
    )
    if location is None:
        raise HTTPException(
            status_code=400,
            detail="Save the workplace location before registering Wi-Fi.",
        )
    return location


def owned_access_point(
    db: Session, *, business_id: uuid.UUID, access_point_id: uuid.UUID
) -> WorkplaceWifiAccessPoint:
    row = db.get(WorkplaceWifiAccessPoint, access_point_id)
    if row is None or row.business_id != business_id:
        raise HTTPException(status_code=404, detail="Workplace Wi-Fi entry was not found.")
    return row


def register_access_point(
    db: Session,
    *,
    business_id: uuid.UUID,
    label: str,
    bssid: str,
    ssid: str | None,
) -> WorkplaceWifiAccessPoint:
    location = primary_location_for_business(db, business_id)
    normalized = normalize_bssid(bssid)
    if normalized is None:
        raise HTTPException(
            status_code=400,
            detail=(
                "The connected Wi-Fi address could not be read. "
                "Join the workplace network on this phone and try again."
            ),
        )
    display_label = label.strip()
    if not display_label:
        raise HTTPException(status_code=400, detail="Enter a name for this access point.")
    existing = (
        db.query(WorkplaceWifiAccessPoint)
        .filter(
            WorkplaceWifiAccessPoint.location_id == location.id,
            WorkplaceWifiAccessPoint.bssid == normalized,
        )
        .first()
    )
    if existing is not None:
        raise HTTPException(
            status_code=409,
            detail={
                "code": "wifi_access_point_exists",
                "message": "That access point is already registered for this workplace.",
            },
        )
    row = WorkplaceWifiAccessPoint(
        business_id=business_id,
        location_id=location.id,
        label=display_label[:80],
        ssid=clean_ssid(ssid),
        bssid=normalized,
        enabled=True,
    )
    db.add(row)
    try:
        db.commit()
    except IntegrityError:
        db.rollback()
        raise HTTPException(
            status_code=409,
            detail={
                "code": "wifi_access_point_exists",
                "message": "That access point is already registered for this workplace.",
            },
        ) from None
    db.refresh(row)
    logger.info(
        "WIFI_ACCESS_POINT action=register business_id=%s location_id=%s access_point_id=%s",
        business_id,
        location.id,
        row.id,
    )
    return row


def list_access_points(db: Session, business_id: uuid.UUID) -> list[WorkplaceWifiAccessPoint]:
    location = (
        db.query(BusinessLocation)
        .filter(
            BusinessLocation.business_id == business_id,
            BusinessLocation.is_primary.is_(True),
        )
        .first()
    )
    if location is None:
        return []
    return (
        db.query(WorkplaceWifiAccessPoint)
        .filter(WorkplaceWifiAccessPoint.location_id == location.id)
        .order_by(WorkplaceWifiAccessPoint.created_at.asc())
        .all()
    )
