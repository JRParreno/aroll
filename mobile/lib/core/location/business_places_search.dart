import 'package:dio/dio.dart';

class PlaceSuggestion {
  const PlaceSuggestion({
    required this.description,
    this.placeId,
    this.latitude,
    this.longitude,
  });

  final String description;
  final String? placeId;
  final double? latitude;
  final double? longitude;
}

class ResolvedPlace {
  const ResolvedPlace({
    required this.address,
    required this.latitude,
    required this.longitude,
    this.name,
  });

  final String address;
  final double latitude;
  final double longitude;
  final String? name;
}

/// Free OpenStreetMap Nominatim search (no API key / billing).
class BusinessPlacesSearch {
  BusinessPlacesSearch({Dio? dio})
      : _dio = dio ??
            Dio(
              BaseOptions(
                connectTimeout: const Duration(seconds: 12),
                receiveTimeout: const Duration(seconds: 12),
                headers: const {
                  // Nominatim requires a descriptive User-Agent.
                  'User-Agent': 'ArollPlus/1.0 (com.example.aroll_mobile)',
                  'Accept': 'application/json',
                },
              ),
            );

  final Dio _dio;
  static const _searchUrl = 'https://nominatim.openstreetmap.org/search';
  DateTime? _lastRequestAt;

  Future<void> _throttle() async {
    final last = _lastRequestAt;
    if (last != null) {
      final wait = const Duration(milliseconds: 1100) -
          DateTime.now().difference(last);
      if (wait > Duration.zero) {
        await Future<void>.delayed(wait);
      }
    }
    _lastRequestAt = DateTime.now();
  }

  Future<List<PlaceSuggestion>> autocomplete(String input) async {
    final query = input.trim();
    if (query.length < 2) return const [];

    try {
      await _throttle();
      final response = await _dio.get<List<dynamic>>(
        _searchUrl,
        queryParameters: {
          'q': query,
          'format': 'json',
          'addressdetails': 1,
          'limit': 6,
          'countrycodes': 'ph',
        },
      );
      final results = response.data ?? const [];
      return results
          .map((raw) {
            final item = raw as Map<String, dynamic>;
            final lat = double.tryParse('${item['lat'] ?? ''}');
            final lon = double.tryParse('${item['lon'] ?? ''}');
            final description = _formatNominatimResult(item);
            if (description.isEmpty || lat == null || lon == null) {
              return null;
            }
            return PlaceSuggestion(
              description: description,
              placeId: '${item['place_id'] ?? ''}',
              latitude: lat,
              longitude: lon,
            );
          })
          .whereType<PlaceSuggestion>()
          .toList();
    } catch (_) {
      return const [];
    }
  }

  Future<ResolvedPlace?> resolve(PlaceSuggestion suggestion) async {
    if (suggestion.latitude != null && suggestion.longitude != null) {
      return ResolvedPlace(
        address: suggestion.description,
        latitude: suggestion.latitude!,
        longitude: suggestion.longitude!,
      );
    }
    return resolveAddress(suggestion.description);
  }

  Future<ResolvedPlace?> resolveAddress(String address) async {
    final query = address.trim();
    if (query.length < 3) return null;
    final results = await autocomplete(query);
    if (results.isEmpty) return null;
    final first = results.first;
    return ResolvedPlace(
      address: first.description,
      latitude: first.latitude!,
      longitude: first.longitude!,
    );
  }

  String _formatNominatimResult(Map<String, dynamic> item) {
    final display = '${item['display_name'] ?? ''}'.trim();
    final address = item['address'] as Map<String, dynamic>?;
    if (address == null) return display;

    final name = [
      address['amenity'],
      address['shop'],
      address['building'],
      address['tourism'],
      address['name'],
    ].map((e) => '$e'.trim()).firstWhere(
          (s) => s.isNotEmpty && s != 'null',
          orElse: () => '',
        );

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
      if (name.isNotEmpty) name,
      if (street.isNotEmpty) street,
      if (barangay.isNotEmpty) barangay,
      if (city.isNotEmpty) city,
      if (province.isNotEmpty) province,
    ];

    if (parts.isEmpty) return display;
    return parts.join(', ');
  }
}
