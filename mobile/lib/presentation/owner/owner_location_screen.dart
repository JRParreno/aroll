import 'package:aroll_mobile/core/di/injection.dart';
import 'package:aroll_mobile/core/location/business_location_defaults.dart';
import 'package:aroll_mobile/core/location/business_location_geocoding.dart';
import 'package:aroll_mobile/core/location/employee_location_service.dart';
import 'package:aroll_mobile/data/repositories/owner_repository.dart';
import 'package:aroll_mobile/presentation/owner/owner_shell.dart';
import 'package:aroll_mobile/presentation/owner/widgets/business_location_map_picker.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

class OwnerLocationScreen extends StatefulWidget {
  const OwnerLocationScreen({super.key});

  @override
  State<OwnerLocationScreen> createState() => _OwnerLocationScreenState();
}

class _OwnerLocationScreenState extends State<OwnerLocationScreen> {
  final _repo = sl<OwnerRepository>();
  final _locationService = EmployeeLocationService();
  final _addressController = TextEditingController();
  final _labelController = TextEditingController(text: 'Main');

  bool _loading = true;
  bool _saving = false;
  bool _locating = false;
  String? _loadError;

  double? _latitude;
  double? _longitude;
  double _geofenceRadiusM = kDefaultGeofenceRadiusM.toDouble();

  @override
  void initState() {
    super.initState();
    _loadLocation();
  }

  @override
  void dispose() {
    _addressController.dispose();
    _labelController.dispose();
    super.dispose();
  }

  Future<void> _loadLocation() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final data = await _repo.location();
      if (!mounted) return;
      setState(() {
        _labelController.text = '${data['label'] ?? 'Main'}';
        _addressController.text = '${data['address'] ?? ''}';
        _latitude = (data['latitude'] as num?)?.toDouble();
        _longitude = (data['longitude'] as num?)?.toDouble();
        _geofenceRadiusM =
            (data['geofence_radius_m'] as num?)?.toDouble() ??
                kDefaultGeofenceRadiusM.toDouble();
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loadError = 'Could not load business location.';
        _loading = false;
      });
    }
  }

  bool get _canSave =>
      !_saving &&
      _addressController.text.trim().length >= 5 &&
      _latitude != null &&
      _longitude != null &&
      _geofenceRadiusM >= kMinGeofenceRadiusM &&
      _geofenceRadiusM <= kMaxGeofenceRadiusM;

  Future<void> _useCurrentLocation() async {
    setState(() => _locating = true);
    try {
      final position = await _locationService.currentPosition();
      final address = await reverseGeocodeAddress(
        position.latitude,
        position.longitude,
      );
      if (!mounted) return;
      setState(() {
        _latitude = position.latitude;
        _longitude = position.longitude;
        if (address != null && address.trim().isNotEmpty) {
          _addressController.text = address;
        }
      });
      _showSnack(
        'Current location set (±${position.accuracyM.toStringAsFixed(0)} m)',
      );
    } catch (error) {
      if (!mounted) return;
      _showSnack('$error', isError: true);
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  Future<void> _onMapPositionChanged(LatLng position) async {
    setState(() {
      _latitude = position.latitude;
      _longitude = position.longitude;
    });
    final address = await reverseGeocodeAddress(
      position.latitude,
      position.longitude,
    );
    if (!mounted || address == null || address.trim().isEmpty) return;
    setState(() => _addressController.text = address);
  }

  Future<void> _save() async {
    if (!_canSave) return;
    setState(() => _saving = true);
    try {
      await _repo.updateLocation({
        'label': _labelController.text.trim().isEmpty
            ? 'Main'
            : _labelController.text.trim(),
        'address': _addressController.text.trim(),
        'latitude': _latitude,
        'longitude': _longitude,
        'geofence_radius_m': _geofenceRadiusM.round(),
      });
      if (!mounted) return;
      _showSnack('Business location saved');
    } catch (_) {
      if (!mounted) return;
      _showSnack('Failed to save location', isError: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _showSnack(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red.shade700 : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return OwnerShell(
      selectedIndex: 0,
      showBackButton: true,
      title: 'Business Location',
      actions: [
        TextButton(
          onPressed: _canSave ? _save : null,
          child: _saving
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Save'),
        ),
      ],
      child: _loading
          ? const Center(child: CircularProgressIndicator())
          : _loadError != null
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(_loadError!),
                      const SizedBox(height: 12),
                      FilledButton(
                        onPressed: _loadLocation,
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    OwnerCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Work site on map',
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Tap the map or drag the pin to set your business '
                            'location. Employees clock in using server-side '
                            'geofence validation.',
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.grey.shade700,
                              height: 1.35,
                            ),
                          ),
                          const SizedBox(height: 12),
                          OutlinedButton.icon(
                            onPressed: _locating ? null : _useCurrentLocation,
                            icon: _locating
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(Icons.my_location_rounded),
                            label: const Text('Use my current location'),
                          ),
                          const SizedBox(height: 12),
                          BusinessLocationMapPicker(
                            latitude: _latitude,
                            longitude: _longitude,
                            geofenceRadiusM: _geofenceRadiusM.round(),
                            onPositionChanged: _onMapPositionChanged,
                            height: 260,
                          ),
                          if (_latitude != null && _longitude != null) ...[
                            const SizedBox(height: 8),
                            Text(
                              'Coordinates: '
                              '${_latitude!.toStringAsFixed(6)}, '
                              '${_longitude!.toStringAsFixed(6)}',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey.shade600,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    OwnerCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          TextField(
                            controller: _addressController,
                            decoration: const InputDecoration(
                              labelText: 'Address',
                              hintText: '123 Main St, Manila',
                              border: OutlineInputBorder(),
                            ),
                            onChanged: (_) => setState(() {}),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'Geofence radius: ${_geofenceRadiusM.round()} m',
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          Slider(
                            value: _geofenceRadiusM,
                            min: kMinGeofenceRadiusM.toDouble(),
                            max: kMaxGeofenceRadiusM.toDouble(),
                            divisions:
                                kMaxGeofenceRadiusM - kMinGeofenceRadiusM,
                            label: '${_geofenceRadiusM.round()} m',
                            onChanged: (value) =>
                                setState(() => _geofenceRadiusM = value),
                          ),
                          Text(
                            'Employees must be within this radius to clock in. '
                            'Range: $kMinGeofenceRadiusM–$kMaxGeofenceRadiusM m.',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey.shade600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    FilledButton(
                      onPressed: _canSave ? _save : null,
                      child: _saving
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Text('Confirm & Save Location'),
                    ),
                  ],
                ),
    );
  }
}
