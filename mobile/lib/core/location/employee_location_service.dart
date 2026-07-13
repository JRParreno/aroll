import 'package:aroll_mobile/core/location/geofence_utils.dart';
import 'package:geolocator/geolocator.dart';

class EmployeeLocationSnapshot {
  const EmployeeLocationSnapshot({
    required this.latitude,
    required this.longitude,
    required this.accuracyM,
  });

  final double latitude;
  final double longitude;
  final double accuracyM;
}

class GeofencePreview {
  const GeofencePreview({
    required this.distanceM,
    required this.allowedRadiusM,
    required this.insideGeofence,
  });

  final double distanceM;
  final double allowedRadiusM;
  final bool insideGeofence;
}

class EmployeeLocationService {
  Future<void> ensurePermission() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      throw const LocationServiceException(
        'Location services are disabled. Turn on GPS to clock attendance.',
      );
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied) {
      throw const LocationPermissionException(
        'Location permission is required to verify you are at the work site.',
      );
    }
    if (permission == LocationPermission.deniedForever) {
      throw const LocationPermissionException(
        'Location permission is permanently denied. Enable it in device settings.',
      );
    }
  }

  Future<EmployeeLocationSnapshot> currentPosition() async {
    await ensurePermission();
    final position = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        timeLimit: Duration(seconds: 20),
      ),
    );
    return EmployeeLocationSnapshot(
      latitude: position.latitude,
      longitude: position.longitude,
      accuracyM: position.accuracy,
    );
  }

  GeofencePreview preview({
    required EmployeeLocationSnapshot device,
    required double centerLatitude,
    required double centerLongitude,
    required double radiusM,
  }) {
    final distanceM = haversineDistanceM(
      device.latitude,
      device.longitude,
      centerLatitude,
      centerLongitude,
    );
    return GeofencePreview(
      distanceM: distanceM,
      allowedRadiusM: radiusM,
      insideGeofence: distanceM <= radiusM,
    );
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
