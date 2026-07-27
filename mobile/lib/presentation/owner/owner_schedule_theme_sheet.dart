import 'package:aroll_mobile/core/di/injection.dart';
import 'package:aroll_mobile/core/theme/business_theme_parsing.dart';
import 'package:aroll_mobile/core/theme/schedule_theme.dart';
import 'package:aroll_mobile/data/repositories/owner_repository.dart';
import 'package:aroll_mobile/domain/entities/user_session.dart';
import 'package:aroll_mobile/presentation/shared/schedule_themed_table.dart';
import 'package:flutter/material.dart';

Future<bool?> showOwnerScheduleThemeSheet({
  required BuildContext context,
  required ScheduleTableColors initialColors,
  required ScheduleDisplaySettings initialDisplay,
  required Map<String, dynamic> businessSettings,
}) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (context) => OwnerScheduleThemeSheet(
      initialColors: initialColors,
      initialDisplay: initialDisplay,
      businessSettings: businessSettings,
    ),
  );
}

class OwnerScheduleThemeSheet extends StatefulWidget {
  const OwnerScheduleThemeSheet({
    super.key,
    required this.initialColors,
    required this.initialDisplay,
    required this.businessSettings,
  });

  final ScheduleTableColors initialColors;
  final ScheduleDisplaySettings initialDisplay;
  final Map<String, dynamic> businessSettings;

  @override
  State<OwnerScheduleThemeSheet> createState() =>
      _OwnerScheduleThemeSheetState();
}

