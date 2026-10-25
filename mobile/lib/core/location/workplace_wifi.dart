import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';

/// Wi-Fi fallback is offered only below 20 m. Exactly 20 m stays GPS-only.
///
/// The 20 m small-fence helper remains "20 m or less" for GPS sampling and
/// owner tips. This check is stricter.
bool wifiFallbackRadiusAllows(num radiusM) => radiusM < 20;

/// Android's unknown connected-network RSSI. Not a real signal strength.
const invalidRssiDbm = -127;
const minConfigurableRssiDbm = -120;
const maxConfigurableRssiDbm = -20;
const suggestedMinimumRssiDbm = -50;

/// A live dBm reading. Unknown, missing, and non-negative values are unusable.
int? parseRssiDbm(Object? raw) {
  if (raw == null) return null;
  final value = raw is int ? raw : int.tryParse(raw.toString().trim());
  if (value == null || value >= 0 || value <= invalidRssiDbm) return null;
  return value;
}

enum RssiThresholdPreset { off, veryStrong, strong, moderate, relaxed, custom }

class RssiThresholdOption {
  const RssiThresholdOption(this.preset, this.label, this.dbm);

  final RssiThresholdPreset preset;
  final String label;
  final int? dbm;
}

const rssiThresholdOptions = <RssiThresholdOption>[
  RssiThresholdOption(
    RssiThresholdPreset.off,
    'Off — saved Wi-Fi address only',
    null,
  ),
  RssiThresholdOption(
    RssiThresholdPreset.veryStrong,
    'Very strong (−40 dBm)',
    -40,
  ),
  RssiThresholdOption(RssiThresholdPreset.strong, 'Strong (−50 dBm)', -50),
  RssiThresholdOption(RssiThresholdPreset.moderate, 'Moderate (−60 dBm)', -60),
  RssiThresholdOption(RssiThresholdPreset.relaxed, 'Relaxed (−70 dBm)', -70),
  RssiThresholdOption(RssiThresholdPreset.custom, 'Custom value', null),
];

const rssiThresholdExplanation =
    'The employee must be connected to the registered workplace Wi-Fi. '
    'When GPS cannot confirm the work area, the signal must meet the minimum you choose. '
    'A stronger requirement can reject a legitimate employee whose phone receives a weaker signal. '
    'Signal strength does not prove the employee’s exact location.';

class RssiThresholdChoice {
  const RssiThresholdChoice({required this.preset, required this.customText});

  final RssiThresholdPreset preset;
  final String customText;
}

RssiThresholdChoice rssiThresholdChoiceFromSaved(int? value) {
  if (value == null) {
    return const RssiThresholdChoice(
      preset: RssiThresholdPreset.off,
      customText: '',
    );
  }
  for (final option in rssiThresholdOptions) {
    if (option.preset == RssiThresholdPreset.off ||
        option.preset == RssiThresholdPreset.custom) {
      continue;
    }
    if (option.dbm == value) {
      return RssiThresholdChoice(preset: option.preset, customText: '');
    }
  }
  return RssiThresholdChoice(
    preset: RssiThresholdPreset.custom,
    customText: '$value',
  );
}

/// Off saves null. A named preset saves its dBm. Custom must be a whole number in range.
int? rssiThresholdValueToSave(RssiThresholdPreset preset, String customText) {
  if (preset == RssiThresholdPreset.off) return null;
  if (preset != RssiThresholdPreset.custom) {
    for (final option in rssiThresholdOptions) {
      if (option.preset == preset) return option.dbm;
    }
  }
  final parsed = parseConfiguredMinimumRssi(customText);
  if (parsed == null) {
    throw const FormatException('Enter a whole number from -120 to -20 dBm.');
  }
  return parsed;
}

bool rssiThresholdSelectionIsValid(
    RssiThresholdPreset preset, String customText) {
  try {
    rssiThresholdValueToSave(preset, customText);
    return true;
  } on FormatException {
    return false;
  }
}

