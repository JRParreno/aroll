import 'package:aroll_mobile/core/theme/schedule_theme.dart';
import 'package:aroll_mobile/presentation/owner/owner_schedule_utils.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class ScheduleThemedTableRow {
  const ScheduleThemedTableRow({
    required this.employeeName,
    required this.dayLabels,
  });

  final String employeeName;
  final List<String> dayLabels;
}

class ScheduleThemedTable extends StatelessWidget {
  const ScheduleThemedTable({
    super.key,
    required this.rows,
    required this.weekStart,
    required this.colors,
    required this.display,
    this.emptyMessage = 'No schedule records found.',
  });

  final List<ScheduleThemedTableRow> rows;
  final DateTime weekStart;
  final ScheduleTableColors colors;
  final ScheduleDisplaySettings display;
  final String emptyMessage;

  @override
  Widget build(BuildContext context) {
    final weekDays = ownerWeekDays(weekStart);
    final visibleIndexes = scheduleWeekdayLabels
        .asMap()
        .entries
        .where((entry) => display.visibleDays.contains(entry.value))
        .toList(growable: false);
    final headerColor = scheduleColorFromHex(colors.header);
    final textColor = scheduleColorFromHex(colors.text);
    final offColor = scheduleColorFromHex(colors.off);
    final rowColors = colors.rowPalette.map(scheduleColorFromHex).toList();

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
      ),
      padding: const EdgeInsets.all(12),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          headingRowColor: WidgetStateProperty.all(headerColor),
          dataTextStyle: TextStyle(fontSize: 11, color: textColor),
          columns: [
            DataColumn(
              label: Text(
                'Employee',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            ...visibleIndexes.map(
              (entry) => DataColumn(
                label: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      entry.value,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      DateFormat('yyyy-MM-dd').format(weekDays[entry.key]),
                      style: const TextStyle(color: Colors.white70, fontSize: 10),
                    ),
                  ],
                ),
              ),
            ),
          ],
          rows: rows.isEmpty
              ? [
                  DataRow(
                    cells: [
                      DataCell(Text(emptyMessage)),
                      ...List.generate(
                        visibleIndexes.length,
                        (_) => const DataCell(SizedBox.shrink()),
                      ),
                    ],
                  ),
                ]
              : rows.asMap().entries.map((entry) {
                  final rowIndex = entry.key;
                  final row = entry.value;
                  final rowBackground = rowColors[rowIndex % rowColors.length];
                  return DataRow(
                    color: WidgetStateProperty.all(rowBackground),
                    cells: [
                      DataCell(
                        Text(
                          row.employeeName,
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: textColor,
                          ),
                        ),
                      ),
                      ...visibleIndexes.map((dayEntry) {
                        final label = row.dayLabels[dayEntry.key];
                        final isOff = label == 'OFF';
                        return DataCell(
                          Container(
                            color: isOff ? offColor : null,
                            alignment: Alignment.center,
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            child: Text(
                              label,
                              textAlign: TextAlign.center,
                              style: TextStyle(fontSize: 11, color: textColor),
                            ),
                          ),
                        );
                      }),
                    ],
                  );
                }).toList(),
        ),
      ),
    );
  }
}

String scheduleCellTimeLabel({
  required String startTime,
  required String endTime,
  required ScheduleDisplaySettings display,
}) {
  final start = formatOwnerShiftTime(startTime);
  final end = formatOwnerShiftTime(endTime);
  if (start.isEmpty && end.isEmpty) {
    final fallbackStart = formatOwnerShiftTime(display.defaultStart);
    final fallbackEnd = formatOwnerShiftTime(display.defaultEnd);
    return '$fallbackStart-$fallbackEnd';
  }
  return '$start-$end';
}

List<String> scheduleDayLabelsFromAssignments({
  required List<List<Map<String, dynamic>>> cells,
  required ScheduleDisplaySettings display,
}) {
  return List.generate(cells.length, (index) {
    final dayAssignments = cells[index];
    if (dayAssignments.isEmpty) return 'OFF';
    return dayAssignments
        .map(
          (assignment) => scheduleCellTimeLabel(
            startTime: '${assignment['shift_start_time']}',
            endTime: '${assignment['shift_end_time']}',
            display: display,
          ),
        )
        .join(', ');
  });
}
