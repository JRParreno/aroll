import 'package:aroll_mobile/presentation/owner/owner_schedule_table_style.dart';
import 'package:aroll_mobile/presentation/owner/owner_schedule_utils.dart';
import 'package:aroll_mobile/presentation/shared/app_ui.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class OwnerColorScheduleTable extends StatelessWidget {
  const OwnerColorScheduleTable({
    super.key,
    required this.rows,
    required this.weekStart,
    required this.colors,
    required this.visibleDays,
    required this.defaultStart,
    required this.defaultEnd,
  });

  final List<Map<String, dynamic>> rows;
  final DateTime weekStart;
  final OwnerScheduleTableColors colors;
  final List<String> visibleDays;
  final String defaultStart;
  final String defaultEnd;

  @override
  Widget build(BuildContext context) {
    final weekDays = ownerWeekDays(weekStart);
    final visibleIndexes = ownerWeekdayLabels
        .asMap()
        .entries
        .where((entry) => visibleDays.contains(entry.value))
        .map((entry) => MapEntry(entry.value, entry.key))
        .toList(growable: false);
    final rowColors = colors.rowColors;

    String cellLabel(List<Map<String, dynamic>> dayCells) {
      final label = ownerScheduleViewerCellLabel(dayCells);
      if (label == 'OFF') return label;
      if (label.isEmpty) {
        return '${formatOwnerShiftTime(defaultStart)}-${formatOwnerShiftTime(defaultEnd)}';
      }
      return label;
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minWidth: 720),
        child: Table(
          defaultColumnWidth: const IntrinsicColumnWidth(),
          border: TableBorder.all(
            color: Colors.white.withValues(alpha: 0.45),
            width: 1,
          ),
          children: [
            TableRow(
              decoration: BoxDecoration(color: colors.header),
              children: [
                _headerCell('Employee', align: TextAlign.left),
                ...visibleIndexes.map(
                  (entry) => _headerCell(
                    entry.key,
                    tooltip: ownerDateKey(weekDays[entry.value]),
                  ),
                ),
              ],
            ),
            if (rows.isEmpty)
              TableRow(
                children: [
                  TableCell(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 28,
                      ),
                      child: Text(
                        'No schedule records found.',
                        textAlign: TextAlign.center,
                        style: appMutedStyle(),
                      ),
                    ),
                  ),
                  ...visibleIndexes.map((_) => const SizedBox.shrink()),
                ],
              )
            else
              ...rows.asMap().entries.map((entry) {
                final rowIndex = entry.key;
                final row = entry.value;
                final employee = row['employee'] as Map<String, dynamic>;
                final cells =
                    row['cells'] as List<List<Map<String, dynamic>>>;
                final rowBg = rowColors[rowIndex % rowColors.length];

                return TableRow(
                  decoration: BoxDecoration(color: rowBg),
                  children: [
                    _bodyCell(
                      '${employee['full_name'] ?? 'Employee'}',
                      textColor: colors.text,
                      align: TextAlign.left,
                      bold: true,
                    ),
                    ...visibleIndexes.map((dayEntry) {
                      final index = dayEntry.value;
                      final dayCells = index < cells.length
                          ? cells[index]
                          : const <Map<String, dynamic>>[];
                      final label = cellLabel(dayCells);
                      final isOff = label == 'OFF';
                      final onLeaveOnly = dayCells.isNotEmpty &&
                          dayCells.every(
                            (cell) =>
                                cell['on_leave'] == true &&
                                cell['assigned_during_leave'] != true,
                          );
                      return _bodyCell(
                        label,
                        textColor: colors.text,
                        background: isOff
                            ? colors.off
                            : onLeaveOnly
                                ? OwnerScheduleTableColors.onLeave
                                : null,
                      );
                    }),
                  ],
                );
              }),
          ],
        ),
      ),
    );
  }

  Widget _headerCell(String label, {TextAlign align = TextAlign.center, String? tooltip}) {
    final child = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Text(
        label,
        textAlign: align,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
    if (tooltip == null) return child;
    return Tooltip(message: tooltip, child: child);
  }

  Widget _bodyCell(
    String label, {
    required Color textColor,
    TextAlign align = TextAlign.center,
    bool bold = false,
    Color? background,
  }) {
    return Container(
      color: background,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Text(
        label,
        textAlign: align,
        style: TextStyle(
          color: textColor,
          fontSize: 11,
          fontWeight: bold ? FontWeight.w600 : FontWeight.w500,
        ),
      ),
    );
  }
}

