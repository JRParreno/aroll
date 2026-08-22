import 'dart:async';
import 'dart:math' as math;

import 'package:aroll_mobile/core/location/business_location_defaults.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

class BusinessLocationMapPicker extends StatefulWidget {
  const BusinessLocationMapPicker({
    super.key,
    this.latitude,
    this.longitude,
    required this.geofenceRadiusM,
    required this.onPositionChanged,
    this.height = 240,
    this.expand = false,
    this.showMyLocationButton = false,
    this.onMyLocationPressed,
    this.locating = false,
    this.borderRadius,
    /// Increment to force a camera re-fit (search / GPS / external moves).
    this.focusToken = 0,
  });

  final double? latitude;
  final double? longitude;
  final int geofenceRadiusM;
  final ValueChanged<LatLng> onPositionChanged;
  final double height;
  final bool expand;
  final bool showMyLocationButton;
  final VoidCallback? onMyLocationPressed;
  final bool locating;
  final BorderRadius? borderRadius;
  final int focusToken;

  @override
  State<BusinessLocationMapPicker> createState() =>
      _BusinessLocationMapPickerState();
}

class _BusinessLocationMapPickerState extends State<BusinessLocationMapPicker>
    with TickerProviderStateMixin {
  final MapController _mapController = MapController();

  /// Single source of truth for marker + geofence center.
  final ValueNotifier<LatLng?> _center = ValueNotifier(null);

  bool _mapReady = false;
  bool _pendingCameraFit = false;
  bool _dragging = false;
  bool _dragMoved = false;
  int? _activePointer;
  Offset? _lastPointerLocal;
  int _cameraToken = 0;
  Timer? _cameraDebounce;
  Timer? _liveNotifyDebounce;
  LatLng? _pendingLiveNotify;
  AnimationController? _moveAnimation;

  static const _fill = Color(0x59E53935);
  static const _stroke = Color(0xFFE53935);
  static const _tileUrl = 'https://tile.openstreetmap.org/{z}/{x}/{y}.png';
  static const _userAgent = 'com.example.aroll_mobile';

  @override
  void initState() {
    super.initState();
    _syncFromProps(
      latitude: widget.latitude,
      longitude: widget.longitude,
      updateCamera: false,
    );
  }

  @override
  void didUpdateWidget(covariant BusinessLocationMapPicker oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (_dragging) return;

    final positionChanged = oldWidget.latitude != widget.latitude ||
        oldWidget.longitude != widget.longitude;
    final radiusChanged =
        oldWidget.geofenceRadiusM != widget.geofenceRadiusM;
    final focusChanged = oldWidget.focusToken != widget.focusToken;

    if (positionChanged || focusChanged) {
      final sameAsLive = _isNearlySame(
        _center.value,
        widget.latitude,
        widget.longitude,
      );
      if (!sameAsLive || focusChanged) {
        _syncFromProps(
          latitude: widget.latitude,
          longitude: widget.longitude,
          updateCamera: true,
        );
      }
    } else if (radiusChanged) {
      // Resize only — keep center fixed; gently adjust zoom for readability.
      setState(() {});
      _requestCameraFit(animate: true, debounce: true);
    }
  }

  @override
  void dispose() {
    _cameraDebounce?.cancel();
    _liveNotifyDebounce?.cancel();
    _moveAnimation?.dispose();
    _center.dispose();
    _mapController.dispose();
    super.dispose();
  }

  bool _isNearlySame(LatLng? point, double? lat, double? lng) {
    if (point == null || lat == null || lng == null) return false;
    return (point.latitude - lat).abs() < 1e-7 &&
        (point.longitude - lng).abs() < 1e-7;
  }

  void _syncFromProps({
    required double? latitude,
    required double? longitude,
    required bool updateCamera,
  }) {
    if (latitude == null || longitude == null) {
      _center.value = null;
      return;
    }
    _center.value = LatLng(latitude, longitude);
    if (updateCamera) {
      _requestCameraFit(animate: true, debounce: false);
    }
  }

  void _commitPosition(LatLng position, {required bool animateCamera}) {
    _center.value = position;
    if (animateCamera) {
      _requestCameraFit(animate: true, debounce: false);
    }
    widget.onPositionChanged(position);
  }

  void _onMapTapped(TapPosition _, LatLng point) {
    if (_dragging) return;
    _commitPosition(point, animateCamera: true);
  }

  void _beginDrag(int pointer, Offset localPosition) {
    _moveAnimation?.stop();
    _cameraDebounce?.cancel();
    _activePointer = pointer;
    _lastPointerLocal = localPosition;
    _dragMoved = false;
    if (!_dragging) {
      setState(() => _dragging = true);
    }
  }

  void _notifyParentLive(LatLng position) {
    _pendingLiveNotify = position;
    if (_liveNotifyDebounce?.isActive ?? false) return;
    _liveNotifyDebounce = Timer(const Duration(milliseconds: 33), () {
      final pending = _pendingLiveNotify;
      if (pending != null) {
        widget.onPositionChanged(pending);
      }
    });
  }

  void _updateDrag(Offset localPosition) {
    final last = _lastPointerLocal;
    final current = _center.value;
    if (last == null || current == null) return;

    final delta = localPosition - last;
    if (delta.distanceSquared > 0.25) {
      _dragMoved = true;
    }
    _lastPointerLocal = localPosition;

    try {
      final camera = _mapController.camera;
      final screen = camera.latLngToScreenOffset(current) + delta;
      final next = camera.screenOffsetToLatLng(screen);
      _center.value = next;
      _notifyParentLive(next);
    } catch (_) {
      // Map not ready.
    }
  }

  void _endDrag() {
    final position = _center.value;
    final moved = _dragMoved;
    _activePointer = null;
    _lastPointerLocal = null;
    _dragMoved = false;
    _liveNotifyDebounce?.cancel();
    _pendingLiveNotify = null;
    if (_dragging) {
      setState(() => _dragging = false);
    }
    if (position == null) return;
    // Always commit final coordinates; animate only after a real drag.
    _commitPosition(position, animateCamera: moved);
  }

  double zoomForRadiusMeters(double radiusM, double latitude) {
    const targetPixels = 260.0;
    final cosLat =
        math.cos(latitude * math.pi / 180.0).abs().clamp(0.25, 1.0);
    final mpp0 = 156543.03392 * cosLat;
    final paddedDiameter = math.max(radiusM, 5.0) * 2.6;
    final zoom = math.log(mpp0 * targetPixels / paddedDiameter) / math.ln2;
    return zoom.clamp(16.0, 18.5);
  }

  void _requestCameraFit({
    required bool animate,
    required bool debounce,
  }) {
    if (_dragging) return;
    _pendingCameraFit = true;
    _cameraDebounce?.cancel();
    if (!debounce) {
      unawaited(_runCameraFit(animate: animate));
      return;
    }
    _cameraDebounce = Timer(const Duration(milliseconds: 70), () {
      unawaited(_runCameraFit(animate: animate));
    });
  }

  Future<void> _runCameraFit({required bool animate}) async {
    if (!_mapReady || _dragging) {
      _pendingCameraFit = true;
      return;
    }

    final marker = _center.value;
    if (marker == null) {
      _pendingCameraFit = true;
      return;
    }

    _pendingCameraFit = false;
    final token = ++_cameraToken;
    final radius = widget.geofenceRadiusM
        .clamp(kMinGeofenceRadiusM, kMaxGeofenceRadiusM)
        .toDouble();
    final zoom = zoomForRadiusMeters(radius, marker.latitude);

    try {
      if (animate) {
        await _animateMapTo(marker, zoom, token);
      } else {
        _mapController.move(marker, zoom);
      }
    } catch (_) {
      if (!mounted || token != _cameraToken) return;
      try {
        _mapController.move(marker, zoom);
      } catch (_) {
        _pendingCameraFit = true;
      }
    }
  }

  Future<void> _animateMapTo(LatLng dest, double zoom, int token) async {
    _moveAnimation?.stop();
    _moveAnimation?.dispose();

    LatLng startCenter;
    double startZoom;
    try {
      startCenter = _mapController.camera.center;
      startZoom = _mapController.camera.zoom;
    } catch (_) {
      _mapController.move(dest, zoom);
      return;
    }

    final controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 420),
    );
    _moveAnimation = controller;
    final curve = CurvedAnimation(parent: controller, curve: Curves.easeInOut);

    void tick() {
      if (!mounted || token != _cameraToken || _dragging) return;
      final t = curve.value;
      final lat =
          startCenter.latitude + (dest.latitude - startCenter.latitude) * t;
      final lng =
          startCenter.longitude + (dest.longitude - startCenter.longitude) * t;
      final z = startZoom + (zoom - startZoom) * t;
      _mapController.move(LatLng(lat, lng), z);
    }

    curve.addListener(tick);
    try {
      await controller.forward();
    } finally {
      curve.removeListener(tick);
      if (identical(_moveAnimation, controller)) {
        _moveAnimation = null;
      }
      controller.dispose();
    }
  }

  void _onMapReady() {
    _mapReady = true;
    unawaited(_runCameraFit(animate: false));
    if (_pendingCameraFit) {
      unawaited(Future<void>.delayed(const Duration(milliseconds: 80), () {
        if (mounted) unawaited(_runCameraFit(animate: true));
      }));
    }
  }

  int get _interactionFlags {
    const base = InteractiveFlag.all & ~InteractiveFlag.rotate;
    if (!_dragging) return base;
    return base &
        ~InteractiveFlag.drag &
        ~InteractiveFlag.flingAnimation &
        ~InteractiveFlag.pinchMove;
  }

  @override
  Widget build(BuildContext context) {
    final seed = _center.value;
    final radius = widget.geofenceRadiusM
        .clamp(kMinGeofenceRadiusM, kMaxGeofenceRadiusM)
        .toDouble();
    final initialCenter = seed ??
        const LatLng(kDefaultBusinessLatitude, kDefaultBusinessLongitude);
    final initialZoom =
        seed == null ? 12.0 : zoomForRadiusMeters(radius, seed.latitude);

    final map = FlutterMap(
      mapController: _mapController,
      options: MapOptions(
        initialCenter: initialCenter,
        initialZoom: initialZoom,
        minZoom: 3,
        maxZoom: 19,
        interactionOptions: InteractionOptions(flags: _interactionFlags),
        onMapReady: _onMapReady,
        onTap: _onMapTapped,
      ),
      children: [
        TileLayer(
          urlTemplate: _tileUrl,
          userAgentPackageName: _userAgent,
          maxZoom: 19,
          keepBuffer: 2,
          panBuffer: 1,
        ),
        ValueListenableBuilder<LatLng?>(
          valueListenable: _center,
          builder: (context, center, _) {
            if (center == null) return const SizedBox.shrink();
            final r = widget.geofenceRadiusM
                .clamp(kMinGeofenceRadiusM, kMaxGeofenceRadiusM)
                .toDouble();
            // Visual only — keep as a direct map layer (not nested in Stack)
            // so projection matches the circle exactly.
            return IgnorePointer(
              child: CircleLayer(
                circles: [
                  CircleMarker(
                    point: center,
                    radius: r,
                    useRadiusInMeter: true,
                    color: _fill,
                    borderColor: _stroke,
                    borderStrokeWidth: 3,
                  ),
                ],
              ),
            );
          },
        ),
        ValueListenableBuilder<LatLng?>(
          valueListenable: _center,
          builder: (context, center, _) {
            if (center == null) return const SizedBox.shrink();
            // Same [center] LatLng as CircleMarker.point — Alignment.center
            // places the hotspot on that coordinate (circle midpoint).
            return IgnorePointer(
              child: MarkerLayer(
                markers: [
                  Marker(
                    point: center,
                    width: 48,
                    height: 48,
                    alignment: Alignment.center,
                    child: _BusinessLocationMarker(dragging: _dragging),
                  ),
                ],
              ),
            );
          },
        ),
        _AttendanceAreaDragTarget(
          centerListenable: _center,
          radiusMeters: radius,
          dragging: _dragging,
          onPointerDown: (pointer, local) {
            if (_activePointer != null) return;
            _beginDrag(pointer, local);
          },
          onPointerMove: (pointer, local) {
            if (_activePointer != pointer) return;
            _updateDrag(local);
          },
          onPointerUp: (pointer) {
            if (_activePointer != pointer) return;
            _endDrag();
          },
          onPointerCancel: (pointer) {
            if (_activePointer != pointer) return;
            _endDrag();
          },
        ),
      ],
    );

    final content = Stack(
      fit: StackFit.expand,
      children: [
        Positioned.fill(child: map),
        // Compact attribution outside FlutterMap children so long OSM text
        // cannot overflow and paint Flutter's yellow/black warning stripes.
        const Positioned(
          left: 8,
          bottom: 8,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: Color(0xE6FFFFFF),
              borderRadius: BorderRadius.all(Radius.circular(8)),
            ),
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Text(
                '© OpenStreetMap',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF6B7280),
                ),
              ),
            ),
          ),
        ),
        if (widget.showMyLocationButton)
          Positioned(
            right: 14,
            bottom: 14,
            child: Material(
              color: Colors.white,
              elevation: 3,
              shape: const CircleBorder(),
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: widget.locating ? null : widget.onMyLocationPressed,
                child: SizedBox(
                  width: 46,
                  height: 46,
                  child: Center(
                    child: widget.locating
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Icon(
                            Icons.near_me_rounded,
                            color: Colors.grey.shade800,
                            size: 22,
                          ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );

    final borderRadius = widget.borderRadius;
    final wrapped = borderRadius == null || borderRadius == BorderRadius.zero
        ? content
        : ClipRRect(borderRadius: borderRadius, child: content);

    if (widget.expand) return wrapped;
    return SizedBox(height: widget.height, child: wrapped);
  }
}

/// Hit-tests the geofence disk + pin so dragging either moves the whole area.
/// Outside the attendance area, events pass through to the map (pan/zoom/tap).
class _AttendanceAreaDragTarget extends StatelessWidget {
  const _AttendanceAreaDragTarget({
    required this.centerListenable,
    required this.radiusMeters,
    required this.dragging,
    required this.onPointerDown,
    required this.onPointerMove,
    required this.onPointerUp,
    required this.onPointerCancel,
  });

  final ValueNotifier<LatLng?> centerListenable;
  final double radiusMeters;
  final bool dragging;
  final void Function(int pointer, Offset localPosition) onPointerDown;
  final void Function(int pointer, Offset localPosition) onPointerMove;
  final void Function(int pointer) onPointerUp;
  final void Function(int pointer) onPointerCancel;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<LatLng?>(
      valueListenable: centerListenable,
      builder: (context, center, _) {
        if (center == null) return const SizedBox.shrink();
        final camera = MapCamera.of(context);
        return Listener(
          // Only capture when [_AttendanceHitBox] hits the disk/pin so map
          // pan/zoom/tap still work outside the attendance area.
          behavior: HitTestBehavior.deferToChild,
          onPointerDown: (event) {
            onPointerDown(event.pointer, event.localPosition);
          },
          onPointerMove: (event) {
            if (!dragging) return;
            onPointerMove(event.pointer, event.localPosition);
          },
          onPointerUp: (event) => onPointerUp(event.pointer),
          onPointerCancel: (event) => onPointerCancel(event.pointer),
          child: _AttendanceHitBox(
            center: center,
            radiusMeters: radiusMeters,
            camera: camera,
            forceHit: dragging,
          ),
        );
      },
    );
  }
}

bool _hitsAttendanceArea({
  required Offset localPosition,
  required LatLng center,
  required MapCamera camera,
  required double radiusMeters,
}) {
  final centerPx = camera.latLngToScreenOffset(center);
  final radiusPx = _metersToPixels(
    meters: radiusMeters,
    latitude: center.latitude,
    zoom: camera.zoom,
  );

  final distance = (localPosition - centerPx).distance;
  if (distance <= radiusPx + 4) return true;

  // Pin / center hotspot sits on the geographic point (Alignment.center).
  final pinRect = Rect.fromCenter(
    center: centerPx,
    width: 48,
    height: 48,
  );
  return pinRect.contains(localPosition);
}

double _metersToPixels({
  required double meters,
  required double latitude,
  required double zoom,
}) {
  final cosLat = math.cos(latitude * math.pi / 180.0).abs().clamp(0.25, 1.0);
  final metersPerPixel = 156543.03392 * cosLat / math.pow(2.0, zoom);
  if (metersPerPixel <= 0) return 0;
  return meters / metersPerPixel;
}

/// A zero-paint box that only participates in hit testing over the geofence/pin.
class _AttendanceHitBox extends SingleChildRenderObjectWidget {
  const _AttendanceHitBox({
    required this.center,
    required this.radiusMeters,
    required this.camera,
    required this.forceHit,
  }) : super(child: const SizedBox.expand());

  final LatLng center;
  final double radiusMeters;
  final MapCamera camera;
  final bool forceHit;

  @override
  RenderObject createRenderObject(BuildContext context) {
    return _AttendanceHitRenderBox(
      center: center,
      radiusMeters: radiusMeters,
      camera: camera,
      forceHit: forceHit,
    );
  }

  @override
  void updateRenderObject(
    BuildContext context,
    covariant _AttendanceHitRenderBox renderObject,
  ) {
    renderObject
      ..center = center
      ..radiusMeters = radiusMeters
      ..camera = camera
      ..forceHit = forceHit;
  }
}

class _AttendanceHitRenderBox extends RenderProxyBox {
  _AttendanceHitRenderBox({
    required LatLng center,
    required double radiusMeters,
    required MapCamera camera,
    required bool forceHit,
  })  : _center = center,
        _radiusMeters = radiusMeters,
        _camera = camera,
        _forceHit = forceHit;

  LatLng _center;
  double _radiusMeters;
  MapCamera _camera;
  bool _forceHit;

  set center(LatLng value) {
    if (_center == value) return;
    _center = value;
    markNeedsPaint();
  }

  set radiusMeters(double value) {
    if (_radiusMeters == value) return;
    _radiusMeters = value;
    markNeedsPaint();
  }

  set camera(MapCamera value) {
    _camera = value;
    markNeedsPaint();
  }

  set forceHit(bool value) {
    if (_forceHit == value) return;
    _forceHit = value;
    markNeedsPaint();
  }

  @override
  bool hitTest(BoxHitTestResult result, {required Offset position}) {
    if (_forceHit ||
        _hitsAttendanceArea(
          localPosition: position,
          center: _center,
          camera: _camera,
          radiusMeters: _radiusMeters,
        )) {
      result.add(BoxHitTestEntry(this, position));
      return true;
    }
    return false;
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    // Intentionally empty — visuals come from CircleLayer / MarkerLayer.
  }
}

/// Marker whose geometric center is the business LatLng (circle midpoint).
class _BusinessLocationMarker extends StatelessWidget {
  const _BusinessLocationMarker({required this.dragging});

  final bool dragging;

  static const _red = Color(0xFFE53935);

  @override
  Widget build(BuildContext context) {
    return AnimatedScale(
      scale: dragging ? 1.08 : 1.0,
      duration: const Duration(milliseconds: 120),
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          // Pin rendered above the point; tip aims at the center hotspot.
          Transform.translate(
            offset: const Offset(0, -18),
            child: const Icon(
              Icons.location_on,
              color: _red,
              size: 36,
            ),
          ),
          // Exact business coordinate / geofence center.
          Container(
            width: 16,
            height: 16,
            decoration: BoxDecoration(
              color: _red,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 3),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x66000000),
                  blurRadius: 3,
                  offset: Offset(0, 1),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