String rssiThresholdStatus(int? value) {
  if (value == null) return 'Signal-strength check: off';
  final choice = rssiThresholdChoiceFromSaved(value);
  if (choice.preset == RssiThresholdPreset.custom) {
    return 'Signal-strength check: on, custom minimum $value dBm';
  }
  final label = rssiThresholdOptions
      .firstWhere((option) => option.preset == choice.preset)
      .label;
  return 'Signal-strength check: on, $label';
}

/// Empty input clears the floor. Other text must be a whole number in range.
int? parseConfiguredMinimumRssi(String raw) {
  final text = raw.trim();
  if (text.isEmpty) return null;
  final value = int.tryParse(text);
  if (value == null ||
      value < minConfigurableRssiDbm ||
      value > maxConfigurableRssiDbm) {
    throw const FormatException('Enter a whole number from -120 to -20 dBm.');
  }
  return value;
}

bool configuredMinimumRssiTextIsValid(String raw) {
  try {
    parseConfiguredMinimumRssi(raw);
    return true;
  } on FormatException {
    return false;
  }
}

/// Null minimum keeps BSSID-only fallback. A configured floor needs a usable reading.
bool rssiMeetsMinimum({
  required int? observedRssiDbm,
  required int? minimumRssiDbm,
}) {
  if (minimumRssiDbm == null) return true;
  final observed = observedRssiDbm;
  if (observed == null) return false;
  return observed >= minimumRssiDbm;
}

const wifiRssiUnavailableMessage =
    'The phone could not read the workplace Wi-Fi signal strength. '
    'Move closer to the access point and try again.';

const wifiRssiWeakMessage = 'The workplace Wi-Fi signal is too weak. '
    'Move closer to the access point and try again.';

/// Connected access point only. This is not a location measurement.
enum WorkplaceWifiReadStatus {
  connected,
  notConnected,
  locationDisabled,
  bssidUnavailable,
  unavailable,
  permissionDenied,
  unsupported,
  androidTooOld,
}

const workplaceWifiAndroidOnlyMessage =
    'New access points are registered from the Aroll+ Android app while the phone is connected to that network.';

/// Owner-facing explanation for a registration read that did not produce a BSSID.
String workplaceWifiReadMessage(WorkplaceWifiReadStatus status) {
  switch (status) {
    case WorkplaceWifiReadStatus.permissionDenied:
      return 'Allow location access so this phone can read the connected Wi-Fi.';
    case WorkplaceWifiReadStatus.unsupported:
      return workplaceWifiAndroidOnlyMessage;
    case WorkplaceWifiReadStatus.androidTooOld:
      return 'This phone must be running Android 11 or later to read the connected Wi-Fi.';
    case WorkplaceWifiReadStatus.notConnected:
      return 'Turn on Wi-Fi and join the workplace network, then try again.';
    case WorkplaceWifiReadStatus.locationDisabled:
      return 'Turn on location services. Android hides the connected Wi-Fi address until location is on.';
    case WorkplaceWifiReadStatus.bssidUnavailable:
    case WorkplaceWifiReadStatus.connected:
      return 'This phone is connected to Wi-Fi, but Android did not share the network address. Try again.';
    case WorkplaceWifiReadStatus.unavailable:
      return 'The connected Wi-Fi could not be read. Try again.';
  }
}

class WorkplaceWifiSnapshot {
  const WorkplaceWifiSnapshot({
    required this.status,
    this.ssid,
    this.bssid,
    this.rssiDbm,
  });

  final WorkplaceWifiReadStatus status;
  final String? ssid;
  final String? bssid;
  final int? rssiDbm;
}

abstract class WorkplaceWifiReader {
  Future<WorkplaceWifiSnapshot> readConnected();
}

/// One foreground read of the network the phone is already joined to.
class PlatformWorkplaceWifiReader implements WorkplaceWifiReader {
  PlatformWorkplaceWifiReader({
    MethodChannel? channel,
    bool? isAndroid,
  })  : _channel = channel ?? const MethodChannel('aroll/workplace_wifi'),
        _isAndroid = isAndroid;

