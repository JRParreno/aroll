import logging

from app.core.config import settings
from app.core.geofence_diagnostics import log_clock_location_failure
from app.services.attendance_clock import GeofenceValidationError
from app.services.workplace_wifi import WorkplaceWifiMismatchError


class _Pin:
    latitude = 13.2946150
    longitude = 123.4827835
    geofence_radius_m = 6


def test_diagnostic_is_silent_unless_enabled(caplog, monkeypatch):
    monkeypatch.setattr(settings, "geofence_diagnostics", False)
    exc = GeofenceValidationError(distance_m=8.64, allowed_radius_m=6)
    with caplog.at_level(logging.INFO):
        log_clock_location_failure(
            exc,
            action="time_in",
            location=_Pin(),
            latitude=13.2945992,
            longitude=123.4827053,
            horizontal_accuracy_m=12.4,
            location_evidence="gps",
        )
    assert "GEOFENCE_DIAGNOSTIC" not in caplog.text


def test_diagnostic_records_an_unsaved_time_in_rejection(caplog, monkeypatch):
    monkeypatch.setattr(settings, "geofence_diagnostics", True)
    exc = GeofenceValidationError(distance_m=8.64, allowed_radius_m=6)
    with caplog.at_level(logging.INFO):
        log_clock_location_failure(
            exc,
            action="time_in",
            location=_Pin(),
            latitude=13.2945992,
            longitude=123.4827053,
            horizontal_accuracy_m=12.4,
            location_evidence="gps",
        )
    line = caplog.text
    assert "GEOFENCE_DIAGNOSTIC" in line
    assert "attendance_saved=false" in line
    assert "attendance_saved=true" not in line
    assert "action=time_in" in line
    assert "gps_fix_obtained=true" in line
    assert "wifi_fallback_considered=false" in line
    assert "worksite_lat=13.2946150" in line
    assert "worksite_lng=123.4827835" in line
    assert "phone_lat=13.2945992" in line
    assert "phone_lng=123.4827053" in line
    assert "accuracy_m=12.4" in line
    assert "distance_m=8.64" in line
    assert "radius_m=6.0" in line
    assert "code=outside_geofence" in line


def test_diagnostic_records_time_out_wifi_fallback_without_a_fix(caplog, monkeypatch):
    monkeypatch.setattr(settings, "geofence_diagnostics", True)
    exc = WorkplaceWifiMismatchError()
    with caplog.at_level(logging.INFO):
        log_clock_location_failure(
            exc,
            action="time_out",
            location=_Pin(),
            latitude=None,
            longitude=None,
            horizontal_accuracy_m=None,
            location_evidence="wifi",
        )
    line = caplog.text
    assert "action=time_out" in line
    assert "attendance_saved=false" in line
    assert "gps_fix_obtained=false" in line
    assert "wifi_fallback_considered=true" in line
    assert "phone_lat=none" in line
    assert "accuracy_m=none" in line
    assert "code=workplace_wifi_mismatch" in line
