"""GPS geofence is authoritative. Wi-Fi is a fallback only when GPS is omitted."""

from __future__ import annotations

import uuid
from datetime import datetime, timedelta, timezone
from pathlib import Path
from unittest.mock import MagicMock, patch

import pytest
from fastapi import HTTPException

from app.services.attendance_clock import (
    GeofenceValidationError,
    clock_in_employee,
    clock_out_employee,
)
from app.models.attendance import AttendanceRecord
from app.models.business import BusinessLocation
from app.models.enums import AttendanceStatus, UserRole
from app.models.workplace_wifi import WorkplaceWifiAccessPoint
from app.services.attendance_clock import clock_in_employee, clock_out_employee
from app.services.workplace_wifi import (
    WIFI_MATCHED,
    WIFI_NOT_CONFIGURED,
    WIFI_UNAVAILABLE,
    WorkplaceWifiFallbackRejected,
    WorkplaceWifiMismatchError,
    assert_wifi_fallback,
    decide_workplace_wifi,
    enabled_bssid_map,
    normalize_bssid,
    owned_access_point,
    register_access_point,
    require_owner_business,
)

WORK_BSSID = "aa:bb:cc:dd:ee:01"
OTHER_BSSID = "aa:bb:cc:dd:ee:02"


def _location(*, radius: int, lat: float = 14.5995, lng: float = 120.9842) -> BusinessLocation:
    return BusinessLocation(
        id=uuid.uuid4(),
        business_id=uuid.uuid4(),
        label="Main",
        address="Workplace",
        latitude=lat,
        longitude=lng,
        geofence_radius_m=radius,
        is_primary=True,
    )


def _employee(business_id: uuid.UUID) -> MagicMock:
    employee = MagicMock()
    employee.id = uuid.uuid4()
    employee.business_id = business_id
    employee.position_id = None
    return employee


def _clock_db() -> MagicMock:
    db = MagicMock()
    db.query.return_value.filter.return_value.first.return_value = None
    db.query.return_value.filter.return_value.all.return_value = []
    return db


def _policy() -> MagicMock:
    policy = MagicMock()
    policy.early_clock_in_minutes = 30
    policy.on_time_grace_minutes = 5
    policy.half_day_threshold_minutes = 120
    policy.absent_threshold_minutes = 240
    policy.early_out_deduction_enabled = False
    return policy


def _assignment(now_local: datetime) -> tuple[MagicMock, MagicMock]:
    assignment = MagicMock()
    assignment.id = uuid.uuid4()
    assignment.work_date = now_local.date()
    assignment.rest_day = False
    assignment.rest_day_authorized = False
    shift = MagicMock()
    shift.name = "Day"
    shift.start_time = now_local.time().replace(microsecond=0)
    shift.end_time = (now_local + timedelta(hours=8)).time().replace(microsecond=0)
    return assignment, shift


def _added_record(db: MagicMock) -> AttendanceRecord:
    record = db.add.call_args.args[0]
    assert isinstance(record, AttendanceRecord)
    return record


@patch("app.services.missing_clock_out.ensure_incomplete_for_employee")
@patch("app.services.leave_requests.raise_if_on_approved_leave")
@patch("app.services.attendance_clock._validate_geofence")
@patch("app.services.attendance_clock._primary_location")
def test_wifi_disabled_keeps_existing_clock_in(mock_location, mock_geofence, _leave, _incomplete):
    location = _location(radius=15)
    mock_location.return_value = location
    mock_geofence.return_value = {"inside": True}
    db = _clock_db()
    employee = _employee(location.business_id)
    now = datetime(2026, 10, 24, 9, 0)
    assignment, shift = _assignment(now)
    with (
        patch("app.services.attendance_clock.business_now", return_value=now),
        patch("app.services.attendance_clock._attendance_policy", return_value=_policy()),
        patch("app.services.attendance_clock._active_record", return_value=None),
        patch("app.services.attendance_clock._resolve_assignment", return_value=(assignment, shift)),
        patch("app.services.attendance_clock._existing_assignment_record", return_value=None),
        patch("app.services.workplace_wifi.enabled_bssid_map", return_value={}) as allow_list,
    ):
        clock_in_employee(db, employee, latitude=14.5995, longitude=120.9842)
    allow_list.assert_not_called()
    record = _added_record(db)
    assert record.wifi_verification_in is None
    assert record.status == AttendanceStatus.in_progress
    assert record.time_in is not None
    db.commit.assert_called_once()


@patch("app.services.missing_clock_out.ensure_incomplete_for_employee")
@patch("app.services.leave_requests.raise_if_on_approved_leave")
@patch("app.services.attendance_clock._validate_geofence")
@patch("app.services.attendance_clock._primary_location")
@pytest.mark.parametrize("radius", [21, 100])
def test_radius_above_20_ignores_wifi(mock_location, mock_geofence, _leave, _incomplete, radius):
    location = _location(radius=radius)
    mock_location.return_value = location
    mock_geofence.return_value = {"inside": True}
    db = _clock_db()
    employee = _employee(location.business_id)
    now = datetime(2026, 10, 24, 9, 0)
    assignment, shift = _assignment(now)
    with (
        patch("app.services.attendance_clock.business_now", return_value=now),
        patch("app.services.attendance_clock._attendance_policy", return_value=_policy()),
        patch("app.services.attendance_clock._active_record", return_value=None),
        patch("app.services.attendance_clock._resolve_assignment", return_value=(assignment, shift)),
        patch("app.services.attendance_clock._existing_assignment_record", return_value=None),
        patch("app.services.workplace_wifi.enabled_bssid_map") as allow_list,
    ):
        clock_in_employee(
            db,
            employee,
            latitude=14.5995,
            longitude=120.9842,
            observed_bssid=OTHER_BSSID,
        )
    allow_list.assert_not_called()
    record = _added_record(db)
    assert record.wifi_verification_in is None
    assert record.matched_wifi_access_point_id_in is None