  final MethodChannel _channel;
  final bool? _isAndroid;

  @override
  Future<WorkplaceWifiSnapshot> readConnected() async {
    if (!(_isAndroid ?? Platform.isAndroid)) {
      return const WorkplaceWifiSnapshot(
        status: WorkplaceWifiReadStatus.unsupported,
      );
    }
    try {
      final raw = await _channel
          .invokeMapMethod<Object?, Object?>('readConnected')
          .timeout(const Duration(seconds: 8));
      return snapshotFromChannel(raw);
    } on TimeoutException {
      return const WorkplaceWifiSnapshot(
        status: WorkplaceWifiReadStatus.unavailable,
      );
    } on PlatformException {
      return const WorkplaceWifiSnapshot(
        status: WorkplaceWifiReadStatus.unavailable,
      );
    } catch (_) {
      return const WorkplaceWifiSnapshot(
        status: WorkplaceWifiReadStatus.unavailable,
      );
    }
  }
}

/// Remembers a single read so widget rebuilds do not ask again.
class WorkplaceWifiAttempt {
  WorkplaceWifiAttempt(this.reader);

  final WorkplaceWifiReader reader;
  Future<WorkplaceWifiSnapshot>? _pending;
  int readCount = 0;

  Future<String?> observedBssid({
    required bool verificationEnabled,
    required bool isAndroid,
  }) async {
    if (!verificationEnabled || !isAndroid) return null;
    _pending ??= _readOnce();
    final snapshot = await _pending!;
    return bssidToSubmit(snapshot);
  }

  Future<WorkplaceWifiSnapshot> _readOnce() async {
    readCount += 1;
    try {
      return await reader.readConnected();
    } catch (_) {
      return const WorkplaceWifiSnapshot(
        status: WorkplaceWifiReadStatus.unavailable,
      );
    }
  }
}

String? normalizeBssid(String? value) {
  if (value == null) return null;
  final text = value.trim().toLowerCase().replaceAll('-', ':');
  if (text.isEmpty || text.contains('unknown') || text.startsWith('<')) {
    return null;
  }
  final parts = text.split(':');
  if (parts.length != 6) return null;
  final octets = <int>[];
  for (final part in parts) {
    if (part.isEmpty || part.length > 2) return null;
    final octet = int.tryParse(part, radix: 16);
    if (octet == null || octet < 0 || octet > 255) return null;
    octets.add(octet);
  }
  final normalized =
      octets.map((octet) => octet.toRadixString(16).padLeft(2, '0')).join(':');
  if (normalized == '00:00:00:00:00:00' || normalized == '02:00:00:00:00:00') {
    return null;
  }
  return normalized;
}

/// One already-cached scan row. Used only to recognize the joined network.
class WifiScanObservation {
  const WifiScanObservation({this.ssid, this.bssid, this.rssiDbm});

  final String? ssid;
  final String? bssid;
  final int? rssiDbm;
}

class ReliableWifiScanMatch {
  const ReliableWifiScanMatch({required this.bssid, this.rssiDbm});

  final String bssid;
  final int? rssiDbm;
}

String? normalizeWifiSsid(String? raw) {
  if (raw == null) return null;
  var ssid = raw.trim();
  if (ssid.length >= 2 && ssid.startsWith('"') && ssid.endsWith('"')) {
    ssid = ssid.substring(1, ssid.length - 1);
  }
  if (ssid.trim().isEmpty || ssid.toLowerCase() == '<unknown ssid>') {
    return null;
  }
  return ssid;
}

