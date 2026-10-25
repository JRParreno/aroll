"""Temporary development log for geofence rejections.

Enabled only when GEOFENCE_DIAGNOSTICS is true. The line records why a
location was rejected. It does not accept, reject, or store attendance.
"""

from __future__ import annotations

import logging

from fastapi import HTTPException

from app.core.config import settings
from app.core.geofence import haversine_distance_m
from app.models.business import BusinessLocation

logger = logging.getLogger("aroll.geofence")

_DIAGNOSTIC_CODES = frozenset(
    {
        "outside_geofence",
        "location_required",
        "invalid_location",
        "wifi_fallback_unavailable",
        "workplace_wifi_not_configured",
        "workplace_wifi_unavailable",
        "workplace_wifi_mismatch",
        "workplace_wifi_rssi_unavailable",
        "workplace_wifi_rssi_weak",
    }
)


def _detail(exc: HTTPException) -> dict:
    detail = exc.detail
    return detail if isinstance(detail, dict) else {}


def log_clock_location_failure(
    exc: HTTPException,
    *,
    action: str,
    location: BusinessLocation | None,
    latitude: float | None,
    longitude: float | None,
    horizontal_accuracy_m: float | None,
    location_evidence: str | None,
) -> None:
    """Log one rejection. Swallows its own errors so the original response stands."""
    if not settings.geofence_diagnostics:
        return
    try:
        detail = _detail(exc)
        code = str(detail.get("code") or "")
        if code not in _DIAGNOSTIC_CODES:
            return
        gps_fix = latitude is not None and longitude is not None
        wifi_considered = (not gps_fix) and (location_evidence or "").strip().lower() == "wifi"
        pin_lat = None if location is None or location.latitude is None else float(location.latitude)
        pin_lng = None if location is None or location.longitude is None else float(location.longitude)
        radius = None if location is None else float(location.geofence_radius_m)
        distance = detail.get("distance_m")
        if distance is None and gps_fix and pin_lat is not None and pin_lng is not None:
            distance = round(
                haversine_distance_m(float(latitude), float(longitude), pin_lat, pin_lng),
                2,
            )
        reason = detail.get("message") or code
        logger.info(
            "GEOFENCE_DIAGNOSTIC attendance_saved=false action=%s "
            "gps_fix_obtained=%s wifi_fallback_considered=%s "
            "worksite_lat=%s worksite_lng=%s phone_lat=%s phone_lng=%s "
            "accuracy_m=%s distance_m=%s radius_m=%s code=%s reason=%s",
            action,
            str(gps_fix).lower(),
            str(wifi_considered).lower(),
            "none" if pin_lat is None else f"{pin_lat:.7f}",
            "none" if pin_lng is None else f"{pin_lng:.7f}",
            "none" if latitude is None else f"{float(latitude):.7f}",
            "none" if longitude is None else f"{float(longitude):.7f}",
            "none" if horizontal_accuracy_m is None else f"{float(horizontal_accuracy_m):.1f}",
            "none" if distance is None else distance,
            "none" if radius is None else radius,
            code,
            reason,
        )
    except Exception:
        logger.info("GEOFENCE_DIAGNOSTIC log_failed attendance_saved=false action=%s", action)