class _OwnerScheduleThemeSheetState extends State<OwnerScheduleThemeSheet> {
  final _repo = sl<OwnerRepository>();
  late ScheduleTableColors _colors;
  late ScheduleDisplaySettings _display;
  late TimeOfDay _startTime;
  late TimeOfDay _endTime;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _colors = widget.initialColors;
    _display = widget.initialDisplay;
    _startTime = _parseTime(_display.defaultStart);
    _endTime = _parseTime(_display.defaultEnd);
  }

  TimeOfDay _parseTime(String value) {
    final parts = value.split(':');
    final hour = int.tryParse(parts.first) ?? 9;
    final minute = parts.length > 1 ? int.tryParse(parts[1]) ?? 0 : 0;
    return TimeOfDay(hour: hour, minute: minute);
  }

  String _formatTime(TimeOfDay value) {
    final hour = value.hour.toString().padLeft(2, '0');
    final minute = value.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }

  Future<void> _pickColor(
    String label,
    String current,
    ValueChanged<String> onChanged,
  ) async {
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(label),
        content: BlockPicker(
          current: scheduleColorFromHex(current),
          onChanged: (value) {
            onChanged(value);
            setState(() {});
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Done'),
          ),
        ],
      ),
    );
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final brandingMap =
          widget.businessSettings['branding'] as Map<String, dynamic>? ?? {};
      final branding = businessBrandingFromJson(brandingMap);
      if (branding == null) {
        throw StateError('Business branding unavailable');
      }
      final display = _display.copyWith(
        defaultStart: _formatTime(_startTime),
        defaultEnd: _formatTime(_endTime),
      );
      final updatedBranding = BusinessBrandingSettings(
        logoUrl: branding.logoUrl,
        ownerProfileImageUrl: branding.ownerProfileImageUrl,
        displayImageUrl: branding.displayImageUrl,
        theme: branding.theme.copyWith(
          scheduleColors: _colors,
          scheduleDisplay: display,
        ),
      );
      await _repo.updateBusinessSettings({
        'business_name': widget.businessSettings['business_name'],
        'business_type': widget.businessSettings['business_type'],
        'address': widget.businessSettings['address'],
        'branding': businessBrandingForSave(updatedBranding),
      });
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Unable to save schedule settings')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Customize Schedule Table',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                    ),
                  ),
                  IconButton(
                    onPressed: _saving ? null : () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              const Text(
                'Schedule colors are separate from business branding.',
                style: TextStyle(color: Color(0xFF6B7280), fontSize: 12),
              ),
              const SizedBox(height: 16),
              const Text('Shift times', style: TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _saving
                          ? null
                          : () async {
                              final picked = await showTimePicker(
                                context: context,
                                initialTime: _startTime,
                              );
                              if (picked != null) {
                                setState(() => _startTime = picked);
                              }
                            },
                      child: Text('Start ${_formatTime(_startTime)}'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _saving
                          ? null
                          : () async {
                              final picked = await showTimePicker(
                                context: context,
                                initialTime: _endTime,
                              );
                              if (picked != null) {
                                setState(() => _endTime = picked);
                              }
                            },
                      child: Text('End ${_formatTime(_endTime)}'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              const Text('Visible days', style: TextStyle(fontWeight: FontWeight.w600)),
              Wrap(
                spacing: 8,
                children: scheduleWeekdayLabels.map((day) {
                  final selected = _display.visibleDays.contains(day);
                  return FilterChip(
                    label: Text(day),
                    selected: selected,
                    onSelected: _saving
                        ? null
                        : (_) {
                            setState(() {
                              final days = List<String>.from(_display.visibleDays);
                              if (selected) {
                                days.remove(day);
                              } else {
                                days.add(day);
                              }
                              days.sort(
                                (a, b) => scheduleWeekdayLabels
                                    .indexOf(a)
                                    .compareTo(scheduleWeekdayLabels.indexOf(b)),
                              );
                              _display = _display.copyWith(visibleDays: days);
                            });
                          },
                  );
                }).toList(),
              ),
              const SizedBox(height: 16),
              const Text('Colors', style: TextStyle(fontWeight: FontWeight.w600)),
              _ColorRow(
                label: 'Header',
                value: _colors.header,
                onTap: () => _pickColor('Header', _colors.header, (value) {
                  setState(() => _colors = _colors.copyWith(header: value));
                }),
              ),
              for (final entry in [
                ('Row 1', _colors.row1, (String v) => _colors.copyWith(row1: v)),
                ('Row 2', _colors.row2, (String v) => _colors.copyWith(row2: v)),
                ('Row 3', _colors.row3, (String v) => _colors.copyWith(row3: v)),
                ('Row 4', _colors.row4, (String v) => _colors.copyWith(row4: v)),
                ('Row 5', _colors.row5, (String v) => _colors.copyWith(row5: v)),
                ('Off', _colors.off, (String v) => _colors.copyWith(off: v)),
                ('Text', _colors.text, (String v) => _colors.copyWith(text: v)),
              ])
                _ColorRow(
                  label: entry.$1,
                  value: entry.$2,
                  onTap: () => _pickColor(entry.$1, entry.$2, (value) {
                    setState(() => _colors = entry.$3(value));
                  }),
                ),
              const SizedBox(height: 16),
              ScheduleThemedTable(
                rows: const [
                  ScheduleThemedTableRow(
                    employeeName: 'Preview Employee',
                    dayLabels: ['OFF', '9:00 AM-5:00 PM', '9:00 AM-5:00 PM', 'OFF', '9:00 AM-5:00 PM', 'OFF', 'OFF'],
                  ),
                ],
                weekStart: DateTime.now(),
                colors: _colors,
                display: _display.copyWith(
                  defaultStart: _formatTime(_startTime),
                  defaultEnd: _formatTime(_endTime),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  TextButton(
                    onPressed: _saving
                        ? null
                        : () {
                            setState(() {
                              _colors = ScheduleTableColors.defaults;
                              _display = ScheduleDisplaySettings.defaults;
                              _startTime = _parseTime(_display.defaultStart);
                              _endTime = _parseTime(_display.defaultEnd);
                            });
                          },
                    child: const Text('Reset'),
                  ),
                  const Spacer(),
                  FilledButton(
                    onPressed: _saving ? null : _save,
                    child: Text(_saving ? 'Saving...' : 'Apply Changes'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ColorRow extends StatelessWidget {
  const _ColorRow({
    required this.label,
    required this.value,
    required this.onTap,
  });

  final String label;
  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(label),
      trailing: Container(
        width: 28,
        height: 28,
        decoration: BoxDecoration(
          color: scheduleColorFromHex(value),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: const Color(0xFFE5E7EB)),
        ),
      ),
      onTap: onTap,
    );
  }
}

class BlockPicker extends StatefulWidget {
  const BlockPicker({
    super.key,
    required this.current,
    required this.onChanged,
  });

  final Color current;
  final ValueChanged<String> onChanged;

  @override
  State<BlockPicker> createState() => _BlockPickerState();
}

class _BlockPickerState extends State<BlockPicker> {
  late Color _selected;

  static const _palette = [
    '#1E3A5F',
    '#FFE5A3',
    '#FFB166',
    '#B8F28C',
    '#B9D8F7',
    '#F2A7EA',
    '#F8B4B4',
    '#111827',
    '#FFFFFF',
    '#6B7280',
  ];

  @override
  void initState() {
    super.initState();
    _selected = widget.current;
  }

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: _palette.map((hex) {
        final color = scheduleColorFromHex(hex);
        final selected = scheduleColorToHex(_selected) == hex.toUpperCase();
        return InkWell(
          onTap: () {
            setState(() => _selected = color);
            widget.onChanged(hex);
          },
          child: Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: selected ? Colors.black : const Color(0xFFE5E7EB),
                width: selected ? 2 : 1,
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}