@patch("app.services.missing_clock_out.ensure_incomplete_for_employee")
@patch("app.services.leave_requests.raise_if_on_approved_leave")
@patch("app.services.attendance_clock._validate_geofence")
@patch("app.services.attendance_clock._primary_location")
@pytest.mark.parametrize("radius", [20, 8])
def test_gps_inside_does_not_require_a_matching_bssid(
    mock_location, mock_geofence, _leave, _incomplete, radius
):
    location = _location(radius=radius)
    access_id = uuid.uuid4()
    mock_location.return_value = location
    mock_geofence.return_value = {"inside": True}
    db = _clock_db()
    employee = _employee(location.business_id)
    now = datetime(2026, 10, 24, 9, 0)
    assignment, shift = _assignment(now)
    with (
        patch("app.services.attendance_clock.business_now", return_value=now),
        patch("app.services.attendance_clock._attendance_policy", return_value=_policy()),
        patch("app.services.attendance_clock._active_record", return_value=None),
        patch("app.services.attendance_clock._resolve_assignment", return_value=(assignment, shift)),
        patch("app.services.attendance_clock._existing_assignment_record", return_value=None),
        patch(
            "app.services.workplace_wifi.enabled_bssid_map",
            return_value={WORK_BSSID: access_id},
        ),
    ):
        payload = clock_in_employee(
            db,
            employee,
            latitude=14.5995,
            longitude=120.9842,
            observed_bssid="AA-BB-CC-DD-EE-01",
            face_match_score=0.91,
            liveness_passed=True,
        )
    record = _added_record(db)
    assert record.wifi_verification_in is None
    assert record.matched_wifi_access_point_id_in is None
    assert record.latitude_in == 14.5995
    assert float(record.face_match_score) == 0.91
    assert record.liveness_passed is True
    assert record.status == AttendanceStatus.in_progress
    assert payload["status"] == AttendanceStatus.in_progress.value
    assert record.shift_assignment_id == assignment.id


@patch("app.services.missing_clock_out.ensure_incomplete_for_employee")
@patch("app.services.leave_requests.raise_if_on_approved_leave")
@patch("app.services.attendance_clock._validate_geofence")
@patch("app.services.attendance_clock._primary_location")
def test_gps_inside_accepts_a_different_bssid(
    mock_location, mock_geofence, _leave, _incomplete
):
    location = _location(radius=20)
    mock_location.return_value = location
    mock_geofence.return_value = {"inside": True}
    db = _clock_db()
    employee = _employee(location.business_id)
    now = datetime(2026, 10, 24, 9, 0)
    assignment, shift = _assignment(now)
    with (
        patch("app.services.attendance_clock.business_now", return_value=now),
        patch("app.services.attendance_clock._attendance_policy", return_value=_policy()),
        patch("app.services.attendance_clock._active_record", return_value=None),
        patch("app.services.attendance_clock._resolve_assignment", return_value=(assignment, shift)),
        patch("app.services.attendance_clock._existing_assignment_record", return_value=None),
        patch("app.services.workplace_wifi.enabled_bssid_map") as allow_list,
    ):
        clock_in_employee(
            db,
            employee,
            latitude=14.5995,
            longitude=120.9842,
            observed_bssid=OTHER_BSSID,
            location_evidence="wifi",
        )
    allow_list.assert_not_called()
    record = _added_record(db)
    assert record.wifi_verification_in is None
    assert record.time_in is not None
    db.commit.assert_called_once()


@patch("app.services.missing_clock_out.ensure_incomplete_for_employee")
@patch("app.services.leave_requests.raise_if_on_approved_leave")
@patch("app.services.attendance_clock._validate_geofence")
@patch("app.services.attendance_clock._primary_location")
@pytest.mark.parametrize("observed", [None, "", "02:00:00:00:00:00", "<unknown ssid>"])
def test_gps_inside_ignores_an_unreadable_bssid(
    mock_location, mock_geofence, _leave, _incomplete, observed
):
    location = _location(radius=12)
    mock_location.return_value = location
    mock_geofence.return_value = {"inside": True}
    db = _clock_db()
    employee = _employee(location.business_id)
    now = datetime(2026, 10, 24, 9, 0)
    assignment, shift = _assignment(now)
    with (
        patch("app.services.attendance_clock.business_now", return_value=now),
        patch("app.services.attendance_clock._attendance_policy", return_value=_policy()),
        patch("app.services.attendance_clock._active_record", return_value=None),
        patch("app.services.attendance_clock._resolve_assignment", return_value=(assignment, shift)),
        patch("app.services.attendance_clock._existing_assignment_record", return_value=None),
        patch(
            "app.services.workplace_wifi.enabled_bssid_map",
            return_value={WORK_BSSID: uuid.uuid4()},
        ),
    ):
        clock_in_employee(
            db,
            employee,
            latitude=14.5995,
            longitude=120.9842,
            observed_bssid=observed,
        )
    record = _added_record(db)
    assert record.wifi_verification_in is None
    assert record.matched_wifi_access_point_id_in is None
    assert record.time_in is not None