/// The joined network name must match exactly one real access-point address.
///
/// Keep this rule aligned with `ConnectedWifiReader.reliableScanMatch`.
ReliableWifiScanMatch? reliableConnectedScanMatch({
  required String? connectedSsid,
  required List<WifiScanObservation> scans,
}) {
  final ssid = normalizeWifiSsid(connectedSsid);
  if (ssid == null) return null;
  final byBssid = <String, int?>{};
  for (final scan in scans) {
    if (normalizeWifiSsid(scan.ssid) != ssid) continue;
    final bssid = normalizeBssid(scan.bssid);
    if (bssid == null) continue;
    final rssi = scan.rssiDbm;
    final usable =
        (rssi != null && rssi < 0 && rssi > invalidRssiDbm) ? rssi : null;
    final previous = byBssid[bssid];
    if (!byBssid.containsKey(bssid) ||
        (usable != null && (previous == null || usable > previous))) {
      byBssid[bssid] = usable;
    }
  }
  if (byBssid.length != 1) return null;
  final match = byBssid.entries.single;
  return ReliableWifiScanMatch(bssid: match.key, rssiDbm: match.value);
}

List<WifiScanObservation> wifiScansFromChannel(Object? raw) {
  if (raw is! List) return const [];
  final scans = <WifiScanObservation>[];
  for (final item in raw) {
    if (item is! Map) continue;
    scans.add(
      WifiScanObservation(
        ssid: item['ssid']?.toString(),
        bssid: item['bssid']?.toString(),
        rssiDbm: parseRssiDbm(item['rssi_dbm']),
      ),
    );
  }
  return scans;
}

WorkplaceWifiSnapshot snapshotFromChannel(Map<Object?, Object?>? raw) {
  final statusName = raw?['status']?.toString();
  var status = switch (statusName) {
    'connected' => WorkplaceWifiReadStatus.connected,
    'not_connected' => WorkplaceWifiReadStatus.notConnected,
    'location_disabled' => WorkplaceWifiReadStatus.locationDisabled,
    'bssid_unavailable' => WorkplaceWifiReadStatus.bssidUnavailable,
    'permission_denied' => WorkplaceWifiReadStatus.permissionDenied,
    'unsupported' => WorkplaceWifiReadStatus.unsupported,
    'android_too_old' => WorkplaceWifiReadStatus.androidTooOld,
    _ => WorkplaceWifiReadStatus.unavailable,
  };
  final ssid = normalizeWifiSsid(raw?['ssid']?.toString());
  var bssid = normalizeBssid(raw?['bssid']?.toString());
  var rssiDbm = parseRssiDbm(raw?['rssi_dbm']);
  final mayMatchScan = status == WorkplaceWifiReadStatus.connected ||
      status == WorkplaceWifiReadStatus.bssidUnavailable;
  if (bssid == null && mayMatchScan) {
    final match = reliableConnectedScanMatch(
      connectedSsid: ssid,
      scans: wifiScansFromChannel(raw?['scans']),
    );
    if (match != null) {
      bssid = match.bssid;
      rssiDbm ??= match.rssiDbm;
      status = WorkplaceWifiReadStatus.connected;
    }
  }
  if (status == WorkplaceWifiReadStatus.connected && bssid == null) {
    status = WorkplaceWifiReadStatus.bssidUnavailable;
  }
  return WorkplaceWifiSnapshot(
    status: status,
    ssid: ssid,
    bssid: status == WorkplaceWifiReadStatus.connected ? bssid : null,
    rssiDbm: rssiDbm,
  );
}

/// Usable connected BSSID to send. Unavailable is omitted, not treated as a mismatch.
String? bssidToSubmit(WorkplaceWifiSnapshot snapshot) {
  if (snapshot.status != WorkplaceWifiReadStatus.connected) return null;
  return normalizeBssid(snapshot.bssid);
}

/// GPS preview still decides whether a punch may be attempted.
bool gpsAllowsAttendanceAttempt({
  required bool insideGeofence,
  required bool needsBetterGps,
  required bool mocked,
}) {
  return insideGeofence && !needsBetterGps && !mocked;
}

enum AttendanceLocationRoute { gpsInside, gpsOutside, wifiFallback, blocked }

class AttendanceLocationDecision {
  const AttendanceLocationDecision(this.route, {this.message});

  final AttendanceLocationRoute route;
  final String? message;
}

const gpsPermissionBlockedMessage =
    'Please allow location access so we can confirm you’re at your workplace.';

