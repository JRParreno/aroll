import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';

/// Temporary development log for a geofence rejection.
///
/// Release builds emit nothing. The line is for a device test and is not
/// shown in the attendance screen. `attendance_saved=false` means no punch
/// was written by this rejection.
String geofenceFailureDiagnosticLine({
  required String action,
  required double worksiteLatitude,
  required double worksiteLongitude,
  required double radiusM,
  double? phoneLatitude,
  double? phoneLongitude,
  double? accuracyM,
  double? distanceM,
  required bool gpsFixObtained,
  required bool wifiFallbackConsidered,
  required String reason,
}) {
  String coord(double? value) =>
      value == null ? 'none' : value.toStringAsFixed(7);
  String meters(double? value, int digits) =>
      value == null ? 'none' : value.toStringAsFixed(digits);
  final compactReason = reason.replaceAll(RegExp(r'\s+'), ' ').trim();
  return 'GEOFENCE_DIAGNOSTIC attendance_saved=false '
      'action=$action '
      'gps_fix_obtained=$gpsFixObtained '
      'wifi_fallback_considered=$wifiFallbackConsidered '
      'worksite_lat=${coord(worksiteLatitude)} '
      'worksite_lng=${coord(worksiteLongitude)} '
      'phone_lat=${coord(phoneLatitude)} '
      'phone_lng=${coord(phoneLongitude)} '
      'accuracy_m=${meters(accuracyM, 1)} '
      'distance_m=${meters(distanceM, 2)} '
      'radius_m=${meters(radiusM, 0)} '
      'reason=$compactReason';
}

void logGeofenceFailureDiagnostic({
  required String action,
  required double worksiteLatitude,
  required double worksiteLongitude,
  required double radiusM,
  double? phoneLatitude,
  double? phoneLongitude,
  double? accuracyM,
  double? distanceM,
  required bool gpsFixObtained,
  required bool wifiFallbackConsidered,
  required String reason,
}) {
  if (kReleaseMode) return;
  final line = geofenceFailureDiagnosticLine(
    action: action,
    worksiteLatitude: worksiteLatitude,
    worksiteLongitude: worksiteLongitude,
    radiusM: radiusM,
    phoneLatitude: phoneLatitude,
    phoneLongitude: phoneLongitude,
    accuracyM: accuracyM,
    distanceM: distanceM,
    gpsFixObtained: gpsFixObtained,
    wifiFallbackConsidered: wifiFallbackConsidered,
    reason: reason,
  );
  developer.log(line, name: 'aroll.geofence.diagnostic');
  // developer.log stays on the VM service. debugPrint is what adb logcat shows.
  debugPrint(line);
}
