"""Geofence helpers — haversine distance on the WGS84 sphere."""

from __future__ import annotations

import logging
import math

EARTH_RADIUS_M = 6_371_000

# Float rounding only.
DISTANCE_EPSILON_M = 0.05

# Modest server-side allowance for normal outdoor GPS error after the client
# has already averaged multiple samples. Keeps security while avoiding
# false rejects between face capture and the API call.
# For small fences (≤20 m) this is essential: outdoor GPS often drifts 8–15 m.
GPS_ACCURACY_TOLERANCE_M = 12.0
SMALL_GEOFENCE_RADIUS_M = 20.0

logger = logging.getLogger("aroll.geofence")


def haversine_distance_m(
    lat1: float,
    lon1: float,
    lat2: float,
    lon2: float,
) -> float:
    """Return great-circle distance in meters between two WGS84 coordinates."""
    phi1 = math.radians(lat1)
    phi2 = math.radians(lat2)
    d_phi = math.radians(lat2 - lat1)
    d_lambda = math.radians(lon2 - lon1)

    a = (
        math.sin(d_phi / 2) ** 2
        + math.cos(phi1) * math.cos(phi2) * math.sin(d_lambda / 2) ** 2
    )
    c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a))
    return EARTH_RADIUS_M * c


def is_within_geofence(
    *,
    latitude: float,
    longitude: float,
    center_latitude: float,
    center_longitude: float,
    radius_m: float | int,
) -> bool:
    distance_m = haversine_distance_m(
        latitude,
        longitude,
        center_latitude,
        center_longitude,
    )
    return distance_m <= float(radius_m) + GPS_ACCURACY_TOLERANCE_M + DISTANCE_EPSILON_M


def geofence_check(
    *,
    latitude: float,
    longitude: float,
    center_latitude: float,
    center_longitude: float,
    radius_m: float | int,
) -> dict[str, float | bool]:
    distance_m = haversine_distance_m(
        latitude,
        longitude,
        center_latitude,
        center_longitude,
    )
    allowed_radius_m = float(radius_m)
    small = allowed_radius_m <= SMALL_GEOFENCE_RADIUS_M
    # Overlap rule: distance − tolerance ≤ radius
    # (equivalent to distance ≤ radius + tolerance).
    effective_radius_m = allowed_radius_m + GPS_ACCURACY_TOLERANCE_M + DISTANCE_EPSILON_M
    best_case_m = max(0.0, distance_m - GPS_ACCURACY_TOLERANCE_M)
    inside = distance_m <= effective_radius_m

    logger.info(
        "GEOFENCE_VALIDATION mode=%s business=(%.7f, %.7f) employee=(%.7f, %.7f) "
        "radius_m=%.2f uncertainty_m=%.2f distance_m=%.2f best_case_m=%.2f result=%s",
        "SMALL_RADIUS" if small else "STANDARD",
        center_latitude,
        center_longitude,
        latitude,
        longitude,
        allowed_radius_m,
        GPS_ACCURACY_TOLERANCE_M,
        distance_m,
        best_case_m,
        "INSIDE" if inside else "OUTSIDE",
    )

    return {
        "distance_m": round(distance_m, 2),
        # Report the owner's configured radius (not the tolerance-expanded value).
        "allowed_radius_m": allowed_radius_m,
        "inside_geofence": inside,
    }