@patch("app.services.missing_clock_out.ensure_incomplete_for_employee")
@patch("app.services.leave_requests.raise_if_on_approved_leave")
@patch("app.services.attendance_clock._primary_location")
def test_gps_rejection_wins_even_when_bssid_would_match(
    mock_location, _leave, _incomplete
):
    location = _location(radius=15)
    location.minimum_rssi_dbm = -50
    mock_location.return_value = location
    db = _clock_db()
    employee = _employee(location.business_id)
    with patch("app.services.workplace_wifi.enabled_bssid_map") as allow_list:
        with pytest.raises(GeofenceValidationError) as exc:
            clock_in_employee(
                db,
                employee,
                latitude=14.70,
                longitude=121.10,
                observed_bssid=WORK_BSSID,
                observed_rssi_dbm=-40,
                location_evidence="wifi",
            )
    assert exc.value.status_code == 403
    assert exc.value.detail["code"] == "outside_geofence"
    allow_list.assert_not_called()
    db.add.assert_not_called()


@patch("app.services.missing_clock_out.ensure_incomplete_for_employee")
@patch("app.services.leave_requests.raise_if_on_approved_leave")
@patch("app.services.attendance_clock._primary_location")
def test_six_meter_radius_rejects_ten_meters_on_time_in(
    mock_location, _leave, _incomplete
):
    location = _location(radius=6)
    mock_location.return_value = location
    db = _clock_db()
    employee = _employee(location.business_id)
    ten_meters_north = float(location.latitude) + (10 / 111_320)
    with patch("app.services.workplace_wifi.enabled_bssid_map") as allow_list:
        with pytest.raises(GeofenceValidationError) as exc:
            clock_in_employee(
                db,
                employee,
                latitude=ten_meters_north,
                longitude=float(location.longitude),
                observed_bssid=WORK_BSSID,
                location_evidence="wifi",
            )
    assert exc.value.detail["code"] == "outside_geofence"
    allow_list.assert_not_called()
    db.add.assert_not_called()
    db.commit.assert_not_called()


@patch("app.services.attendance_clock._active_record")
@patch("app.services.missing_clock_out.ensure_incomplete_for_employee")
@patch("app.services.leave_requests.raise_if_on_approved_leave")
@patch("app.services.attendance_clock._primary_location")
def test_six_meter_radius_rejects_ten_meters_on_time_out(
    mock_location, _leave, _incomplete, _active
):
    location = _location(radius=6)
    mock_location.return_value = location
    record = AttendanceRecord(
        id=uuid.uuid4(),
        business_id=location.business_id,
        employee_id=uuid.uuid4(),
        time_in=datetime.now(timezone.utc),
        status=AttendanceStatus.in_progress,
    )
    _active.return_value = record
    db = _clock_db()
    employee = _employee(location.business_id)
    ten_meters_north = float(location.latitude) + (10 / 111_320)
    with patch("app.services.workplace_wifi.enabled_bssid_map") as allow_list:
        with pytest.raises(GeofenceValidationError) as exc:
            clock_out_employee(
                db,
                employee,
                latitude=ten_meters_north,
                longitude=float(location.longitude),
                observed_bssid=WORK_BSSID,
                location_evidence="wifi",
            )
    assert exc.value.detail["code"] == "outside_geofence"
    allow_list.assert_not_called()
    assert record.time_out is None
    db.commit.assert_not_called()


def test_disabled_and_other_worksite_bssid_do_not_match():
    this_site = {WORK_BSSID: uuid.uuid4()}
    with pytest.raises(WorkplaceWifiMismatchError):
        decide_workplace_wifi(
            radius_m=19,
            is_demo=False,
            enabled_bssids=this_site,
            observed_bssid=OTHER_BSSID,
        )
    ignored = decide_workplace_wifi(
        radius_m=20,
        is_demo=False,
        enabled_bssids=this_site,
        observed_bssid=WORK_BSSID,
    )
    assert ignored == (None, None)
    other_site_only = {OTHER_BSSID: uuid.uuid4()}
    with pytest.raises(WorkplaceWifiMismatchError):
        decide_workplace_wifi(
            radius_m=10,
            is_demo=False,
            enabled_bssids=other_site_only,
            observed_bssid=WORK_BSSID,
        )


def test_enabled_map_uses_only_enabled_rows():
    db = MagicMock()
    row = MagicMock(bssid="AA:BB:CC:DD:EE:01", id=uuid.uuid4())
    db.query.return_value.filter.return_value.all.return_value = [row]
    found = enabled_bssid_map(db, uuid.uuid4())
    assert found == {WORK_BSSID: row.id}
    criterion = db.query.return_value.filter.call_args.args
    assert any("enabled" in str(item) for item in criterion)


