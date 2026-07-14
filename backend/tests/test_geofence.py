from app.core.geofence import geofence_check, haversine_distance_m, is_within_geofence

# Quezon City area — stable reference coordinates for tests.
_CENTER_LAT = 14.6760
_CENTER_LNG = 121.0437
_RADIUS_M = 100.0


def test_haversine_zero_distance():
    distance = haversine_distance_m(_CENTER_LAT, _CENTER_LNG, _CENTER_LAT, _CENTER_LNG)
    assert distance == 0.0


def test_is_within_geofence_inside():
    assert is_within_geofence(
        latitude=_CENTER_LAT,
        longitude=_CENTER_LNG,
        center_latitude=_CENTER_LAT,
        center_longitude=_CENTER_LNG,
        radius_m=_RADIUS_M,
    )


def test_is_within_geofence_outside():
    far_lat = _CENTER_LAT + 0.01
    assert not is_within_geofence(
        latitude=far_lat,
        longitude=_CENTER_LNG,
        center_latitude=_CENTER_LAT,
        center_longitude=_CENTER_LNG,
        radius_m=_RADIUS_M,
    )


def test_geofence_check_boundary_inside():
    # ~99 m north — should remain inside a 100 m radius.
    boundary_lat = _CENTER_LAT + (99 / 111_320)
    result = geofence_check(
        latitude=boundary_lat,
        longitude=_CENTER_LNG,
        center_latitude=_CENTER_LAT,
        center_longitude=_CENTER_LNG,
        radius_m=_RADIUS_M,
    )
    assert result["distance_m"] < _RADIUS_M
    assert result["inside_geofence"] is True


def test_geofence_check_just_outside_boundary():
    outside_lat = _CENTER_LAT + (101 / 111_320)
    result = geofence_check(
        latitude=outside_lat,
        longitude=_CENTER_LNG,
        center_latitude=_CENTER_LAT,
        center_longitude=_CENTER_LNG,
        radius_m=_RADIUS_M,
    )
    assert result["inside_geofence"] is False
