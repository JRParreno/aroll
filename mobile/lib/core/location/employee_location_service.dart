import 'dart:async';
import 'dart:developer' as developer;
import 'dart:io' show Platform;
import 'dart:math' as math;

import 'package:aroll_mobile/core/location/business_location_defaults.dart';
import 'package:aroll_mobile/core/location/geofence_utils.dart';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

class EmployeeLocationSnapshot {
  const EmployeeLocationSnapshot({
    required this.latitude,
    required this.longitude,
    required this.accuracyM,
    this.sampleCount = 1,
    this.isMocked = false,
  });

  final double latitude;
  final double longitude;
  final double accuracyM;
  final int sampleCount;
  final bool isMocked;
}

class LocationMockException implements Exception {
  const LocationMockException([
    this.message =
        'Location spoofing isn’t allowed. Please turn off any fake GPS apps and try again.',
  ]);
  final String message;

  @override
  String toString() => message;
}

class GeofencePreview {
  const GeofencePreview({
    required this.distanceM,
    required this.allowedRadiusM,
    required this.insideGeofence,
    required this.businessLatitude,
    required this.businessLongitude,
    required this.employeeLatitude,
    required this.employeeLongitude,
    required this.accuracyM,
    this.toleranceM = 0,
    this.needsBetterGps = false,
    this.failReason,
  });

  final double distanceM;
  final double allowedRadiusM;
  final bool insideGeofence;
  final double businessLatitude;
  final double businessLongitude;
  final double employeeLatitude;
  final double employeeLongitude;
  final double accuracyM;
  final double toleranceM;
  final bool needsBetterGps;
  final String? failReason;
}

class EmployeeLocationService {
  static const double distanceEpsilonM = 0.05;

  /// Max meters of GPS uncertainty used when deciding overlap with the fence.
  static const double maxAccuracyToleranceM = 12;

  static const int targetSampleCount = 5;
  static const int smallRadiusSampleCount = 7;
  static const int minSampleCount = 3;
  static const double preferredAccuracyM = 12;
  static const double smallRadiusPreferredAccuracyM = 8;

  static bool isSmallRadius(double radiusM) => isSmallGeofenceRadius(radiusM);

  LocationSettings _streamSettings() {
    if (!kIsWeb && Platform.isAndroid) {
      return AndroidSettings(
        accuracy: LocationAccuracy.best,
        distanceFilter: 0,
        intervalDuration: const Duration(milliseconds: 700),
        forceLocationManager: false,
      );
    }
    if (!kIsWeb && Platform.isIOS) {
      return AppleSettings(
        accuracy: LocationAccuracy.best,
        activityType: ActivityType.otherNavigation,
        distanceFilter: 0,
        pauseLocationUpdatesAutomatically: false,
        allowBackgroundLocationUpdates: false,
      );
    }
    return const LocationSettings(
      accuracy: LocationAccuracy.best,
      distanceFilter: 0,
    );
  }

  LocationSettings _pollSettings({Duration? timeLimit}) {
    final limit = timeLimit ?? const Duration(seconds: 4);
    if (!kIsWeb && Platform.isAndroid) {
      return AndroidSettings(
        accuracy: LocationAccuracy.best,
        distanceFilter: 0,
        forceLocationManager: false,
        timeLimit: limit,
      );
    }
    if (!kIsWeb && Platform.isIOS) {
      return AppleSettings(
        accuracy: LocationAccuracy.best,
        activityType: ActivityType.otherNavigation,
        distanceFilter: 0,
        pauseLocationUpdatesAutomatically: false,
        timeLimit: limit,
      );
    }
    return LocationSettings(
      accuracy: LocationAccuracy.best,
      timeLimit: limit,
    );
  }

  static double cappedGpsUncertaintyM(double accuracyM) {
    if (!accuracyM.isFinite || accuracyM <= 0) return 0;
    return math.min(accuracyM, maxAccuracyToleranceM);
  }

  static double preferredAccuracyForRadius(double radiusM) {
    return isSmallRadius(radiusM)
        ? smallRadiusPreferredAccuracyM
        : preferredAccuracyM;
  }