def test_duplicate_normalized_bssid_is_rejected():
    db = MagicMock()
    location = _location(radius=15)
    existing = WorkplaceWifiAccessPoint(
        id=uuid.uuid4(),
        business_id=location.business_id,
        location_id=location.id,
        label="Old",
        ssid="Cafe",
        bssid=WORK_BSSID,
        enabled=True,
    )
    db.query.return_value.filter.return_value.first.side_effect = [location, existing]
    with pytest.raises(HTTPException) as exc:
        register_access_point(
            db,
            business_id=location.business_id,
            label="Replacement",
            bssid="AA-BB-CC-DD-EE-01",
            ssid="Cafe",
        )
    assert exc.value.status_code == 409
    db.add.assert_not_called()


def test_same_bssid_can_be_registered_on_another_worksite():
    first = decide_workplace_wifi(
        radius_m=19,
        is_demo=False,
        enabled_bssids={WORK_BSSID: uuid.uuid4()},
        observed_bssid=WORK_BSSID,
    )
    second = decide_workplace_wifi(
        radius_m=19,
        is_demo=False,
        enabled_bssids={WORK_BSSID: uuid.uuid4()},
        observed_bssid=WORK_BSSID,
    )
    assert first[0] == WIFI_MATCHED
    assert second[0] == WIFI_MATCHED
    assert first[1] != second[1]


def test_non_owner_cannot_manage_wifi():
    manager = MagicMock()
    manager.role = UserRole.manager
    manager.business_id = uuid.uuid4()
    with pytest.raises(HTTPException) as exc:
        require_owner_business(manager)
    assert exc.value.status_code == 403


def test_owner_cannot_manage_another_business_access_point():
    owner_business = uuid.uuid4()
    row = WorkplaceWifiAccessPoint(
        id=uuid.uuid4(),
        business_id=uuid.uuid4(),
        location_id=uuid.uuid4(),
        label="Other",
        ssid=None,
        bssid=WORK_BSSID,
        enabled=True,
    )
    db = MagicMock()
    db.get.return_value = row
    with pytest.raises(HTTPException) as exc:
        owned_access_point(db, business_id=owner_business, access_point_id=row.id)
    assert exc.value.status_code == 404


@patch("app.services.missing_clock_out.ensure_incomplete_for_employee")
@patch("app.services.leave_requests.raise_if_on_approved_leave")
@patch("app.services.attendance_clock._validate_geofence")
@patch("app.services.attendance_clock._primary_location")
@patch("app.services.attendance_clock.load_business_for_employee")
def test_demo_skips_wifi_even_with_a_different_bssid(
    mock_business, mock_location, mock_geofence, _leave, _incomplete
):
    location = _location(radius=10)
    mock_location.return_value = location
    mock_geofence.return_value = {"inside": True}
    business = MagicMock()
    business.is_demo = True
    mock_business.return_value = business
    db = _clock_db()
    employee = _employee(location.business_id)
    now = datetime(2026, 10, 24, 9, 0)
    assignment, shift = _assignment(now)
    with (
        patch("app.services.attendance_clock.business_now", return_value=now),
        patch("app.services.attendance_clock._attendance_policy", return_value=_policy()),
        patch("app.services.attendance_clock._active_record", return_value=None),
        patch("app.services.attendance_clock._resolve_assignment", return_value=(assignment, shift)),
        patch("app.services.attendance_clock._existing_assignment_record", return_value=None),
        patch("app.services.workplace_wifi.enabled_bssid_map") as allow_list,
    ):
        clock_in_employee(
            db,
            employee,
            latitude=14.0,
            longitude=120.0,
            observed_bssid=OTHER_BSSID,
        )
    allow_list.assert_not_called()
    assert _added_record(db).wifi_verification_in is None


def test_demo_decision_ignores_allow_list():
    outcome, matched = decide_workplace_wifi(
        radius_m=10,
        is_demo=True,
        enabled_bssids={WORK_BSSID: uuid.uuid4()},
        observed_bssid=OTHER_BSSID,
    )
    assert outcome is None
    assert matched is None


@patch("app.services.attendance_clock._active_record")
@patch("app.services.missing_clock_out.raise_if_incomplete_clock_out")
@patch("app.services.leave_requests.raise_if_on_approved_leave")
@patch("app.services.attendance_clock._validate_geofence")
@patch("app.services.attendance_clock._primary_location")
def test_clock_out_fallback_mismatch_does_not_set_time_out(
    mock_location, mock_geofence, _leave, _incomplete, mock_active
):
    location = _location(radius=19)
    mock_location.return_value = location
    mock_geofence.return_value = {"inside": True}
    record = AttendanceRecord(
        id=uuid.uuid4(),
        business_id=location.business_id,
        employee_id=uuid.uuid4(),
        shift_assignment_id=None,
        time_in=datetime.now(timezone.utc) - timedelta(hours=2),
        status=AttendanceStatus.in_progress,
    )
    db = _clock_db()
    db.query.return_value.filter.return_value.order_by.return_value.first.return_value = None
    mock_active.return_value = record
    employee = _employee(location.business_id)
    with patch(
        "app.services.workplace_wifi.enabled_bssid_map",
        return_value={WORK_BSSID: uuid.uuid4()},
    ):
        with pytest.raises(WorkplaceWifiMismatchError):
            clock_out_employee(
                db,
                employee,
                observed_bssid=OTHER_BSSID,
                location_evidence="wifi",
            )
    assert record.time_out is None
    assert record.wifi_verification_out is None
    db.commit.assert_not_called()


