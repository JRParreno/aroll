import 'package:aroll_mobile/core/face/face_api_errors.dart';
import 'package:aroll_mobile/core/location/employee_location_service.dart';
import 'package:aroll_mobile/core/location/geofence_diagnostics.dart';
import 'package:aroll_mobile/core/location/workplace_wifi.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('a geofence failure log names the rejection and does not claim a save',
      () {
    final line = geofenceFailureDiagnosticLine(
      action: 'time_in',
      worksiteLatitude: 13.2946150,
      worksiteLongitude: 123.4827835,
      radiusM: 6,
      phoneLatitude: 13.2945992,
      phoneLongitude: 123.4827053,
      accuracyM: 12.4,
      distanceM: 8.64,
      gpsFixObtained: true,
      wifiFallbackConsidered: false,
      reason: 'distance 8.6 m > radius 6 m.',
    );
    expect(line, contains('attendance_saved=false'));
    expect(line, isNot(contains('attendance_saved=true')));
    expect(line, contains('action=time_in'));
    expect(line, contains('gps_fix_obtained=true'));
    expect(line, contains('wifi_fallback_considered=false'));
    expect(line, contains('worksite_lat=13.2946150'));
    expect(line, contains('worksite_lng=123.4827835'));
    expect(line, contains('phone_lat=13.2945992'));
    expect(line, contains('phone_lng=123.4827053'));
    expect(line, contains('accuracy_m=12.4'));
    expect(line, contains('distance_m=8.64'));
    expect(line, contains('radius_m=6'));
    expect(line, contains('reason=distance 8.6 m > radius 6 m.'));

    final timeOut = geofenceFailureDiagnosticLine(
      action: 'time_out',
      worksiteLatitude: 13.2946150,
      worksiteLongitude: 123.4827835,
      radiusM: 6,
      gpsFixObtained: false,
      wifiFallbackConsidered: true,
      reason: 'Workplace Wi-Fi could not be confirmed.',
    );
    expect(timeOut, contains('action=time_out'));
    expect(timeOut, contains('gps_fix_obtained=false'));
    expect(timeOut, contains('wifi_fallback_considered=true'));
    expect(timeOut, contains('phone_lat=none'));
    expect(timeOut, contains('accuracy_m=none'));
    expect(timeOut, contains('attendance_saved=false'));
  });

  test('disabled worksite does not read Wi-Fi', () async {
    final reader = _CountingReader(
      const WorkplaceWifiSnapshot(
          status: WorkplaceWifiReadStatus.connected,
          bssid: 'aa:bb:cc:dd:ee:01'),
    );
    final attempt = WorkplaceWifiAttempt(reader);
    final first = await attempt.observedBssid(
        verificationEnabled: false, isAndroid: true);
    final second = await attempt.observedBssid(
        verificationEnabled: false, isAndroid: true);
    expect(first, isNull);
    expect(second, isNull);
    expect(reader.calls, 0);
  });

  test('matching connected BSSID is submitted once across rebuilds', () async {
    final reader = _CountingReader(
      const WorkplaceWifiSnapshot(
        status: WorkplaceWifiReadStatus.connected,
        ssid: 'Cafe',
        bssid: 'AA-BB-CC-DD-EE-01',
      ),
    );
    final attempt = WorkplaceWifiAttempt(reader);
    final first =
        await attempt.observedBssid(verificationEnabled: true, isAndroid: true);
    final second =
        await attempt.observedBssid(verificationEnabled: true, isAndroid: true);
    expect(first, 'aa:bb:cc:dd:ee:01');
    expect(second, first);
    expect(reader.calls, 1);
    expect(attempt.readCount, 1);
  });

  test('a different usable BSSID is still sent for the server to reject',
      () async {
    final value = bssidToSubmit(
      const WorkplaceWifiSnapshot(
        status: WorkplaceWifiReadStatus.connected,
        bssid: '11:22:33:44:55:66',
      ),
    );
    expect(value, '11:22:33:44:55:66');
  });

  test('wifi disabled, hidden, or unreadable is not a mismatch', () {
    for (final status in [
      WorkplaceWifiReadStatus.unavailable,
      WorkplaceWifiReadStatus.notConnected,
      WorkplaceWifiReadStatus.locationDisabled,
      WorkplaceWifiReadStatus.bssidUnavailable,
    ]) {
      expect(bssidToSubmit(WorkplaceWifiSnapshot(status: status)), isNull);
    }
  });

  test('redacted connected BSSID is not treated as disconnected', () {
    final hidden = snapshotFromChannel({
      'status': 'connected',
      'ssid': '<unknown ssid>',
      'bssid': '02:00:00:00:00:00',
    });
    final zero = snapshotFromChannel({
      'status': 'connected',
      'bssid': '00:00:00:00:00:00',
    });
    expect(hidden.status, WorkplaceWifiReadStatus.bssidUnavailable);
    expect(hidden.bssid, isNull);
    expect(zero.status, WorkplaceWifiReadStatus.bssidUnavailable);
    expect(bssidToSubmit(hidden), isNull);
    expect(normalizeBssid('not-a-mac'), isNull);
  });

  test('a missing BSSID keeps a valid RSSI and is not a total failure', () {
    final hidden = snapshotFromChannel({
      'status': 'connected',
      'ssid': 'Cafe',
      'bssid': '02:00:00:00:00:00',
      'rssi_dbm': '-70',
    });
    expect(hidden.status, WorkplaceWifiReadStatus.bssidUnavailable);
    expect(hidden.bssid, isNull);
    expect(hidden.rssiDbm, -70);
    expect(bssidToSubmit(hidden), isNull);
    expect(
      workplaceWifiReadMessage(hidden.status),
      isNot('The connected Wi-Fi could not be read. Try again.'),
    );

    final reported = snapshotFromChannel({
      'status': 'bssid_unavailable',
      'ssid': 'Cafe',
      'rssi_dbm': '-75',
    });
    expect(reported.status, WorkplaceWifiReadStatus.bssidUnavailable);
    expect(reported.rssiDbm, -75);
    expect(
      workplaceWifiReadMessage(reported.status),
      contains('did not share the network address'),
    );

    final locationOff = snapshotFromChannel({
      'status': 'location_disabled',
      'bssid': '02:00:00:00:00:00',
      'rssi_dbm': '-65',
    });
    expect(locationOff.status, WorkplaceWifiReadStatus.locationDisabled);
    expect(locationOff.bssid, isNull);
    expect(locationOff.rssiDbm, -65);
  });

  test(
      'scan results identify the connected access point only when the match is unique',
      () {
    final unique = snapshotFromChannel({
      'status': 'bssid_unavailable',
      'ssid': '"Cafe"',
      'bssid': '02:00:00:00:00:00',
      'rssi_dbm': '-75',
      'scans': [
        {'ssid': 'Cafe', 'bssid': 'AA:BB:CC:DD:EE:10', 'rssi_dbm': '-80'},
        {'ssid': 'Other', 'bssid': 'AA:BB:CC:DD:EE:11', 'rssi_dbm': '-40'},
      ],
    });
    expect(unique.status, WorkplaceWifiReadStatus.connected);
    expect(bssidToSubmit(unique), 'aa:bb:cc:dd:ee:10');
    expect(unique.rssiDbm, -75);

    final sameAddressTwice = reliableConnectedScanMatch(
      connectedSsid: 'Cafe',
      scans: const [
        WifiScanObservation(
            ssid: 'Cafe', bssid: 'AA-BB-CC-DD-EE-10', rssiDbm: -80),
        WifiScanObservation(
            ssid: '"Cafe"', bssid: 'aa:bb:cc:dd:ee:10', rssiDbm: -40),
      ],
    );
    expect(sameAddressTwice?.bssid, 'aa:bb:cc:dd:ee:10');
    expect(sameAddressTwice?.rssiDbm, -40);

    final mesh = snapshotFromChannel({
      'status': 'bssid_unavailable',
      'ssid': 'Cafe',
      'rssi_dbm': '-75',
      'scans': [
        {'ssid': 'Cafe', 'bssid': 'aa:bb:cc:dd:ee:10', 'rssi_dbm': '-80'},
        {'ssid': 'Cafe', 'bssid': 'aa:bb:cc:dd:ee:11', 'rssi_dbm': '-70'},
      ],
    });
    expect(mesh.status, WorkplaceWifiReadStatus.bssidUnavailable);
    expect(mesh.bssid, isNull);
    expect(mesh.rssiDbm, -75);
    expect(bssidToSubmit(mesh), isNull);

    final neighbor = snapshotFromChannel({
      'status': 'bssid_unavailable',
      'ssid': 'Cafe',
      'rssi_dbm': '-70',
      'scans': [
        {'ssid': 'Neighbor', 'bssid': 'aa:bb:cc:dd:ee:22', 'rssi_dbm': '-40'},
      ],
    });
    expect(neighbor.bssid, isNull);
    expect(neighbor.rssiDbm, -70);

    final unknown = snapshotFromChannel({
      'status': 'bssid_unavailable',
      'ssid': '<unknown ssid>',
      'rssi_dbm': '-60',
      'scans': [
        {'ssid': 'Cafe', 'bssid': 'aa:bb:cc:dd:ee:10', 'rssi_dbm': '-60'},
      ],
    });
    expect(unknown.bssid, isNull);
    expect(unknown.rssiDbm, -60);

    final placeholderScan = snapshotFromChannel({
      'status': 'connected',
      'ssid': 'Cafe',
      'scans': [
        {'ssid': 'Cafe', 'bssid': '02:00:00:00:00:00', 'rssi_dbm': '-40'},
        {'ssid': 'Cafe', 'bssid': '00:00:00:00:00:00', 'rssi_dbm': '-40'},
      ],
    });
    expect(placeholderScan.bssid, isNull);
    expect(placeholderScan.status, WorkplaceWifiReadStatus.bssidUnavailable);

    final direct = snapshotFromChannel({
      'status': 'connected',
      'ssid': 'Cafe',
      'bssid': 'aa:bb:cc:dd:ee:01',
      'rssi_dbm': '-50',
      'scans': [
        {'ssid': 'Cafe', 'bssid': 'aa:bb:cc:dd:ee:99', 'rssi_dbm': '-30'},
      ],
    });
    expect(bssidToSubmit(direct), 'aa:bb:cc:dd:ee:01');
    expect(direct.rssiDbm, -50);

    expect(
      reliableConnectedScanMatch(
        connectedSsid: 'Cafe',
        scans: const [
          WifiScanObservation(
              ssid: 'cafe', bssid: 'aa:bb:cc:dd:ee:10', rssiDbm: -40),
        ],
      ),
      isNull,
    );
  });

  test('phones below Android 11 are reported separately', () {
    final snapshot = snapshotFromChannel({'status': 'android_too_old'});
    expect(snapshot.status, WorkplaceWifiReadStatus.androidTooOld);
    expect(snapshot.bssid, isNull);
    expect(bssidToSubmit(snapshot), isNull);
    expect(
      workplaceWifiReadMessage(snapshot.status),
      'This phone must be running Android 11 or later to read the connected Wi-Fi.',
    );
  });

  test('connected RSSI is parsed and an invalid reading is omitted', () {
    final strong = snapshotFromChannel({
      'status': 'connected',
      'bssid': 'aa:bb:cc:dd:ee:01',
      'rssi_dbm': '-45',
    });
    final unknown = snapshotFromChannel({
      'status': 'connected',
      'bssid': 'aa:bb:cc:dd:ee:01',
      'rssi_dbm': '-127',
    });
    final missing = snapshotFromChannel({
      'status': 'connected',
      'bssid': 'aa:bb:cc:dd:ee:01',
    });
    expect(strong.rssiDbm, -45);
    expect(bssidToSubmit(strong), 'aa:bb:cc:dd:ee:01');
    expect(unknown.rssiDbm, isNull);
    expect(missing.rssiDbm, isNull);
    expect(parseRssiDbm(0), isNull);
    expect(rssiMeetsMinimum(observedRssiDbm: -40, minimumRssiDbm: -50), isTrue);
    expect(rssiMeetsMinimum(observedRssiDbm: -50, minimumRssiDbm: -50), isTrue);
    expect(
        rssiMeetsMinimum(observedRssiDbm: -51, minimumRssiDbm: -50), isFalse);
    expect(
        rssiMeetsMinimum(observedRssiDbm: null, minimumRssiDbm: -50), isFalse);
    expect(
        rssiMeetsMinimum(observedRssiDbm: null, minimumRssiDbm: null), isTrue);
    expect(parseConfiguredMinimumRssi(''), isNull);
    expect(parseConfiguredMinimumRssi('-50'), -50);
    expect(configuredMinimumRssiTextIsValid('-19'), isFalse);
    expect(configuredMinimumRssiTextIsValid('-121'), isFalse);
  });

  test('saved RSSI thresholds map to presets, custom values, or off', () {
    expect(rssiThresholdChoiceFromSaved(null).preset, RssiThresholdPreset.off);
    expect(rssiThresholdChoiceFromSaved(-40).preset,
        RssiThresholdPreset.veryStrong);
    expect(
        rssiThresholdChoiceFromSaved(-50).preset, RssiThresholdPreset.strong);
    expect(
        rssiThresholdChoiceFromSaved(-60).preset, RssiThresholdPreset.moderate);
    expect(
        rssiThresholdChoiceFromSaved(-70).preset, RssiThresholdPreset.relaxed);
    final custom = rssiThresholdChoiceFromSaved(-55);
    expect(custom.preset, RssiThresholdPreset.custom);
    expect(custom.customText, '-55');
    expect(rssiThresholdExplanation, contains('registered workplace Wi-Fi'));
    expect(rssiThresholdExplanation, contains('GPS cannot confirm'));
    expect(rssiThresholdExplanation, contains('legitimate employee'));
    expect(rssiThresholdExplanation, contains('exact location'));
  });

  test('RSSI preset and custom selections save the expected value', () {
    expect(rssiThresholdValueToSave(RssiThresholdPreset.off, '-55'), isNull);
    expect(rssiThresholdValueToSave(RssiThresholdPreset.veryStrong, ''), -40);
    expect(rssiThresholdValueToSave(RssiThresholdPreset.strong, ''), -50);
    expect(rssiThresholdValueToSave(RssiThresholdPreset.moderate, ''), -60);
    expect(rssiThresholdValueToSave(RssiThresholdPreset.relaxed, ''), -70);
    expect(rssiThresholdValueToSave(RssiThresholdPreset.custom, ' -55 '), -55);
    expect(rssiThresholdValueToSave(RssiThresholdPreset.custom, '-120'), -120);
    expect(rssiThresholdValueToSave(RssiThresholdPreset.custom, '-20'), -20);
    expect(
      rssiThresholdSelectionIsValid(RssiThresholdPreset.custom, ''),
      isFalse,
    );
    expect(
      rssiThresholdSelectionIsValid(RssiThresholdPreset.custom, '-19'),
      isFalse,
    );
    expect(
      rssiThresholdSelectionIsValid(RssiThresholdPreset.custom, '-121'),
      isFalse,
    );
    expect(
      rssiThresholdSelectionIsValid(RssiThresholdPreset.custom, 'strong'),
      isFalse,
    );
    expect(() => rssiThresholdValueToSave(RssiThresholdPreset.custom, ''),
        throwsFormatException);
  });

  test('channel statuses stay distinct and never invent a BSSID', () {
    final notConnected = snapshotFromChannel({'status': 'not_connected'});
    final locationOff = snapshotFromChannel({
      'status': 'location_disabled',
      'bssid': '02:00:00:00:00:00',
    });
    final redacted = snapshotFromChannel({'status': 'bssid_unavailable'});
    final connected = snapshotFromChannel({
      'status': 'connected',
      'ssid': '"Cafe"',
      'bssid': 'AA:BB:CC:DD:EE:02',
    });
    expect(notConnected.status, WorkplaceWifiReadStatus.notConnected);
    expect(locationOff.status, WorkplaceWifiReadStatus.locationDisabled);
    expect(locationOff.bssid, isNull);
    expect(redacted.status, WorkplaceWifiReadStatus.bssidUnavailable);
    expect(connected.status, WorkplaceWifiReadStatus.connected);
    expect(bssidToSubmit(connected), 'aa:bb:cc:dd:ee:02');
    expect(bssidToSubmit(notConnected), isNull);
    expect(bssidToSubmit(locationOff), isNull);
    expect(bssidToSubmit(redacted), isNull);
  });

  test('registration messages match the failure that was read', () {
    expect(
      workplaceWifiReadMessage(WorkplaceWifiReadStatus.notConnected),
      'Turn on Wi-Fi and join the workplace network, then try again.',
    );
    expect(
      workplaceWifiReadMessage(WorkplaceWifiReadStatus.locationDisabled),
      contains('Turn on location services'),
    );
    expect(
      workplaceWifiReadMessage(WorkplaceWifiReadStatus.locationDisabled),
      isNot(contains('join the workplace network')),
    );
    expect(
      workplaceWifiReadMessage(WorkplaceWifiReadStatus.bssidUnavailable),
      contains('did not share the network address'),
    );
    expect(
      workplaceWifiReadMessage(WorkplaceWifiReadStatus.bssidUnavailable),
      isNot(contains('join the workplace network')),
    );
    expect(
      workplaceWifiReadMessage(WorkplaceWifiReadStatus.connected),
      workplaceWifiReadMessage(WorkplaceWifiReadStatus.bssidUnavailable),
    );
    expect(
      workplaceWifiReadMessage(WorkplaceWifiReadStatus.unavailable),
      'The connected Wi-Fi could not be read. Try again.',
    );
    expect(
      workplaceWifiReadMessage(WorkplaceWifiReadStatus.permissionDenied),
      'Allow location access so this phone can read the connected Wi-Fi.',
    );
    expect(
      workplaceWifiReadMessage(WorkplaceWifiReadStatus.unsupported),
      workplaceWifiAndroidOnlyMessage,
    );
  });

  test('permission denied does not invent a BSSID', () {
    final snapshot = snapshotFromChannel({'status': 'permission_denied'});
    expect(snapshot.status, WorkplaceWifiReadStatus.permissionDenied);
    expect(bssidToSubmit(snapshot), isNull);
  });

  test('platform exceptions become unavailable', () async {
    final attempt = WorkplaceWifiAttempt(_ThrowingReader());
    final value =
        await attempt.observedBssid(verificationEnabled: true, isAndroid: true);
    expect(value, isNull);
  });

  test('iOS and unsupported platforms skip the read', () async {
    final reader = _CountingReader(
      const WorkplaceWifiSnapshot(
          status: WorkplaceWifiReadStatus.connected,
          bssid: 'aa:bb:cc:dd:ee:01'),
    );
    final attempt = WorkplaceWifiAttempt(reader);
    final value = await attempt.observedBssid(
        verificationEnabled: true, isAndroid: false);
    expect(value, isNull);
    expect(reader.calls, 0);
    expect(
      bssidToSubmit(const WorkplaceWifiSnapshot(
          status: WorkplaceWifiReadStatus.unsupported)),
      isNull,
    );
  });

  test('GPS rejection stays authoritative', () {
    expect(
      gpsAllowsAttendanceAttempt(
          insideGeofence: false, needsBetterGps: false, mocked: false),
      isFalse,
    );
    expect(
      gpsAllowsAttendanceAttempt(
          insideGeofence: true, needsBetterGps: true, mocked: false),
      isFalse,
    );
    expect(
      gpsAllowsAttendanceAttempt(
          insideGeofence: true, needsBetterGps: false, mocked: true),
      isFalse,
    );
  });

  test('Wi-Fi mismatch asks the employee to retry and is not a success', () {
    final error = DioException(
      requestOptions:
          RequestOptions(path: '/employee/attendance/clock-in-face'),
      response: Response(
        requestOptions:
            RequestOptions(path: '/employee/attendance/clock-in-face'),
        statusCode: 409,
        data: {
          'detail': {
            'code': 'workplace_wifi_mismatch',
            'message':
                'Connect to the workplace Wi-Fi registered by your employer, then try again.',
          },
        },
      ),
    );
    expect(
      faceApiErrorMessage(error, fallback: 'failed'),
      'Connect to the workplace Wi-Fi registered by your employer, then try again.',
    );
  });

  test('a 6 m preview rejects 10 m even when accuracy is wide', () {
    const centerLat = 14.5995;
    const centerLng = 120.9842;
    final tenMetersNorth = centerLat + (10 / 111320);
    final outside = EmployeeLocationService().preview(
      device: EmployeeLocationSnapshot(
        latitude: tenMetersNorth,
        longitude: centerLng,
        accuracyM: 30,
      ),
      centerLatitude: centerLat,
      centerLongitude: centerLng,
      radiusM: 6,
    );
    final fiveMetersNorth = centerLat + (5 / 111320);
    final inside = EmployeeLocationService().preview(
      device: EmployeeLocationSnapshot(
        latitude: fiveMetersNorth,
        longitude: centerLng,
        accuracyM: 30,
      ),
      centerLatitude: centerLat,
      centerLongitude: centerLng,
      radiusM: 6,
    );
    expect(outside.distanceM, greaterThan(6));
    expect(outside.distanceM, lessThan(12));
    expect(outside.insideGeofence, isFalse);
    expect(outside.needsBetterGps, isFalse);
    expect(inside.distanceM, lessThan(6));
    expect(inside.insideGeofence, isTrue);
  });

  test('GPS inside does not ask for a Wi-Fi fallback', () {
    final underTwenty = decideAttendanceLocation(
      demo: false,
      radiusM: 19.99,
      mocked: false,
      permissionDenied: false,
      locationServicesDisabled: false,
      gpsFixAvailable: true,
      insideGeofence: true,
      needsBetterGps: false,
    );
    final atTwenty = decideAttendanceLocation(
      demo: false,
      radiusM: 20,
      mocked: false,
      permissionDenied: false,
      locationServicesDisabled: false,
      gpsFixAvailable: true,
      insideGeofence: true,
      needsBetterGps: false,
    );
    expect(underTwenty.route, AttendanceLocationRoute.gpsInside);
    expect(atTwenty.route, AttendanceLocationRoute.gpsInside);
    final gps = attendancePayloadForChoice(
      choice: AttendanceLocationChoice.gps,
      latitude: 13.2946,
      longitude: 123.4828,
      observedBssid: 'aa:bb:cc:dd:ee:01',
    );
    expect(gps.submit, isTrue);
    expect(gps.latitude, 13.2946);
    expect(gps.longitude, 123.4828);
    expect(gps.observedBssid, isNull);
    expect(gps.locationEvidence, 'gps');
  });

  test('outside and missing fixes under 20 m offer Wi-Fi, and 20 m does not',
      () {
    final outside = decideAttendanceLocation(
      demo: false,
      radiusM: 8,
      mocked: false,
      permissionDenied: false,
      locationServicesDisabled: false,
      gpsFixAvailable: true,
      insideGeofence: false,
      needsBetterGps: false,
    );
    final weakOutside = decideAttendanceLocation(
      demo: false,
      radiusM: 6,
      mocked: false,
      permissionDenied: false,
      locationServicesDisabled: false,
      gpsFixAvailable: true,
      insideGeofence: false,
      needsBetterGps: true,
    );
    final missing = decideAttendanceLocation(
      demo: false,
      radiusM: 19.99,
      mocked: false,
      permissionDenied: false,
      locationServicesDisabled: false,
      gpsFixAvailable: false,
      insideGeofence: false,
      needsBetterGps: false,
    );
    final atTwenty = decideAttendanceLocation(
      demo: false,
      radiusM: 20,
      mocked: false,
      permissionDenied: false,
      locationServicesDisabled: false,
      gpsFixAvailable: false,
      insideGeofence: false,
      needsBetterGps: false,
    );
    final outsideAtTwenty = decideAttendanceLocation(
      demo: false,
      radiusM: 20,
      mocked: false,
      permissionDenied: false,
      locationServicesDisabled: false,
      gpsFixAvailable: true,
      insideGeofence: false,
      needsBetterGps: false,
    );
    expect(outside.route, AttendanceLocationRoute.wifiFallback);
    expect(weakOutside.route, AttendanceLocationRoute.wifiFallback);
    expect(missing.route, AttendanceLocationRoute.wifiFallback);
    expect(atTwenty.route, AttendanceLocationRoute.blocked);
    expect(atTwenty.message, gpsUnavailableNoWifiMessage);
    expect(outsideAtTwenty.route, AttendanceLocationRoute.gpsOutside);
    expect(wifiFallbackRadiusAllows(19.99), isTrue);
    expect(wifiFallbackRadiusAllows(20), isFalse);
    expect(wifiFallbackRadiusAllows(21), isFalse);
  });

  test('Yes omits coordinates and No submits nothing', () {
    final yes = attendancePayloadForChoice(
      choice: attendanceChoiceAfterFallback(accepted: true),
      latitude: 13.2947,
      longitude: 123.4827,
      observedBssid: 'aa:bb:cc:dd:ee:01',
    );
    final no = attendancePayloadForChoice(
      choice: attendanceChoiceAfterFallback(accepted: false),
      latitude: 13.2947,
      longitude: 123.4827,
      observedBssid: 'aa:bb:cc:dd:ee:01',
    );
    final nextAttempt = attendancePayloadForChoice(
      choice: AttendanceLocationChoice.gps,
      latitude: 13.2946,
      longitude: 123.4828,
    );
    expect(yes.submit, isTrue);
    expect(yes.latitude, isNull);
    expect(yes.longitude, isNull);
    expect(yes.observedBssid, 'aa:bb:cc:dd:ee:01');
    expect(yes.locationEvidence, 'wifi');
    expect(no.submit, isFalse);
    expect(no.latitude, isNull);
    expect(no.observedBssid, isNull);
    expect(nextAttempt.latitude, 13.2946);
    expect(nextAttempt.observedBssid, isNull);
    expect(nextAttempt.locationEvidence, 'gps');
  });

  test('permission and location services do not pretend Wi-Fi can be read', () {
    final deniedAtTwenty = decideAttendanceLocation(
      demo: false,
      radiusM: 20,
      mocked: false,
      permissionDenied: true,
      locationServicesDisabled: false,
      gpsFixAvailable: false,
      insideGeofence: false,
      needsBetterGps: false,
    );
    final servicesOffAtTwenty = decideAttendanceLocation(
      demo: false,
      radiusM: 20,
      mocked: false,
      permissionDenied: false,
      locationServicesDisabled: true,
      gpsFixAvailable: false,
      insideGeofence: false,
      needsBetterGps: false,
    );
    final deniedUnderTwenty = decideAttendanceLocation(
      demo: false,
      radiusM: 8,
      mocked: false,
      permissionDenied: true,
      locationServicesDisabled: false,
      gpsFixAvailable: false,
      insideGeofence: false,
      needsBetterGps: false,
    );
    expect(deniedAtTwenty.route, AttendanceLocationRoute.blocked);
    expect(deniedAtTwenty.message, gpsPermissionBlockedMessage);
    expect(servicesOffAtTwenty.message, gpsServicesBlockedMessage);
    expect(deniedUnderTwenty.route, AttendanceLocationRoute.wifiFallback);
    expect(
      workplaceWifiReadMessage(WorkplaceWifiReadStatus.permissionDenied),
      contains('Allow location access'),
    );
    expect(
      workplaceWifiReadMessage(WorkplaceWifiReadStatus.locationDisabled),
      contains('location services'),
    );
    expect(
      bssidToSubmit(
        const WorkplaceWifiSnapshot(
            status: WorkplaceWifiReadStatus.permissionDenied),
      ),
      isNull,
    );
  });

  test('demo and mocked fixes do not enter the Wi-Fi fallback', () {
    final demo = decideAttendanceLocation(
      demo: true,
      radiusM: 10,
      mocked: false,
      permissionDenied: false,
      locationServicesDisabled: false,
      gpsFixAvailable: false,
      insideGeofence: false,
      needsBetterGps: false,
    );
    final mocked = decideAttendanceLocation(
      demo: false,
      radiusM: 10,
      mocked: true,
      permissionDenied: false,
      locationServicesDisabled: false,
      gpsFixAvailable: true,
      insideGeofence: true,
      needsBetterGps: false,
    );
    expect(demo.route, AttendanceLocationRoute.blocked);
    expect(mocked.route, AttendanceLocationRoute.blocked);
    expect(mocked.message, mockLocationBlockedMessage);
  });

  test('existing GPS rejection copy is unchanged', () {
    final error = DioException(
      requestOptions:
          RequestOptions(path: '/employee/attendance/clock-in-face'),
      response: Response(
        requestOptions:
            RequestOptions(path: '/employee/attendance/clock-in-face'),
        statusCode: 403,
        data: {
          'detail': {'code': 'outside_geofence', 'message': 'outside'},
        },
      ),
    );
    expect(
      faceApiErrorMessage(error, fallback: 'failed'),
      contains('outside your workplace'),
    );
  });
}

class _CountingReader implements WorkplaceWifiReader {
  _CountingReader(this.snapshot);
  final WorkplaceWifiSnapshot snapshot;
  int calls = 0;

  @override
  Future<WorkplaceWifiSnapshot> readConnected() async {
    calls += 1;
    return snapshot;
  }
}

class _ThrowingReader implements WorkplaceWifiReader {
  @override
  Future<WorkplaceWifiSnapshot> readConnected() async {
    throw StateError('channel failed');
  }
}
