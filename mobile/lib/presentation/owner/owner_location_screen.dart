import 'dart:async';

import 'package:aroll_mobile/core/app_state.dart';
import 'package:aroll_mobile/core/di/injection.dart';
import 'package:aroll_mobile/core/location/business_location_defaults.dart';
import 'package:aroll_mobile/core/location/business_location_geocoding.dart';
import 'package:aroll_mobile/core/location/business_places_search.dart';
import 'package:aroll_mobile/core/location/employee_location_service.dart';
import 'package:aroll_mobile/data/repositories/owner_repository.dart';
import 'package:aroll_mobile/presentation/owner/owner_shell.dart';
import 'package:aroll_mobile/presentation/owner/widgets/business_location_map_picker.dart';
import 'package:aroll_mobile/presentation/shared/app_ui.dart';
import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

class OwnerLocationScreen extends StatefulWidget {
  const OwnerLocationScreen({super.key});

  @override
  State<OwnerLocationScreen> createState() => _OwnerLocationScreenState();
}

class _OwnerLocationScreenState extends State<OwnerLocationScreen> {
  static const _navy = Color(0xFF1F456B);
  static const _softBlue = Color(0xFFB9D8EE);
  static const _panelBg = Colors.white;

  final _repo = sl<OwnerRepository>();
  final _locationService = EmployeeLocationService();
  final _placesSearch = BusinessPlacesSearch();
  final _addressController = TextEditingController();
  final _addressFocus = FocusNode();
  final _labelController = TextEditingController(text: 'Main');

  bool _loading = true;
  bool _saving = false;
  bool _locating = false;
  bool _searching = false;
  bool _addressEditedManually = false;
  String? _loadError;

  double? _latitude;
  double? _longitude;
  double _geofenceRadiusM = kDefaultGeofenceRadiusM.toDouble();
  int _mapFocusToken = 0;

  /// Snapshot used by Cancel to restore last loaded/saved values.
  String _savedLabel = 'Main';
  String _savedAddress = '';
  double? _savedLatitude;
  double? _savedLongitude;
  double _savedGeofenceRadiusM = kDefaultGeofenceRadiusM.toDouble();

  List<PlaceSuggestion> _suggestions = const [];
  Timer? _debounce;
  Timer? _reverseGeocodeDebounce;

  void _bumpMapFocus() {
    _mapFocusToken++;
  }

  bool get _isManager => sl<AppState>().session?.role == 'manager';

  @override
  void initState() {
    super.initState();
    _loadLocation();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _reverseGeocodeDebounce?.cancel();
    _addressController.dispose();
    _addressFocus.dispose();
    _labelController.dispose();
    super.dispose();
  }

