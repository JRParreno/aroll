import 'dart:io';

import 'package:aroll_mobile/core/location/workplace_wifi.dart';
import 'package:aroll_mobile/data/repositories/owner_repository.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

/// Owner management for the saved worksite. Does not read Wi-Fi during build.
class WorkplaceWifiSection extends StatefulWidget {
  const WorkplaceWifiSection({
    super.key,
    required OwnerRepository repository,
    required this.radiusM,
    this.reader,
    this.isAndroid,
  }) : _repository = repository,
       _loadPoints = null,
       _loadRssi = null,
       _saveRssi = null;

  /// Loads and saves through the supplied functions so the dropdown can be
  /// tested without an API client.
  @visibleForTesting
  const WorkplaceWifiSection.testing({
    super.key,
    required this.radiusM,
    required Future<List<Map<String, dynamic>>> Function() loadPoints,
    required Future<Map<String, dynamic>> Function() loadRssi,
    required Future<Map<String, dynamic>> Function(int? minimumRssiDbm) saveRssi,
    this.reader,
    this.isAndroid = false,
  }) : _repository = null,
       _loadPoints = loadPoints,
       _loadRssi = loadRssi,
       _saveRssi = saveRssi;

  final OwnerRepository? _repository;
  final double radiusM;
  final WorkplaceWifiReader? reader;
  final bool? isAndroid;
  final Future<List<Map<String, dynamic>>> Function()? _loadPoints;
  final Future<Map<String, dynamic>> Function()? _loadRssi;
  final Future<Map<String, dynamic>> Function(int? minimumRssiDbm)? _saveRssi;

  @override
  State<WorkplaceWifiSection> createState() => _WorkplaceWifiSectionState();
}

class _WorkplaceWifiSectionState extends State<WorkplaceWifiSection> {
  List<Map<String, dynamic>> _points = const [];
  bool _loading = true;
  bool _busy = false;
  String? _error;
  int? _minimumRssiDbm;
  RssiThresholdPreset _rssiPreset = RssiThresholdPreset.off;
  final _rssiController = TextEditingController();

  WorkplaceWifiReader get _reader =>
      widget.reader ?? PlatformWorkplaceWifiReader(isAndroid: widget.isAndroid);

