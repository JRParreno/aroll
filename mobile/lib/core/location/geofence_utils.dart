import 'dart:math' as math;

const _earthRadiusM = 6371000.0;

/// Great-circle distance in meters between two WGS84 coordinates.
double haversineDistanceM(
  double lat1,
  double lon1,
  double lat2,
  double lon2,
) {
  final phi1 = _toRadians(lat1);
  final phi2 = _toRadians(lat2);
  final dPhi = _toRadians(lat2 - lat1);
  final dLambda = _toRadians(lon2 - lon1);

  final a = math.sin(dPhi / 2) * math.sin(dPhi / 2) +
      math.cos(phi1) *
          math.cos(phi2) *
          math.sin(dLambda / 2) *
          math.sin(dLambda / 2);
  final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
  return _earthRadiusM * c;
}

bool isWithinGeofence({
  required double latitude,
  required double longitude,
  required double centerLatitude,
  required double centerLongitude,
  required double radiusM,
}) {
  return haversineDistanceM(
        latitude,
        longitude,
        centerLatitude,
        centerLongitude,
      ) <=
      radiusM;
}

double _toRadians(double degrees) => degrees * math.pi / 180;