const gpsServicesBlockedMessage =
    'Please turn on location so we can confirm you’re at work.';

const gpsUnavailableNoWifiMessage =
    'We couldn’t confirm your workplace location. Move into the work area and try again.';

const wifiNotConfiguredAttendanceMessage =
    'Location isn’t accurate enough, and workplace Wi-Fi is not set up as a backup. '
    'Move into the work area and try again.';

const mockLocationBlockedMessage =
    'Location spoofing isn’t allowed. Please turn off any fake GPS apps and try again.';

/// GPS inside never asks for Wi-Fi. Under 20 m, an outside fix or a missing
/// fix can offer Wi-Fi after the employee agrees. At 20 m or more, GPS stands.
AttendanceLocationDecision decideAttendanceLocation({
  required bool demo,
  required double radiusM,
  required bool mocked,
  required bool permissionDenied,
  required bool locationServicesDisabled,
  required bool gpsFixAvailable,
  required bool insideGeofence,
  required bool needsBetterGps,
}) {
  if (demo) {
    return const AttendanceLocationDecision(AttendanceLocationRoute.blocked);
  }
  if (mocked) {
    return const AttendanceLocationDecision(
      AttendanceLocationRoute.blocked,
      message: mockLocationBlockedMessage,
    );
  }
  if (gpsFixAvailable && insideGeofence) {
    return const AttendanceLocationDecision(AttendanceLocationRoute.gpsInside);
  }
  // A weak or outside fix still has a position. Under 20 m the employee may
  // choose Wi-Fi. needsBetterGps must not treat that fix as inside.
  final outsideOrMissing =
      !gpsFixAvailable || !insideGeofence || needsBetterGps;
  if (wifiFallbackRadiusAllows(radiusM) && outsideOrMissing) {
    return const AttendanceLocationDecision(
        AttendanceLocationRoute.wifiFallback);
  }
  if (gpsFixAvailable) {
    return const AttendanceLocationDecision(AttendanceLocationRoute.gpsOutside);
  }
  if (permissionDenied) {
    return const AttendanceLocationDecision(
      AttendanceLocationRoute.blocked,
      message: gpsPermissionBlockedMessage,
    );
  }
  if (locationServicesDisabled) {
    return const AttendanceLocationDecision(
      AttendanceLocationRoute.blocked,
      message: gpsServicesBlockedMessage,
    );
  }
  return const AttendanceLocationDecision(
    AttendanceLocationRoute.blocked,
    message: gpsUnavailableNoWifiMessage,
  );
}

enum AttendanceLocationChoice { gps, wifiOmitCoordinates, cancelled }

/// What the attendance request should send after the employee answers.
AttendanceLocationChoice attendanceChoiceAfterFallback(
    {required bool accepted}) {
  if (!accepted) return AttendanceLocationChoice.cancelled;
  return AttendanceLocationChoice.wifiOmitCoordinates;
}

class AttendanceLocationPayload {
  const AttendanceLocationPayload({
    required this.submit,
    this.latitude,
    this.longitude,
    this.observedBssid,
    required this.locationEvidence,
  });

  final bool submit;
  final double? latitude;
  final double? longitude;
  final String? observedBssid;
  final String locationEvidence;
}

AttendanceLocationPayload attendancePayloadForChoice({
  required AttendanceLocationChoice choice,
  double? latitude,
  double? longitude,
  String? observedBssid,
}) {
  switch (choice) {
    case AttendanceLocationChoice.cancelled:
      return const AttendanceLocationPayload(
        submit: false,
        locationEvidence: 'cancelled',
      );
    case AttendanceLocationChoice.wifiOmitCoordinates:
      return AttendanceLocationPayload(
        submit: true,
        observedBssid: observedBssid,
        locationEvidence: 'wifi',
      );
    case AttendanceLocationChoice.gps:
      return AttendanceLocationPayload(
        submit: true,
        latitude: latitude,
        longitude: longitude,
        locationEvidence: 'gps',
      );
  }
}