  static double maxAcceptableAccuracy(double radiusM) {
    if (isSmallRadius(radiusM)) return 15;
    return math
        .min(35.0, math.max(preferredAccuracyM, radiusM * 0.5))
        .clamp(10.0, 35.0)
        .toDouble();
  }

  static int targetSamplesForRadius(double radiusM) =>
      isSmallRadius(radiusM) ? smallRadiusSampleCount : targetSampleCount;

  Future<void> ensurePermission() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      throw const LocationServiceException(
        'Please turn on location so we can confirm you’re at work.',
      );
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied) {
      throw const LocationPermissionException(
        'Please allow location access so we can confirm you’re at your workplace.',
      );
    }
    if (permission == LocationPermission.deniedForever) {
      throw const LocationPermissionException(
        'Please allow location access in your device settings.',
      );
    }
  }

  /// Fresh high-accuracy GPS. Small radii collect more samples and wait longer.
  ///
  /// When [earlyAcceptCenterLatitude]/[earlyAcceptCenterLongitude]/
  /// [earlyAcceptRadiusM] are provided, returns as soon as ≥[minSampleCount]
  /// samples average to an inside geofence with acceptable accuracy — same
  /// validation rules, less waiting when already clearly inside.
  Future<EmployeeLocationSnapshot> freshPositionForAttendance({
    required double geofenceRadiusM,
    Duration? timeout,
    void Function(EmployeeLocationSnapshot snapshot)? onUpdate,
    void Function(String message)? onStatus,
    double? earlyAcceptCenterLatitude,
    double? earlyAcceptCenterLongitude,
    double? earlyAcceptRadiusM,
  }) async {
    if (geofenceRadiusM <= 0) {
      throw ArgumentError.value(geofenceRadiusM, 'geofenceRadiusM');
    }
    await ensurePermission();

    final small = isSmallRadius(geofenceRadiusM);
    final wait = timeout ??
        (small ? const Duration(seconds: 16) : const Duration(seconds: 10));
    final sampleTarget = targetSamplesForRadius(geofenceRadiusM);
    final preferred = preferredAccuracyForRadius(geofenceRadiusM);
    final maxAccuracy = maxAcceptableAccuracy(geofenceRadiusM);
    final canEarlyAccept = earlyAcceptCenterLatitude != null &&
        earlyAcceptCenterLongitude != null &&
        earlyAcceptRadiusM != null &&
        earlyAcceptRadiusM > 0;

    onStatus?.call(
      small
          ? 'Getting a precise location for a small work area...'
          : 'Getting your current location...',
    );

    final samples = <EmployeeLocationSnapshot>[];
    final startedAt = DateTime.now();
    final deadline = startedAt.add(wait);
    StreamSubscription<Position>? subscription;
    var polling = true;
    var mockDetected = false;

    void consider(Position position) {
      if (!_isPlausibleCoordinate(position.latitude, position.longitude)) {
        return;
      }
      // Platform mock / developer fake-GPS detection (Android isMocked).
      if (position.isMocked) {
        mockDetected = true;
        developer.log(
          'GPS_MOCK_DETECTED lat=${position.latitude} lng=${position.longitude}',
          name: 'aroll.geofence',
        );
        return;
      }
      final accuracy =
          position.accuracy.isFinite ? position.accuracy : 9999.0;
      final snapshot = EmployeeLocationSnapshot(
        latitude: position.latitude,
        longitude: position.longitude,
        accuracyM: accuracy,
        isMocked: false,
      );
      onUpdate?.call(snapshot);

      if (samples.length >= minSampleCount && accuracy > maxAccuracy * 1.6) {
        return;
      }
      samples.add(snapshot);
      if (samples.length >= minSampleCount) {
        onStatus?.call(
          small
              ? 'Improving GPS for a tight attendance area...'
              : 'Improving GPS accuracy...',
        );
      }
    }

    try {
      subscription = Geolocator.getPositionStream(
        locationSettings: _streamSettings(),
      ).listen(consider, onError: (_) {});

      () async {
        while (polling && DateTime.now().isBefore(deadline)) {
          try {
            final position = await Geolocator.getCurrentPosition(
              locationSettings: _pollSettings(),
            );
            consider(position);
          } catch (_) {}
          if (!polling || !DateTime.now().isBefore(deadline)) break;
          await Future<void>.delayed(const Duration(milliseconds: 550));
        }
      }();

      while (DateTime.now().isBefore(deadline)) {
        if (mockDetected) {
          throw const LocationMockException();
        }
        final sharp = samples.where((s) => s.accuracyM <= preferred).length;
        if (samples.length >= sampleTarget &&
            (sharp >= minSampleCount ||
                samples.where((s) => s.accuracyM <= maxAccuracy).length >=
                    minSampleCount)) {
          break;
        }

        // Fast path: enough samples, sharp enough, already inside fence.
        final earlyLat = earlyAcceptCenterLatitude;
        final earlyLng = earlyAcceptCenterLongitude;
        final earlyRadius = earlyAcceptRadiusM;
        if (canEarlyAccept &&
            earlyLat != null &&
            earlyLng != null &&
            earlyRadius != null &&
            samples.length >= minSampleCount) {
          final probe = _averageSamples(samples, keepBest: sampleTarget);
          if (probe.accuracyM <= maxAccuracy) {
            final early = preview(
              device: probe,
              centerLatitude: earlyLat,
              centerLongitude: earlyLng,
              radiusM: earlyRadius,
            );
            if (early.insideGeofence && !early.needsBetterGps) {
              developer.log(
                'GPS_EARLY_ACCEPT samples=${probe.sampleCount} '
                'accuracy_m=${probe.accuracyM} distance_m=${early.distanceM} '
                'duration_ms=${DateTime.now().difference(startedAt).inMilliseconds}',
                name: 'aroll.geofence',
              );
              onUpdate?.call(probe);
              return probe;
            }
          }
        }

        if (samples.length >= minSampleCount &&
            DateTime.now().isAfter(
              deadline.subtract(Duration(seconds: small ? 5 : 3)),
            )) {
          break;
        }
        await Future<void>.delayed(const Duration(milliseconds: 200));
      }

      if (mockDetected) {
        throw const LocationMockException();
      }
      if (samples.isEmpty) {
        throw const LocationAccuracyException(
          'Getting your current location... Please try again outdoors.',
        );
      }

      onStatus?.call(
        small
            ? 'Checking your position in the small work area...'
            : 'Improving GPS accuracy...',
      );
      final averaged = _averageSamples(samples, keepBest: sampleTarget);
      if (averaged.isMocked) {
        throw const LocationMockException();
      }
      onUpdate?.call(averaged);

      if (averaged.accuracyM > maxAccuracy &&
          averaged.sampleCount < minSampleCount) {
        throw LocationAccuracyException(
          small
              ? 'This work area is very small. Please stand outdoors near the entrance and try again '
                  '(±${averaged.accuracyM.toStringAsFixed(0)} m).'
              : 'Improving GPS accuracy... Please move outdoors or near a window '
                  '(±${averaged.accuracyM.toStringAsFixed(0)} m).',
        );
      }

      final durationMs =
          DateTime.now().difference(startedAt).inMilliseconds;
      developer.log(
        'GPS_SAMPLES collected=${samples.length} selected=${averaged.sampleCount} '
        'lat=${averaged.latitude} lng=${averaged.longitude} '
        'accuracy_m=${averaged.accuracyM} duration_ms=$durationMs '
        'radius_m=$geofenceRadiusM',
        name: 'aroll.geofence',
      );

      return averaged;
    } finally {
      polling = false;
      await subscription?.cancel();
    }
  }

  EmployeeLocationSnapshot _averageSamples(
    List<EmployeeLocationSnapshot> raw, {
    required int keepBest,
  }) {
    final sorted = [...raw]..sort((a, b) => a.accuracyM.compareTo(b.accuracyM));
    final pool =
        sorted.take(math.min(keepBest + 2, sorted.length)).toList();

    final seedCount = math.max(minSampleCount, (pool.length / 2).ceil());
    final seed = pool.take(seedCount).toList();
    final centerLat =
        seed.map((s) => s.latitude).reduce((a, b) => a + b) / seed.length;
    final centerLng =
        seed.map((s) => s.longitude).reduce((a, b) => a + b) / seed.length;

    final kept = <EmployeeLocationSnapshot>[];
    for (final sample in pool) {
      final d = _distanceMeters(
        sample.latitude,
        sample.longitude,
        centerLat,
        centerLng,
      );
      if (d <= math.max(20.0, sample.accuracyM * 1.8)) {
        kept.add(sample);
      }
    }
    final usable = kept.isNotEmpty ? kept : seed;

    final avgLat =
        usable.map((s) => s.latitude).reduce((a, b) => a + b) / usable.length;
    final avgLng =
        usable.map((s) => s.longitude).reduce((a, b) => a + b) / usable.length;
    final bestAccuracy = usable.map((s) => s.accuracyM).reduce(math.min);
    final meanAccuracy =
        usable.map((s) => s.accuracyM).reduce((a, b) => a + b) / usable.length;
    final reportedAccuracy = (bestAccuracy + meanAccuracy) / 2;

    developer.log(
      'GPS_AVERAGE samples=${usable.length}/${raw.length} '
      'lat=$avgLat lon=$avgLng accuracy_m=$reportedAccuracy',
      name: 'aroll.geofence',
    );

    return EmployeeLocationSnapshot(
      latitude: avgLat,
      longitude: avgLng,
      accuracyM: reportedAccuracy,
      sampleCount: usable.length,
      isMocked: usable.any((s) => s.isMocked),
    );
  }

  Future<EmployeeLocationSnapshot> currentPosition() async {
    await ensurePermission();
    final position = await Geolocator.getCurrentPosition(
      locationSettings: _pollSettings(timeLimit: const Duration(seconds: 12)),
    );
    if (position.isMocked) {
      throw const LocationMockException();
    }
    return EmployeeLocationSnapshot(
      latitude: position.latitude,
      longitude: position.longitude,
      accuracyM: position.accuracy,
      isMocked: position.isMocked,
    );
  }

  /// GPS uncertainty overlap — required for small radii (5–20 m).
  ///
  /// Inside when: (distance − min(accuracy, 12)) ≤ radius
  /// i.e. the GPS error circle still intersects the attendance disk.
  GeofencePreview preview({
    required EmployeeLocationSnapshot device,
    required double centerLatitude,
    required double centerLongitude,
    required double radiusM,
  }) {
    final distanceM = _distanceMeters(
      device.latitude,
      device.longitude,
      centerLatitude,
      centerLongitude,
    );

    final accuracyM = math.max(device.accuracyM, 0.0);
    final radius = math.max(radiusM, 0.0);
    final small = isSmallRadius(radius);
    final uncertainty = cappedGpsUncertaintyM(accuracyM);
    final bestCaseDistance = math.max(0.0, distanceM - uncertainty);
    // If the full reported accuracy circle still reaches the fence, a sharper
    // fix might flip the result — ask for better GPS instead of hard-reject.
    final reachableWithFullAccuracy =
        math.max(0.0, distanceM - accuracyM) <= radius + distanceEpsilonM;

    final inside = bestCaseDistance <= radius + distanceEpsilonM;
    final needsBetterGps = !inside &&
        reachableWithFullAccuracy &&
        accuracyM > preferredAccuracyForRadius(radius);

    String? failReason;
    if (inside) {
      failReason = null;
    } else if (needsBetterGps) {
      failReason = small
          ? 'Small ${radius.toStringAsFixed(0)} m area needs a sharper GPS fix '
              '(±${accuracyM.toStringAsFixed(0)} m, distance '
              '${distanceM.toStringAsFixed(1)} m).'
          : 'GPS accuracy ±${accuracyM.toStringAsFixed(0)} m is too weak to decide '
              'for a ${radius.toStringAsFixed(0)} m radius '
              '(distance ${distanceM.toStringAsFixed(1)} m).';
    } else {
      failReason =
          'best-case distance ${bestCaseDistance.toStringAsFixed(1)} m > '
          'radius ${radius.toStringAsFixed(0)} m '
          '(measured ${distanceM.toStringAsFixed(1)} m, '
          'GPS ±${uncertainty.toStringAsFixed(1)} m).';
    }

    logGeofenceValidation(
      businessLatitude: centerLatitude,
      businessLongitude: centerLongitude,
      employeeLatitude: device.latitude,
      employeeLongitude: device.longitude,
      accuracyM: accuracyM,
      radiusM: radius,
      toleranceM: uncertainty,
      distanceM: distanceM,
      insideGeofence: inside,
      needsBetterGps: needsBetterGps,
      sampleCount: device.sampleCount,
      failReason: failReason,
      smallRadius: small,
      bestCaseDistanceM: bestCaseDistance,
    );

    return GeofencePreview(
      distanceM: distanceM,
      allowedRadiusM: radius,
      insideGeofence: inside,
      businessLatitude: centerLatitude,
      businessLongitude: centerLongitude,
      employeeLatitude: device.latitude,
      employeeLongitude: device.longitude,
      accuracyM: accuracyM,
      toleranceM: uncertainty,
      needsBetterGps: needsBetterGps,
      failReason: failReason,
    );
  }

  static void logGeofenceValidation({
    required double businessLatitude,
    required double businessLongitude,
    required double employeeLatitude,
    required double employeeLongitude,
    required double accuracyM,
    required double radiusM,
    required double distanceM,
    required bool insideGeofence,
    double toleranceM = 0,
    bool needsBetterGps = false,
    int sampleCount = 1,
    String? failReason,
    bool smallRadius = false,
    double? bestCaseDistanceM,
  }) {
    developer.log(
      'GEOFENCE_VALIDATION\n'
      '  mode=${smallRadius ? 'SMALL_RADIUS' : 'STANDARD'}\n'
      '  business: lat=$businessLatitude lon=$businessLongitude\n'
      '  employee: lat=$employeeLatitude lon=$employeeLongitude '
      'accuracy_m=$accuracyM samples=$sampleCount\n'
      '  radius_m=$radiusM uncertainty_m=$toleranceM '
      'effective_m=${radiusM + toleranceM}\n'
      '  distance_m=$distanceM'
      '${bestCaseDistanceM != null ? ' best_case_m=$bestCaseDistanceM' : ''}\n'
      '  result=${needsBetterGps ? 'NEEDS_BETTER_GPS' : (insideGeofence ? 'INSIDE' : 'OUTSIDE')}'
      '${failReason != null ? '\n  reason=$failReason' : ''}',
      name: 'aroll.geofence',
    );
  }

  static double _distanceMeters(
    double lat1,
    double lon1,
    double lat2,
    double lon2,
  ) {
    try {
      return Geolocator.distanceBetween(lat1, lon1, lat2, lon2);
    } catch (_) {
      return haversineDistanceM(lat1, lon1, lat2, lon2);
    }
  }

  static bool _isPlausibleCoordinate(double latitude, double longitude) {
    if (!latitude.isFinite || !longitude.isFinite) return false;
    if (latitude < -90 || latitude > 90) return false;
    if (longitude < -180 || longitude > 180) return false;
    if (latitude.abs() < 0.0001 && longitude.abs() < 0.0001) return false;
    return true;
  }
}

class LocationServiceException implements Exception {
  const LocationServiceException(this.message);
  final String message;

  @override
  String toString() => message;
}

class LocationPermissionException implements Exception {
  const LocationPermissionException(this.message);
  final String message;

  @override
  String toString() => message;
}

class LocationAccuracyException implements Exception {
  const LocationAccuracyException(this.message);
  final String message;

  @override
  String toString() => message;
}