@patch("app.services.attendance_clock._active_record")
@patch("app.services.activity_notifications.notify_overtime_pending_if_needed")
@patch("app.services.ot_approval.sync_ot_approval_after_close")
@patch("app.services.employee_pay.stamp_attendance_completion_pay")
@patch("app.services.missing_clock_out.raise_if_incomplete_clock_out")
@patch("app.services.leave_requests.raise_if_on_approved_leave")
@patch("app.services.attendance_clock._validate_geofence")
@patch("app.services.attendance_clock._primary_location")
def test_clock_out_fallback_match_records_evidence(
    mock_location,
    mock_geofence,
    _leave,
    _incomplete,
    _stamp,
    _ot,
    _notify,
    mock_active,
):
    location = _location(radius=15)
    access_id = uuid.uuid4()
    mock_location.return_value = location
    mock_geofence.return_value = {"inside": True}
    started = datetime.now(timezone.utc) - timedelta(hours=3)
    record = AttendanceRecord(
        id=uuid.uuid4(),
        business_id=location.business_id,
        employee_id=uuid.uuid4(),
        shift_assignment_id=None,
        time_in=started,
        status=AttendanceStatus.in_progress,
        face_match_score=0.88,
        liveness_passed=True,
    )
    db = _clock_db()
    db.query.return_value.filter.return_value.order_by.return_value.first.return_value = None
    mock_active.return_value = record
    employee = _employee(location.business_id)
    with (
        patch("app.services.attendance_clock._attendance_policy", return_value=_policy()),
        patch(
            "app.services.workplace_wifi.enabled_bssid_map",
            return_value={WORK_BSSID: access_id},
        ),
    ):
        clock_out_employee(
            db,
            employee,
            observed_bssid=WORK_BSSID,
            location_evidence="wifi",
            face_match_score=0.9,
            liveness_passed=True,
        )
    assert record.time_out is not None
    assert record.time_in == started
    assert float(record.face_match_score) == 0.88
    assert float(record.face_match_score_out) == 0.9
    assert record.liveness_passed is True
    assert record.wifi_verification_out == WIFI_MATCHED
    assert record.matched_wifi_access_point_id_out == access_id
    assert record.status == AttendanceStatus.complete


def test_unknown_placeholder_bssid_is_unavailable():
    assert normalize_bssid("02:00:00:00:00:00") is None
    assert normalize_bssid("not-a-mac") is None
    assert normalize_bssid("AA:BB:CC:DD:EE:01") == WORK_BSSID


def _fallback_clock_in(db, employee, location, *, observed, evidence="wifi", rssi=None):
    now = datetime(2026, 10, 24, 9, 0)
    assignment, shift = _assignment(now)
    with (
        patch("app.services.attendance_clock.business_now", return_value=now),
        patch("app.services.attendance_clock._attendance_policy", return_value=_policy()),
        patch("app.services.attendance_clock._active_record", return_value=None),
        patch("app.services.attendance_clock._resolve_assignment", return_value=(assignment, shift)),
        patch("app.services.attendance_clock._existing_assignment_record", return_value=None),
    ):
        return clock_in_employee(
            db,
            employee,
            observed_bssid=observed,
            observed_rssi_dbm=rssi,
            location_evidence=evidence,
        )


@patch("app.services.missing_clock_out.ensure_incomplete_for_employee")
@patch("app.services.leave_requests.raise_if_on_approved_leave")
@patch("app.services.attendance_clock._primary_location")
@pytest.mark.parametrize("radius", [19, 8])
def test_wifi_fallback_matching_bssid_records_time_in(mock_location, _leave, _incomplete, radius):
    location = _location(radius=radius)
    access_id = uuid.uuid4()
    mock_location.return_value = location
    db = _clock_db()
    employee = _employee(location.business_id)
    with patch(
        "app.services.workplace_wifi.enabled_bssid_map",
        return_value={WORK_BSSID: access_id},
    ):
        _fallback_clock_in(db, employee, location, observed=WORK_BSSID)
    record = _added_record(db)
    assert record.wifi_verification_in == WIFI_MATCHED
    assert record.matched_wifi_access_point_id_in == access_id
    assert record.latitude_in is None
    assert record.longitude_in is None
    assert record.time_in is not None
    db.commit.assert_called_once()


def test_rssi_setting_accepts_a_floor_and_rejects_out_of_range():
    from pydantic import ValidationError

    from app.schemas.business import WorkplaceWifiRssiSetting

    assert WorkplaceWifiRssiSetting(minimum_rssi_dbm=None).minimum_rssi_dbm is None
    assert WorkplaceWifiRssiSetting(minimum_rssi_dbm=-50).minimum_rssi_dbm == -50
    with pytest.raises(ValidationError):
        WorkplaceWifiRssiSetting(minimum_rssi_dbm=-10)
    with pytest.raises(ValidationError):
        WorkplaceWifiRssiSetting(minimum_rssi_dbm=-121)


