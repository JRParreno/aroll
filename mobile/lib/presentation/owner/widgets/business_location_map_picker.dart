import 'package:aroll_mobile/core/location/business_location_defaults.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

class BusinessLocationMapPicker extends StatefulWidget {
  const BusinessLocationMapPicker({
    super.key,
    this.latitude,
    this.longitude,
    required this.geofenceRadiusM,
    required this.onPositionChanged,
    this.height = 240,
  });

  final double? latitude;
  final double? longitude;
  final int geofenceRadiusM;
  final ValueChanged<LatLng> onPositionChanged;
  final double height;

  @override
  State<BusinessLocationMapPicker> createState() =>
      _BusinessLocationMapPickerState();
}

class _BusinessLocationMapPickerState extends State<BusinessLocationMapPicker> {
  GoogleMapController? _mapController;
  LatLng? _markerPosition;

  @override
  void initState() {
    super.initState();
    _syncMarkerFromWidget();
  }

  @override
  void didUpdateWidget(covariant BusinessLocationMapPicker oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.latitude != widget.latitude ||
        oldWidget.longitude != widget.longitude) {
      _syncMarkerFromWidget();
      _moveCameraToMarker();
    }
  }

  @override
  void dispose() {
    _mapController?.dispose();
    super.dispose();
  }

  void _syncMarkerFromWidget() {
    final lat = widget.latitude;
    final lng = widget.longitude;
    if (lat != null && lng != null) {
      _markerPosition = LatLng(lat, lng);
    }
  }

  LatLng get _cameraTarget =>
      _markerPosition ??
      const LatLng(kDefaultBusinessLatitude, kDefaultBusinessLongitude);

  Future<void> _moveCameraToMarker() async {
    final controller = _mapController;
    if (controller == null) return;
    await controller.animateCamera(
      CameraUpdate.newLatLngZoom(_cameraTarget, 16),
    );
  }

  void _setPosition(LatLng position) {
    setState(() => _markerPosition = position);
    widget.onPositionChanged(position);
    _mapController?.animateCamera(CameraUpdate.newLatLng(position));
  }

  Set<Marker> get _markers {
    final position = _markerPosition;
    if (position == null) return const {};
    return {
      Marker(
        markerId: const MarkerId('business_location'),
        position: position,
        draggable: true,
        onDragEnd: _setPosition,
      ),
    };
  }

  Set<Circle> get _circles {
    final position = _markerPosition;
    if (position == null) return const {};
    return {
      Circle(
        circleId: const CircleId('geofence'),
        center: position,
        radius: widget.geofenceRadiusM.toDouble(),
        fillColor: const Color(0x401E466E),
        strokeColor: const Color(0xFF1E466E),
        strokeWidth: 2,
      ),
    };
  }

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: SizedBox(
        height: widget.height,
        child: GoogleMap(
          initialCameraPosition: CameraPosition(
            target: _cameraTarget,
            zoom: _markerPosition == null ? 12 : 16,
          ),
          onMapCreated: (controller) {
            _mapController = controller;
            _moveCameraToMarker();
          },
          onTap: _setPosition,
          myLocationEnabled: true,
          myLocationButtonEnabled: false,
          zoomControlsEnabled: false,
          markers: _markers,
          circles: _circles,
        ),
      ),
    );
  }
}