  void _storeSnapshot() {
    _savedLabel = _labelController.text;
    _savedAddress = _addressController.text;
    _savedLatitude = _latitude;
    _savedLongitude = _longitude;
    _savedGeofenceRadiusM = _geofenceRadiusM;
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
        _latitude = _coordFromJson(data['latitude']);
        _longitude = _coordFromJson(data['longitude']);
        _geofenceRadiusM =
            (_coordFromJson(data['geofence_radius_m']) ??
                    kDefaultGeofenceRadiusM.toDouble());
        if (_geofenceRadiusM < kMinGeofenceRadiusM) {
          _geofenceRadiusM = kMinGeofenceRadiusM.toDouble();
        }
        if (_geofenceRadiusM > kMaxGeofenceRadiusM) {
          _geofenceRadiusM = kMaxGeofenceRadiusM.toDouble();
        }
        _addressEditedManually = false;
        _suggestions = const [];
        _loading = false;
      });
      _storeSnapshot();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loadError = 'Could not load business location.';
        _loading = false;
      });
    }
  }

  bool get _canSave =>
      !_isManager &&
      !_saving &&
      _addressController.text.trim().length >= 5 &&
      _latitude != null &&
      _longitude != null &&
      _geofenceRadiusM >= kMinGeofenceRadiusM &&
      _geofenceRadiusM <= kMaxGeofenceRadiusM;

  Future<void> _applyReverseGeocodedAddress(
    double latitude,
    double longitude,
  ) async {
    if (_addressEditedManually) return;
    final address = await reverseGeocodeAddress(latitude, longitude);
    if (!mounted || address == null || address.trim().isEmpty) return;
    setState(() => _addressController.text = address);
  }

  Future<void> _useCurrentLocation() async {
    if (_isManager) return;
    setState(() => _locating = true);
    try {
      final position = await _locationService.currentPosition();
      if (!mounted) return;
      setState(() {
        _latitude = position.latitude;
        _longitude = position.longitude;
        _addressEditedManually = false;
        _suggestions = const [];
        _bumpMapFocus();
      });
      await _applyReverseGeocodedAddress(
        position.latitude,
        position.longitude,
      );
    } catch (error) {
      if (!mounted) return;
      _showSnack('$error', isError: true);
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  Future<void> _onMapPositionChanged(LatLng position) async {
    if (_isManager) return;
    // Camera animation is handled by the map picker for tap/drag.
    setState(() {
      _latitude = position.latitude;
      _longitude = position.longitude;
      _addressEditedManually = false;
      _suggestions = const [];
    });
    // Debounce reverse geocoding so drag stays smooth.
    _reverseGeocodeDebounce?.cancel();
    _reverseGeocodeDebounce = Timer(const Duration(milliseconds: 450), () {
      unawaited(
        _applyReverseGeocodedAddress(position.latitude, position.longitude),
      );
    });
  }

  void _onAddressChanged(String value) {
    setState(() {
      _addressEditedManually = true;
    });
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      _fetchSuggestions(value);
    });
  }

  Future<void> _fetchSuggestions(String query) async {
    if (_isManager) return;
    final trimmed = query.trim();
    if (trimmed.length < 2) {
      if (mounted) setState(() => _suggestions = const []);
      return;
    }
    setState(() => _searching = true);
    try {
      final results = await _placesSearch.autocomplete(trimmed);
      if (!mounted) return;
      setState(() => _suggestions = results);
    } catch (_) {
      if (!mounted) return;
      setState(() => _suggestions = const []);
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  Future<void> _selectSuggestion(PlaceSuggestion suggestion) async {
    setState(() {
      _searching = true;
      _suggestions = const [];
    });
    _addressFocus.unfocus();
    try {
      final place = await _placesSearch.resolve(suggestion);
      if (!mounted) return;
      if (place == null) {
        _showSnack('Could not find that address.', isError: true);
        return;
      }
      setState(() {
        _addressController.text = place.address;
        _latitude = place.latitude;
        _longitude = place.longitude;
        if (place.name != null && place.name!.trim().isNotEmpty) {
          _labelController.text = place.name!.trim();
        }
        _addressEditedManually = true;
        _bumpMapFocus();
      });
    } catch (_) {
      if (!mounted) return;
      _showSnack('Could not find that address.', isError: true);
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  Future<void> _submitAddressSearch() async {
    final query = _addressController.text.trim();
    if (query.length < 3 || _isManager) return;
    setState(() {
      _searching = true;
      _suggestions = const [];
    });
    _addressFocus.unfocus();
    try {
      final place = await _placesSearch.resolveAddress(query);
      if (!mounted) return;
      if (place == null) {
        _showSnack('No results for that address.', isError: true);
        return;
      }
      setState(() {
        _addressController.text = place.address;
        _latitude = place.latitude;
        _longitude = place.longitude;
        _addressEditedManually = true;
        _bumpMapFocus();
      });
    } catch (_) {
      if (!mounted) return;
      _showSnack('No results for that address.', isError: true);
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  void _cancelEdits() {
    setState(() {
      _labelController.text = _savedLabel;
      _addressController.text = _savedAddress;
      _latitude = _savedLatitude;
      _longitude = _savedLongitude;
      _geofenceRadiusM = _savedGeofenceRadiusM;
      _addressEditedManually = false;
      _suggestions = const [];
      _bumpMapFocus();
    });
    _addressFocus.unfocus();
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
        // Persist the exact marker coordinates (full double precision).
        'latitude': _latitude!,
        'longitude': _longitude!,
        'geofence_radius_m': _geofenceRadiusM.round(),
      });
      if (!mounted) return;
      _storeSnapshot();
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

  static double? _coordFromJson(Object? value) {
    if (value == null) return null;
    if (value is num) return value.toDouble();
    return double.tryParse('$value');
  }

  @override
  Widget build(BuildContext context) {
    return OwnerShell(
      selectedIndex: 0,
      showBackButton: true,
      title: 'Location',
      child: _loading
          ? appLoadingView(cardCount: 3)
          : _loadError != null
              ? OwnerErrorState(onRetry: _loadLocation)
              : _buildBody(),
    );
  }

  Widget _buildBody() {
    return Column(
      children: [
        if (_isManager) _managerReadOnlyBanner(),
        Expanded(
          flex: 11,
          child: BusinessLocationMapPicker(
            latitude: _latitude,
            longitude: _longitude,
            geofenceRadiusM: _geofenceRadiusM.round(),
            onPositionChanged: _onMapPositionChanged,
            expand: true,
            showMyLocationButton: !_isManager,
            onMyLocationPressed: _useCurrentLocation,
            locating: _locating,
            borderRadius: BorderRadius.zero,
            focusToken: _mapFocusToken,
          ),
        ),
        Expanded(
          flex: 10,
          child: _bottomPanel(),
        ),
      ],
    );
  }

  Widget _managerReadOnlyBanner() {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFEFF6FF),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFBFDBFE)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.info_outline_rounded, color: _navy),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Only the business owner can update the business location.',
              style: TextStyle(
                fontSize: 13,
                color: Colors.grey.shade800,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _bottomPanel() {
    final radiusLabel = '${_geofenceRadiusM.round()}m';
    return Material(
      color: _panelBg,
      elevation: 8,
      shadowColor: Colors.black26,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      child: SafeArea(
        top: false,
        child: CustomScrollView(
          physics: const ClampingScrollPhysics(),
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
              sliver: SliverList(
                delegate: SliverChildListDelegate([
                  const Text(
                    'Add Business Address',
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF111827),
                    ),
                  ),
                  const SizedBox(height: 10),
                  _addressField(),
                  if (_suggestions.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    _suggestionsList(),
                  ],
                  const SizedBox(height: 4),
                  if (!_isManager)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        onPressed: _locating ? null : _useCurrentLocation,
                        icon: _locating
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.my_location_rounded, size: 18),
                        label: const Text('Use My Current Location'),
                        style: TextButton.styleFrom(
                          foregroundColor: _navy,
                          padding: EdgeInsets.zero,
                          visualDensity: VisualDensity.compact,
                        ),
                      ),
                    ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'Set Attendance Distance',
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF111827),
                          ),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF3F4F6),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: const Color(0xFFE5E7EB)),
                        ),
                        child: Text(
                          radiusLabel,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF111827),
                          ),
                        ),
                      ),
                    ],
                  ),
                  SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      trackHeight: 10,
                      activeTrackColor: _navy,
                      inactiveTrackColor: _softBlue,
                      thumbColor: Colors.white,
                      overlayColor: _navy.withValues(alpha: 0.12),
                      thumbShape: const RoundSliderThumbShape(
                        enabledThumbRadius: 11,
                        elevation: 2,
                      ),
                      trackShape: const RoundedRectSliderTrackShape(),
                    ),
                    child: Slider(
                      value: _geofenceRadiusM.clamp(
                        kMinGeofenceRadiusM.toDouble(),
                        kMaxGeofenceRadiusM.toDouble(),
                      ),
                      min: kMinGeofenceRadiusM.toDouble(),
                      max: kMaxGeofenceRadiusM.toDouble(),
                      divisions: kMaxGeofenceRadiusM - kMinGeofenceRadiusM,
                      onChanged: _isManager
                          ? null
                          : (value) => setState(() => _geofenceRadiusM = value),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          '${kMinGeofenceRadiusM}m - ${kMaxGeofenceRadiusM}m',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: Colors.grey.shade800,
                          ),
                        ),
                        Text(
                          radiusLabel,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: Colors.grey.shade800,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (isSmallGeofenceRadius(_geofenceRadiusM)) ...[
                    const SizedBox(height: 8),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFFBEB),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: const Color(0xFFFDE68A)),
                      ),
                      child: const Text(
                        kSmallGeofenceOwnerTip,
                        style: TextStyle(
                          fontSize: 12,
                          height: 1.35,
                          color: Color(0xFF92400E),
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ]),
              ),
            ),
            SliverFillRemaining(
              hasScrollBody: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
                child: Align(
                  alignment: Alignment.bottomCenter,
                  child: Row(
                    children: [
                      Expanded(
                        child: SizedBox(
                          height: 48,
                          child: FilledButton(
                            onPressed: _isManager ? null : _cancelEdits,
                            style: FilledButton.styleFrom(
                              backgroundColor: _softBlue,
                              foregroundColor: Colors.white,
                              disabledBackgroundColor:
                                  _softBlue.withValues(alpha: 0.5),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                              elevation: 0,
                            ),
                            child: const Text(
                              'Cancel',
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 15,
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: SizedBox(
                          height: 48,
                          child: FilledButton(
                            onPressed: _canSave ? _save : null,
                            style: FilledButton.styleFrom(
                              backgroundColor: _navy,
                              foregroundColor: Colors.white,
                              disabledBackgroundColor:
                                  _navy.withValues(alpha: 0.4),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                              elevation: 0,
                            ),
                            child: _saving
                                ? const SizedBox(
                                    width: 22,
                                    height: 22,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : const Text(
                                    'Save Location',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 15,
                                    ),
                                  ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _addressField() {
    return Material(
      color: Colors.white,
      elevation: 2,
      shadowColor: Colors.black26,
      borderRadius: BorderRadius.circular(12),
      child: TextField(
        controller: _addressController,
        focusNode: _addressFocus,
        enabled: !_isManager,
        textInputAction: TextInputAction.search,
        onChanged: _onAddressChanged,
        onSubmitted: (_) => _submitAddressSearch(),
        decoration: InputDecoration(
          hintText: 'Search street, barangay, or place',
          hintStyle: TextStyle(color: Colors.grey.shade500, fontSize: 14),
          prefixIcon: Icon(Icons.search_rounded, color: Colors.grey.shade600),
          suffixIcon: _searching
              ? const Padding(
                  padding: EdgeInsets.all(12),
                  child: SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
              : (_addressController.text.isNotEmpty
                  ? IconButton(
                      tooltip: 'Clear',
                      onPressed: () {
                        setState(() {
                          _addressController.clear();
                          _suggestions = const [];
                          _addressEditedManually = true;
                        });
                      },
                      icon: Icon(
                        Icons.close_rounded,
                        color: Colors.grey.shade500,
                      ),
                    )
                  : null),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: _navy, width: 1.2),
          ),
          filled: true,
          fillColor: Colors.white,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 14,
          ),
        ),
      ),
    );
  }

  Widget _suggestionsList() {
    return Material(
      color: Colors.white,
      elevation: 2,
      borderRadius: BorderRadius.circular(12),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 140),
        child: ListView.separated(
          padding: EdgeInsets.zero,
          shrinkWrap: true,
          itemCount: _suggestions.length.clamp(0, 6),
          separatorBuilder: (_, __) => Divider(
            height: 1,
            color: Colors.grey.shade200,
          ),
          itemBuilder: (context, index) {
            final suggestion = _suggestions[index];
            return ListTile(
              dense: true,
              leading: Icon(
                Icons.place_outlined,
                color: Colors.grey.shade600,
                size: 20,
              ),
              title: Text(
                suggestion.description,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 13),
              ),
              onTap: () => _selectSuggestion(suggestion),
            );
          },
        ),
      ),
    );
  }
}