@patch("app.services.missing_clock_out.ensure_incomplete_for_employee")
@patch("app.services.leave_requests.raise_if_on_approved_leave")
@patch("app.services.attendance_clock._primary_location")
@pytest.mark.parametrize("rssi", [-40, -50])
def test_wifi_fallback_rssi_at_or_above_threshold_records_time_in(
    mock_location, _leave, _incomplete, rssi
):
    location = _location(radius=19)
    location.minimum_rssi_dbm = -50
    mock_location.return_value = location
    db = _clock_db()
    employee = _employee(location.business_id)
    with patch(
        "app.services.workplace_wifi.enabled_bssid_map",
        return_value={WORK_BSSID: uuid.uuid4()},
    ):
        _fallback_clock_in(db, employee, location, observed=WORK_BSSID, rssi=rssi)
    record = _added_record(db)
    assert record.latitude_in is None
    assert record.longitude_in is None
    assert record.time_in is not None


@patch("app.services.missing_clock_out.ensure_incomplete_for_employee")
@patch("app.services.leave_requests.raise_if_on_approved_leave")
@patch("app.services.attendance_clock._primary_location")
@pytest.mark.parametrize("rssi", [-51, None, -127, 0])
def test_wifi_fallback_weak_or_unreadable_rssi_does_not_punch(
    mock_location, _leave, _incomplete, rssi
):
    location = _location(radius=19)
    location.minimum_rssi_dbm = -50
    mock_location.return_value = location
    db = _clock_db()
    employee = _employee(location.business_id)
    with patch(
        "app.services.workplace_wifi.enabled_bssid_map",
        return_value={WORK_BSSID: uuid.uuid4()},
    ):
        with pytest.raises(WorkplaceWifiFallbackRejected) as exc:
            _fallback_clock_in(db, employee, location, observed=WORK_BSSID, rssi=rssi)
    code = exc.value.detail["code"]
    assert code in {"workplace_wifi_rssi_weak", "workplace_wifi_rssi_unavailable"}
    if rssi == -51:
        assert code == "workplace_wifi_rssi_weak"
    else:
        assert code == "workplace_wifi_rssi_unavailable"
    db.add.assert_not_called()
    db.commit.assert_not_called()


@patch("app.services.missing_clock_out.ensure_incomplete_for_employee")
@patch("app.services.leave_requests.raise_if_on_approved_leave")
@patch("app.services.attendance_clock._primary_location")
def test_wifi_fallback_without_threshold_ignores_missing_rssi(
    mock_location, _leave, _incomplete
):
    location = _location(radius=19)
    assert location.minimum_rssi_dbm is None
    mock_location.return_value = location
    db = _clock_db()
    employee = _employee(location.business_id)
    with patch(
        "app.services.workplace_wifi.enabled_bssid_map",
        return_value={WORK_BSSID: uuid.uuid4()},
    ):
        _fallback_clock_in(db, employee, location, observed=WORK_BSSID, rssi=None)
    assert _added_record(db).time_in is not None


@patch("app.services.missing_clock_out.ensure_incomplete_for_employee")
@patch("app.services.leave_requests.raise_if_on_approved_leave")
@patch("app.services.attendance_clock._primary_location")
def test_radius_20_rejects_wifi_fallback_even_with_a_strong_rssi(
    mock_location, _leave, _incomplete
):
    location = _location(radius=20)
    location.minimum_rssi_dbm = -50
    mock_location.return_value = location
    db = _clock_db()
    employee = _employee(location.business_id)
    with patch("app.services.workplace_wifi.enabled_bssid_map") as allow_list:
        with pytest.raises(WorkplaceWifiFallbackRejected) as exc:
            _fallback_clock_in(db, employee, location, observed=WORK_BSSID, rssi=-40)
    assert exc.value.detail["code"] == "wifi_fallback_unavailable"
    allow_list.assert_not_called()
    db.add.assert_not_called()


@patch("app.services.missing_clock_out.ensure_incomplete_for_employee")
@patch("app.services.leave_requests.raise_if_on_approved_leave")
@patch("app.services.attendance_clock._primary_location")
@pytest.mark.parametrize("observed", [None, "", "02:00:00:00:00:00"])
def test_wifi_fallback_unreadable_bssid_does_not_punch(
    mock_location, _leave, _incomplete, observed
):
    location = _location(radius=19)
    mock_location.return_value = location
    db = _clock_db()
    employee = _employee(location.business_id)
    with patch(
        "app.services.workplace_wifi.enabled_bssid_map",
        return_value={WORK_BSSID: uuid.uuid4()},
    ):
        with pytest.raises(WorkplaceWifiFallbackRejected) as exc:
            _fallback_clock_in(db, employee, location, observed=observed)
    assert exc.value.detail["code"] == "workplace_wifi_unavailable"
    db.add.assert_not_called()
    db.commit.assert_not_called()


@patch("app.services.missing_clock_out.ensure_incomplete_for_employee")
@patch("app.services.leave_requests.raise_if_on_approved_leave")
@patch("app.services.attendance_clock._primary_location")
def test_wifi_fallback_mismatch_does_not_punch(mock_location, _leave, _incomplete):
    location = _location(radius=19)
    location.minimum_rssi_dbm = -50
    mock_location.return_value = location
    db = _clock_db()
    employee = _employee(location.business_id)
    with patch(
        "app.services.workplace_wifi.enabled_bssid_map",
        return_value={WORK_BSSID: uuid.uuid4()},
    ):
        with pytest.raises(WorkplaceWifiMismatchError):
            _fallback_clock_in(
                db, employee, location, observed=OTHER_BSSID, rssi=-40
            )
    db.add.assert_not_called()
    db.commit.assert_not_called()