Future<void> showOwnerScheduleCustomizeSheet({
  required BuildContext context,
  required OwnerScheduleTableColors colors,
  required List<String> visibleDays,
  required String defaultStart,
  required String defaultEnd,
  required List<Map<String, dynamic>> previewRows,
  required DateTime weekStart,
  required void Function({
    required OwnerScheduleTableColors colors,
    required List<String> visibleDays,
    required String defaultStart,
    required String defaultEnd,
  }) onApply,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (context) {
      return _CustomizeSheet(
        initialColors: colors,
        initialVisibleDays: visibleDays,
        initialDefaultStart: defaultStart,
        initialDefaultEnd: defaultEnd,
        previewRows: previewRows,
        weekStart: weekStart,
        onApply: onApply,
      );
    },
  );
}

class _CustomizeSheet extends StatefulWidget {
  const _CustomizeSheet({
    required this.initialColors,
    required this.initialVisibleDays,
    required this.initialDefaultStart,
    required this.initialDefaultEnd,
    required this.previewRows,
    required this.weekStart,
    required this.onApply,
  });

  final OwnerScheduleTableColors initialColors;
  final List<String> initialVisibleDays;
  final String initialDefaultStart;
  final String initialDefaultEnd;
  final List<Map<String, dynamic>> previewRows;
  final DateTime weekStart;
  final void Function({
    required OwnerScheduleTableColors colors,
    required List<String> visibleDays,
    required String defaultStart,
    required String defaultEnd,
  }) onApply;

  @override
  State<_CustomizeSheet> createState() => _CustomizeSheetState();
}

class _CustomizeSheetState extends State<_CustomizeSheet> {
  late OwnerScheduleTableColors _colors;
  late List<String> _visibleDays;
  late String _defaultStart;
  late String _defaultEnd;

  @override
  void initState() {
    super.initState();
    _colors = widget.initialColors;
    _visibleDays = List<String>.from(widget.initialVisibleDays);
    _defaultStart = widget.initialDefaultStart;
    _defaultEnd = widget.initialDefaultEnd;
  }

  Future<void> _pickTime({required bool isStart}) async {
    final current = ownerScheduleParseTimeOfDay(
      isStart ? _defaultStart : _defaultEnd,
    );
    final picked = await showTimePicker(
      context: context,
      initialTime: current,
    );
    if (picked == null) return;
    setState(() {
      final value = ownerScheduleTimeOfDayToString(picked);
      if (isStart) {
        _defaultStart = value;
      } else {
        _defaultEnd = value;
      }
    });
  }

