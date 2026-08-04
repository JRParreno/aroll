import 'package:dio/dio.dart';
import 'package:geocoding/geocoding.dart';

final Dio _nominatimDio = Dio(
  BaseOptions(
    connectTimeout: const Duration(seconds: 12),
    receiveTimeout: const Duration(seconds: 12),
    headers: const {
      'User-Agent': 'ArollPlus/1.0 (com.example.aroll_mobile)',
      'Accept': 'application/json',
    },
  ),
);

DateTime? _lastReverseAt;

Future<void> _throttleReverse() async {
  final last = _lastReverseAt;
  if (last != null) {
    final wait =
        const Duration(milliseconds: 1100) - DateTime.now().difference(last);
    if (wait > Duration.zero) {
      await Future<void>.delayed(wait);
    }
  }
  _lastReverseAt = DateTime.now();
}

/// Readable address for the UI (barangay / city / province). No raw coordinates.
Future<String?> reverseGeocodeAddress(double latitude, double longitude) async {
  final nominatim = await _reverseViaNominatim(latitude, longitude);
  if (nominatim != null && nominatim.trim().isNotEmpty) return nominatim;
  return _reverseViaDeviceGeocoder(latitude, longitude);
}

Future<String?> _reverseViaNominatim(double latitude, double longitude) async {
  try {
    await _throttleReverse();
    final response = await _nominatimDio.get<Map<String, dynamic>>(
      'https://nominatim.openstreetmap.org/reverse',
      queryParameters: {
        'lat': latitude,
        'lon': longitude,
        'format': 'json',
        'addressdetails': 1,
        'zoom': 18,
      },
    );
    final data = response.data;
    if (data == null) return null;
    final address = data['address'] as Map<String, dynamic>?;
    if (address == null) {
      final display = '${data['display_name'] ?? ''}'.trim();
      return display.isEmpty ? null : display;
    }

    final streetParts = <String>[
      if ('${address['house_number'] ?? ''}'.trim().isNotEmpty)
        '${address['house_number']}'.trim(),
      if ('${address['road'] ?? ''}'.trim().isNotEmpty)
        '${address['road']}'.trim(),
    ];
    final street = streetParts.join(' ');

    final barangay = [
      address['suburb'],
      address['neighbourhood'],
      address['village'],
      address['quarter'],
      address['hamlet'],
    ].map((e) => '$e'.trim()).firstWhere(
          (s) => s.isNotEmpty && s != 'null',
          orElse: () => '',
        );

    final city = [
      address['city'],
      address['municipality'],
      address['town'],
      address['city_district'],
    ].map((e) => '$e'.trim()).firstWhere(
          (s) => s.isNotEmpty && s != 'null',
          orElse: () => '',
        );

    final province = [
      address['state'],
      address['province'],
      address['region'],
    ].map((e) => '$e'.trim()).firstWhere(
          (s) => s.isNotEmpty && s != 'null',
          orElse: () => '',
        );

    final parts = <String>[
      if (street.isNotEmpty) street,
      if (barangay.isNotEmpty) barangay,
      if (city.isNotEmpty) city,
      if (province.isNotEmpty) province,
    ];
    if (parts.isEmpty) return null;
    return parts.join(', ');
  } catch (_) {
    return null;
  }
}

Future<String?> _reverseViaDeviceGeocoder(
  double latitude,
  double longitude,
) async {
  try {
    final placemarks = await placemarkFromCoordinates(latitude, longitude);
    if (placemarks.isEmpty) return null;

    final place = placemarks.first;
    final parts = <String>[
      if (place.street != null && place.street!.trim().isNotEmpty)
        place.street!.trim(),
      if (place.subLocality != null && place.subLocality!.trim().isNotEmpty)
        place.subLocality!.trim(),
      if (place.locality != null && place.locality!.trim().isNotEmpty)
        place.locality!.trim(),
      if (place.administrativeArea != null &&
          place.administrativeArea!.trim().isNotEmpty)
        place.administrativeArea!.trim(),
    ];
    if (parts.isEmpty) return null;
    return parts.join(', ');
  } catch (_) {
    return null;
  }
}