@patch("app.services.missing_clock_out.ensure_incomplete_for_employee")
@patch("app.services.leave_requests.raise_if_on_approved_leave")
@patch("app.services.attendance_clock._primary_location")
def test_wifi_fallback_without_access_points_does_not_punch(
    mock_location, _leave, _incomplete
):
    location = _location(radius=19)
    mock_location.return_value = location
    db = _clock_db()
    employee = _employee(location.business_id)
    with patch("app.services.workplace_wifi.enabled_bssid_map", return_value={}):
        with pytest.raises(WorkplaceWifiFallbackRejected) as exc:
            _fallback_clock_in(db, employee, location, observed=WORK_BSSID)
    assert exc.value.detail["code"] == "workplace_wifi_not_configured"
    db.add.assert_not_called()


@patch("app.services.missing_clock_out.ensure_incomplete_for_employee")
@patch("app.services.leave_requests.raise_if_on_approved_leave")
@patch("app.services.attendance_clock._validate_geofence")
@patch("app.services.attendance_clock._primary_location")
def test_radius_above_20_rejects_wifi_fallback(
    mock_location, mock_geofence, _leave, _incomplete
):
    location = _location(radius=21)
    mock_location.return_value = location
    mock_geofence.return_value = {"inside": True}
    db = _clock_db()
    employee = _employee(location.business_id)
    with patch("app.services.workplace_wifi.enabled_bssid_map") as allow_list:
        with pytest.raises(WorkplaceWifiFallbackRejected) as exc:
            _fallback_clock_in(db, employee, location, observed=WORK_BSSID)
    assert exc.value.detail["code"] == "wifi_fallback_unavailable"
    allow_list.assert_not_called()
    db.add.assert_not_called()
    now = datetime(2026, 10, 24, 9, 0)
    assignment, shift = _assignment(now)
    with (
        patch("app.services.attendance_clock.business_now", return_value=now),
        patch("app.services.attendance_clock._attendance_policy", return_value=_policy()),
        patch("app.services.attendance_clock._active_record", return_value=None),
        patch("app.services.attendance_clock._resolve_assignment", return_value=(assignment, shift)),
        patch("app.services.attendance_clock._existing_assignment_record", return_value=None),
    ):
        clock_in_employee(
            db,
            employee,
            latitude=14.5995,
            longitude=120.9842,
            observed_bssid=OTHER_BSSID,
            location_evidence="wifi",
        )
    assert _added_record(db).wifi_verification_in is None


@patch("app.services.missing_clock_out.ensure_incomplete_for_employee")
@patch("app.services.leave_requests.raise_if_on_approved_leave")
@patch("app.services.attendance_clock._primary_location")
def test_evidence_flag_alone_does_not_authorize(mock_location, _leave, _incomplete):
    location = _location(radius=15)
    mock_location.return_value = location
    db = _clock_db()
    employee = _employee(location.business_id)
    with pytest.raises(HTTPException) as exc:
        _fallback_clock_in(db, employee, location, observed=WORK_BSSID, evidence="gps_unavailable")
    assert exc.value.detail["code"] == "location_required"
    db.add.assert_not_called()
    db.commit.assert_not_called()


def test_radius_20_rejects_wifi_only_time_in_and_time_out():
    from app.services.workplace_wifi import wifi_fallback_radius_allows

    assert wifi_fallback_radius_allows(19.99) is True
    assert wifi_fallback_radius_allows(20) is False
    assert wifi_fallback_radius_allows(20.0) is False
    assert wifi_fallback_radius_allows(21) is False

    location = _location(radius=20)
    employee = _employee(location.business_id)
    record = AttendanceRecord(
        id=uuid.uuid4(),
        business_id=location.business_id,
        employee_id=uuid.uuid4(),
        time_in=datetime.now(timezone.utc),
        status=AttendanceStatus.in_progress,
    )
    db = _clock_db()
    with (
        patch("app.services.attendance_clock._primary_location", return_value=location),
        patch("app.services.missing_clock_out.ensure_incomplete_for_employee"),
        patch("app.services.leave_requests.raise_if_on_approved_leave"),
        patch("app.services.workplace_wifi.enabled_bssid_map") as allow_list,
    ):
        with pytest.raises(WorkplaceWifiFallbackRejected) as exc:
            clock_in_employee(
                db,
                employee,
                observed_bssid=WORK_BSSID,
                location_evidence="wifi",
            )
    assert exc.value.detail["code"] == "wifi_fallback_unavailable"
    allow_list.assert_not_called()
    db.add.assert_not_called()

    db_out = _clock_db()
    with (
        patch("app.services.attendance_clock._primary_location", return_value=location),
        patch("app.services.attendance_clock._active_record", return_value=record),
        patch("app.services.missing_clock_out.raise_if_incomplete_clock_out"),
        patch("app.services.leave_requests.raise_if_on_approved_leave"),
        patch("app.services.workplace_wifi.enabled_bssid_map") as allow_list_out,
    ):
        with pytest.raises(WorkplaceWifiFallbackRejected):
            clock_out_employee(
                db_out,
                employee,
                observed_bssid=WORK_BSSID,
                location_evidence="wifi",
            )
    assert record.time_out is None
    allow_list_out.assert_not_called()
    db_out.commit.assert_not_called()