  Future<void> _pickColor({
    required String label,
    required Color current,
    required ValueChanged<Color> onChanged,
  }) async {
    final selected = await showDialog<Color>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(label),
          content: Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              for (final color in OwnerScheduleTableColors.swatchPalette)
                InkWell(
                  onTap: () => Navigator.of(context).pop(color),
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: color,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: color == current
                            ? AppColors.primaryDark
                            : const Color(0xFFD1D5DB),
                        width: color == current ? 2 : 1,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
          ],
        );
      },
    );
    if (selected != null) onChanged(selected);
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.paddingOf(context).bottom;
    return DraggableScrollableSheet(
      initialChildSize: 0.92,
      minChildSize: 0.55,
      maxChildSize: 0.96,
      builder: (context, scrollController) {
        return Container(
          decoration: const BoxDecoration(
            color: AppColors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            children: [
              const SizedBox(height: 10),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: const Color(0xFFD1D5DB),
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 8, 8),
                child: Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Customize Table',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView(
                  controller: scrollController,
                  padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + bottom),
                  children: [
                    Text('Shift Times', style: appSectionTitleStyle()),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => _pickTime(isStart: true),
                            child: Text(formatOwnerShiftTime(_defaultStart)),
                          ),
                        ),
                        const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 8),
                          child: Text('-'),
                        ),
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => _pickTime(isStart: false),
                            child: Text(formatOwnerShiftTime(_defaultEnd)),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    Text('Days of the Week', style: appSectionTitleStyle()),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      children: ownerWeekdayLabels.map((day) {
                        final checked = _visibleDays.contains(day);
                        return FilterChip(
                          label: Text(day),
                          selected: checked,
                          onSelected: (selected) {
                            setState(() {
                              if (selected) {
                                if (!_visibleDays.contains(day)) {
                                  _visibleDays = [
                                    ...ownerWeekdayLabels.where(
                                      (label) =>
                                          label == day ||
                                          _visibleDays.contains(label),
                                    ),
                                  ];
                                }
                              } else if (_visibleDays.length > 1) {
                                _visibleDays = _visibleDays
                                    .where((item) => item != day)
                                    .toList();
                              }
                            });
                          },
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 18),
                    Text('Color Settings', style: appSectionTitleStyle()),
                    Text(
                      'Set colors used by table rows.',
                      style: appMutedStyle().copyWith(fontSize: 12),
                    ),
                    const SizedBox(height: 8),
                    _colorRow(
                      'Header Color',
                      _colors.header,
                      (color) =>
                          setState(() => _colors = _colors.copyWith(header: color)),
                    ),
                    _colorRow(
                      'Row Color 1',
                      _colors.row1,
                      (color) =>
                          setState(() => _colors = _colors.copyWith(row1: color)),
                    ),
                    _colorRow(
                      'Row Color 2',
                      _colors.row2,
                      (color) =>
                          setState(() => _colors = _colors.copyWith(row2: color)),
                    ),
                    _colorRow(
                      'Row Color 3',
                      _colors.row3,
                      (color) =>
                          setState(() => _colors = _colors.copyWith(row3: color)),
                    ),
                    _colorRow(
                      'Row Color 4',
                      _colors.row4,
                      (color) =>
                          setState(() => _colors = _colors.copyWith(row4: color)),
                    ),
                    _colorRow(
                      'Row Color 5',
                      _colors.row5,
                      (color) =>
                          setState(() => _colors = _colors.copyWith(row5: color)),
                    ),
                    _colorRow(
                      'Off',
                      _colors.off,
                      (color) =>
                          setState(() => _colors = _colors.copyWith(off: color)),
                    ),
                    const SizedBox(height: 14),
                    Text('Text Color', style: appSectionTitleStyle()),
                    const SizedBox(height: 8),
                    Row(
                      children: OwnerScheduleTableColors.textChoices.map((color) {
                        final selected = color == _colors.text;
                        return Padding(
                          padding: const EdgeInsets.only(right: 10),
                          child: InkWell(
                            onTap: () => setState(
                              () => _colors = _colors.copyWith(text: color),
                            ),
                            borderRadius: BorderRadius.circular(8),
                            child: Container(
                              width: 36,
                              height: 36,
                              decoration: BoxDecoration(
                                color: color,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: selected
                                      ? AppColors.primaryDark
                                      : const Color(0xFFD1D5DB),
                                  width: selected ? 2 : 1,
                                ),
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 18),
                    Text('Preview', style: appSectionTitleStyle()),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFAFBFC),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: OwnerColorScheduleTable(
                        rows: widget.previewRows.take(5).toList(growable: false),
                        weekStart: widget.weekStart,
                        colors: _colors,
                        visibleDays: _visibleDays,
                        defaultStart: _defaultStart,
                        defaultEnd: _defaultEnd,
                      ),
                    ),
                    const SizedBox(height: 18),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () {
                              setState(() {
                                _colors = OwnerScheduleTableColors.defaults;
                              });
                            },
                            child: const Text('Reset'),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: FilledButton(
                            style: FilledButton.styleFrom(
                              backgroundColor: AppColors.primaryDark,
                            ),
                            onPressed: () {
                              widget.onApply(
                                colors: _colors,
                                visibleDays: List<String>.from(_visibleDays),
                                defaultStart: _defaultStart,
                                defaultEnd: _defaultEnd,
                              );
                              Navigator.of(context).pop();
                            },
                            child: const Text('Apply Changes'),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Week of ${DateFormat.yMMMd().format(widget.weekStart)}',
                      style: appMutedStyle().copyWith(fontSize: 11),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _colorRow(
    String label,
    Color value,
    ValueChanged<Color> onChanged,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 14,
                color: Color(0xFF374151),
              ),
            ),
          ),
          InkWell(
            onTap: () => _pickColor(
              label: label,
              current: value,
              onChanged: onChanged,
            ),
            borderRadius: BorderRadius.circular(8),
            child: Container(
              width: 40,
              height: 28,
              decoration: BoxDecoration(
                color: value,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFFD1D5DB)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
