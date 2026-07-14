"""Geofence helpers — haversine distance on the WGS84 sphere."""

from __future__ import annotations

import math

EARTH_RADIUS_M = 6_371_000


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
    return distance_m <= float(radius_m)


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
    return {
        "distance_m": round(distance_m, 2),
        "allowed_radius_m": allowed_radius_m,
        "inside_geofence": distance_m <= allowed_radius_m,
    }