  bool get _android => widget.isAndroid ?? Platform.isAndroid;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _rssiController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final rows = widget._loadPoints != null
          ? await widget._loadPoints!()
          : await widget._repository!.workplaceWifiAccessPoints();
      final setting = widget._loadRssi != null
          ? await widget._loadRssi!()
          : await widget._repository!.workplaceWifiRssiSetting();
      if (!mounted) return;
      final stored = setting['minimum_rssi_dbm'];
      final minimum = stored == null
          ? null
          : stored is int
              ? stored
              : int.tryParse('$stored');
      final choice = rssiThresholdChoiceFromSaved(minimum);
      setState(() {
        _points = rows;
        _minimumRssiDbm = minimum;
        _rssiPreset = choice.preset;
        _rssiController.text = choice.customText;
        _loading = false;
        _error = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = _message(error);
      });
    }
  }

  Future<void> _register() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final location = await Permission.locationWhenInUse.request();
      if (!location.isGranted) {
        _show('Allow location access so this phone can read the connected Wi-Fi.');
        return;
      }
      final snapshot = await _reader.readConnected();
      final bssid = bssidToSubmit(snapshot);
      if (bssid == null) {
        _show(_readMessage(snapshot.status));
        return;
      }
      if (!mounted) return;
      final label = await _askLabel(snapshot.ssid, bssid);
      if (label == null || !mounted) return;
      await widget._repository!.registerWorkplaceWifi(
        label: label,
        bssid: bssid,
        ssid: snapshot.ssid,
      );
      await _load();
    } catch (error) {
      _show(_message(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<String?> _askLabel(String? ssid, String bssid) {
    final controller = TextEditingController(
      text: (ssid == null || ssid.isEmpty) ? 'Workplace Wi-Fi' : ssid,
    );
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Save this access point?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(ssid == null || ssid.isEmpty ? 'Network name unavailable' : ssid),
            const SizedBox(height: 4),
            Text(bssid, style: const TextStyle(fontFamily: 'monospace')),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              decoration: const InputDecoration(labelText: 'Name'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  void _selectRssiPreset(RssiThresholdPreset preset) {
    if (preset == RssiThresholdPreset.custom &&
        _rssiPreset != RssiThresholdPreset.custom &&
        _rssiController.text.trim().isEmpty) {
      for (final option in rssiThresholdOptions) {
        if (option.preset == _rssiPreset && option.dbm != null) {
          _rssiController.text = '${option.dbm}';
        }
      }
    }
    setState(() => _rssiPreset = preset);
  }

  Future<void> _saveRssi() async {
    if (!rssiThresholdSelectionIsValid(_rssiPreset, _rssiController.text)) {
      _show('Enter a whole number from -120 to -20 dBm.');
      return;
    }
    setState(() => _busy = true);
    try {
      final value = rssiThresholdValueToSave(_rssiPreset, _rssiController.text);
      final saved = widget._saveRssi != null
          ? await widget._saveRssi!(value)
          : await widget._repository!.updateWorkplaceWifiRssi(value);
      if (!mounted) return;
      final stored = saved['minimum_rssi_dbm'];
      final minimum = stored is int ? stored : null;
      final choice = rssiThresholdChoiceFromSaved(minimum);
      setState(() {
        _minimumRssiDbm = minimum;
        _rssiPreset = choice.preset;
        _rssiController.text = choice.customText;
      });
      _show(
        minimum == null
            ? 'Signal-strength check is off.'
            : '${rssiThresholdStatus(minimum)}.',
      );
    } catch (error) {
      _show(_message(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _setEnabled(Map<String, dynamic> row, bool enabled) async {
    await widget._repository!.updateWorkplaceWifi(
      row['id'].toString(),
      enabled: enabled,
    );
    await _load();
  }

  Future<void> _remove(Map<String, dynamic> row) async {
    await widget._repository!.deleteWorkplaceWifi(row['id'].toString());
    await _load();
  }

  void _show(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final checksApply = widget.radiusM < 20;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Workplace Wi-Fi',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          Text(
            checksApply
                ? 'Optional. Attendance still uses the map boundary first.'
                : 'Saved networks are checked only when the work area is under 20 m.',
            style: const TextStyle(fontSize: 12, height: 1.35),
          ),
          const SizedBox(height: 8),
          Text(
            rssiThresholdStatus(_minimumRssiDbm),
            style: const TextStyle(fontSize: 12, height: 1.35),
          ),
          const SizedBox(height: 4),
          const Text(
            rssiThresholdExplanation,
            style: TextStyle(fontSize: 12, height: 1.35, color: Color(0xFF64748B)),
          ),
          const SizedBox(height: 8),
          DropdownButtonFormField<RssiThresholdPreset>(
            initialValue: _rssiPreset,
            isExpanded: true,
            isDense: false,
            decoration: const InputDecoration(
              labelText: 'Signal requirement',
              border: OutlineInputBorder(),
              contentPadding: EdgeInsets.fromLTRB(12, 16, 12, 12),
            ),
            selectedItemBuilder: (context) => [
              for (final option in rssiThresholdOptions)
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    option.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
            items: [
              for (final option in rssiThresholdOptions)
                DropdownMenuItem(
                  value: option.preset,
                  child: Text(option.label),
                ),
            ],
            onChanged: _busy
                ? null
                : (value) {
                    if (value != null) _selectRssiPreset(value);
                  },
          ),
          if (_rssiPreset == RssiThresholdPreset.custom) ...[
            const SizedBox(height: 8),
            TextField(
              controller: _rssiController,
              keyboardType: const TextInputType.numberWithOptions(signed: true),
              decoration: const InputDecoration(
                labelText: 'Custom minimum (dBm)',
                hintText: '-55',
                helperText:
                    'Enter a whole number from -120 to -20. A number closer to zero requires a stronger signal.',
                isDense: true,
              ),
            ),
          ],
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: _busy ? null : _saveRssi,
              child: const Text('Save signal check'),
            ),
          ),
          if (!_android) ...[
            const SizedBox(height: 8),
            const Text(
              workplaceWifiAndroidOnlyMessage,
              style: TextStyle(fontSize: 12, height: 1.35),
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!, style: const TextStyle(color: Color(0xFFB91C1C), fontSize: 12)),
          ],
          if (_loading)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: LinearProgressIndicator(),
            )
          else
            for (final row in _points)
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(row['label']?.toString() ?? 'Access point'),
                subtitle: Text(
                  [
                    if ((row['ssid']?.toString() ?? '').isNotEmpty) row['ssid'],
                    row['bssid'],
                    row['enabled'] == true ? 'Enabled' : 'Disabled',
                  ].join(' · '),
                ),
                trailing: PopupMenuButton<String>(
                  onSelected: (value) {
                    if (value == 'toggle') {
                      _setEnabled(row, row['enabled'] != true);
                    } else if (value == 'remove') {
                      _remove(row);
                    }
                  },
                  itemBuilder: (context) => [
                    PopupMenuItem(
                      value: 'toggle',
                      child: Text(row['enabled'] == true ? 'Disable' : 'Enable'),
                    ),
                    const PopupMenuItem(value: 'remove', child: Text('Remove')),
                  ],
                ),
              ),
          if (_android)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: _busy ? null : _register,
                child: Text(_busy ? 'Reading Wi-Fi…' : 'Use the connected Wi-Fi'),
              ),
            ),
        ],
      ),
    );
  }
}

String _readMessage(WorkplaceWifiReadStatus status) =>
    workplaceWifiReadMessage(status);

String _message(Object error) {
  if (error is DioException) {
    final data = error.response?.data;
    if (data is Map) {
      final detail = data['detail'];
      if (detail is String && detail.isNotEmpty) return detail;
      if (detail is Map && detail['message'] != null) {
        return detail['message'].toString();
      }
    }
  }
  return 'Workplace Wi-Fi could not be updated.';
}