@patch("app.services.employee_pay.stamp_attendance_completion_pay")
@patch("app.services.attendance_clock._active_record")
@patch("app.services.missing_clock_out.raise_if_incomplete_clock_out")
@patch("app.services.leave_requests.raise_if_on_approved_leave")
@patch("app.services.attendance_clock._primary_location")
def test_clock_out_fallback_failure_skips_payroll_stamp(
    mock_location, _leave, _incomplete, _active, _stamp
):
    location = _location(radius=19)
    mock_location.return_value = location
    record = AttendanceRecord(
        id=uuid.uuid4(),
        business_id=location.business_id,
        employee_id=uuid.uuid4(),
        time_in=datetime.now(timezone.utc),
        status=AttendanceStatus.in_progress,
    )
    _active.return_value = record
    db = _clock_db()
    employee = _employee(location.business_id)
    with patch("app.services.workplace_wifi.enabled_bssid_map", return_value={}):
        with pytest.raises(WorkplaceWifiFallbackRejected):
            clock_out_employee(
                db,
                employee,
                location_evidence="wifi",
                observed_bssid=WORK_BSSID,
            )
    assert record.time_out is None
    _stamp.assert_not_called()
    db.commit.assert_not_called()


@patch("app.services.attendance_clock._active_record")
@patch("app.services.missing_clock_out.raise_if_incomplete_clock_out")
@patch("app.services.leave_requests.raise_if_on_approved_leave")
@patch("app.services.attendance_clock._primary_location")
def test_clock_out_outside_geofence_rejects_matching_bssid(
    mock_location, _leave, _incomplete, _active
):
    location = _location(radius=15)
    mock_location.return_value = location
    record = AttendanceRecord(
        id=uuid.uuid4(),
        business_id=location.business_id,
        employee_id=uuid.uuid4(),
        time_in=datetime.now(timezone.utc),
        status=AttendanceStatus.in_progress,
    )
    _active.return_value = record
    db = _clock_db()
    employee = _employee(location.business_id)
    with patch("app.services.workplace_wifi.enabled_bssid_map") as allow_list:
        with pytest.raises(GeofenceValidationError):
            clock_out_employee(
                db,
                employee,
                latitude=14.70,
                longitude=121.10,
                observed_bssid=WORK_BSSID,
                location_evidence="wifi",
            )
    allow_list.assert_not_called()
    assert record.time_out is None
    db.commit.assert_not_called()


def test_wifi_preflight_does_not_create_a_punch():
    from app.services.attendance_clock import check_wifi_fallback

    location = _location(radius=19)
    employee = _employee(location.business_id)
    business = MagicMock()
    business.is_demo = False
    db = _clock_db()
    with (
        patch("app.services.attendance_clock.load_business_for_employee", return_value=business),
        patch("app.services.attendance_clock._primary_location", return_value=location),
        patch(
            "app.services.workplace_wifi.enabled_bssid_map",
            return_value={WORK_BSSID: uuid.uuid4()},
        ),
    ):
        check_wifi_fallback(db, employee, WORK_BSSID)
    db.add.assert_not_called()
    db.commit.assert_not_called()


def test_gps_only_endpoints_still_require_face(monkeypatch):
    from app.api import employee_mobile as api

    monkeypatch.setattr(api, "_current_employee", lambda db, user: (MagicMock(), MagicMock()))
    with pytest.raises(HTTPException) as clock_in_exc:
        api.clock_in(body=MagicMock(), db=MagicMock(), user=MagicMock())
    assert clock_in_exc.value.detail["code"] == "face_required"
    with pytest.raises(HTTPException) as clock_out_exc:
        api.clock_out(body=MagicMock(), db=MagicMock(), user=MagicMock())
    assert clock_out_exc.value.detail["code"] == "face_required"


def test_assert_wifi_fallback_rejects_another_worksites_bssid():
    location = _location(radius=10)
    db = MagicMock()
    with patch(
        "app.services.workplace_wifi.enabled_bssid_map",
        return_value={OTHER_BSSID: uuid.uuid4()},
    ):
        with pytest.raises(WorkplaceWifiMismatchError):
            assert_wifi_fallback(db, location, WORK_BSSID)
    db.add.assert_not_called()


def test_payroll_modules_do_not_read_wifi_evidence():
    root = Path(__file__).resolve().parents[1] / "app" / "services"
    for name in (
        "payroll_engine.py",
        "payroll_adjustments.py",
        "payroll_snapshot.py",
        "payroll_incomplete_gate.py",
    ):
        text = (root / name).read_text(encoding="utf-8").lower()
        assert "wifi" not in text
    assert WIFI_MATCHED not in {item.value for item in AttendanceStatus}
    assert WIFI_NOT_CONFIGURED not in {item.value for item in AttendanceStatus}
    assert WIFI_UNAVAILABLE not in {item.value for item in AttendanceStatus}
