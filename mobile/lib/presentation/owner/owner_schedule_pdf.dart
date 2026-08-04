import 'dart:io';
import 'dart:ui' show Color;

import 'package:aroll_mobile/presentation/owner/owner_schedule_table_style.dart';
import 'package:aroll_mobile/presentation/owner/owner_schedule_utils.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

PdfColor _pdfColor(Color color) {
  // ignore: deprecated_member_use
  return PdfColor.fromInt(color.value);
}

Future<String> generateOwnerSchedulePdf({
  required String businessName,
  required DateTime weekStart,
  required List<Map<String, dynamic>> rows,
  required OwnerScheduleTableColors colors,
  required List<String> visibleDays,
  required String defaultStart,
  required String defaultEnd,
}) async {
  final doc = pw.Document();
  final weekDays = ownerWeekDays(weekStart);
  final visibleIndexes = ownerWeekdayLabels
      .asMap()
      .entries
      .where((entry) => visibleDays.contains(entry.value))
      .map((entry) => entry.key)
      .toList(growable: false);
  final rowColors =
      colors.rowColors.map(_pdfColor).toList(growable: false);
  final headerColor = _pdfColor(colors.header);
  final textColor = _pdfColor(colors.text);
  final offColor = _pdfColor(colors.off);
  final onLeaveColor = _pdfColor(OwnerScheduleTableColors.onLeave);

  String cellLabel(List<Map<String, dynamic>> dayAssignments) {
    final label = ownerScheduleViewerCellLabel(dayAssignments);
    if (label == 'OFF') return label;
    if (label.isEmpty) {
      return '${formatOwnerShiftTime(defaultStart)}-${formatOwnerShiftTime(defaultEnd)}';
    }
    return label;
  }

  final headers = <String>[
    'Employee',
    ...visibleIndexes.map((index) {
      final day = ownerWeekdayLabels[index];
      final dateLabel = DateFormat('MMM d').format(weekDays[index]);
      return '$day · $dateLabel';
    }),
  ];

  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4.landscape,
      margin: const pw.EdgeInsets.all(24),
      build: (context) => [
        pw.Text(
          businessName,
          style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold),
        ),
        pw.SizedBox(height: 4),
        pw.Text(
          'Weekly Schedule: ${formatOwnerWeekRange(weekStart)}',
          style: const pw.TextStyle(fontSize: 11),
        ),
        pw.Text(
          'Generated: ${DateFormat.yMMMd().add_jm().format(DateTime.now())}',
          style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700),
        ),
        pw.SizedBox(height: 12),
        pw.Table(
          border: pw.TableBorder.all(color: PdfColors.white, width: 0.6),
          children: [
            pw.TableRow(
              decoration: pw.BoxDecoration(color: headerColor),
              children: headers
                  .map(
                    (header) => pw.Padding(
                      padding: const pw.EdgeInsets.all(5),
                      child: pw.Text(
                        header,
                        style: pw.TextStyle(
                          color: PdfColors.white,
                          fontSize: 8,
                          fontWeight: pw.FontWeight.bold,
                        ),
                        textAlign: header == 'Employee'
                            ? pw.TextAlign.left
                            : pw.TextAlign.center,
                      ),
                    ),
                  )
                  .toList(),
            ),
            ...rows.asMap().entries.map((entry) {
              final rowIndex = entry.key;
              final row = entry.value;
              final employee = row['employee'] as Map<String, dynamic>;
              final cells =
                  row['cells'] as List<List<Map<String, dynamic>>>;
              final rowBg = rowColors[rowIndex % rowColors.length];
              final values = <String>[
                '${employee['full_name'] ?? 'Employee'}',
                ...visibleIndexes.map(
                  (index) => cellLabel(
                    index < cells.length
                        ? cells[index]
                        : const <Map<String, dynamic>>[],
                  ),
                ),
              ];

              return pw.TableRow(
                children: values.asMap().entries.map((cellEntry) {
                  final colIndex = cellEntry.key;
                  final value = cellEntry.value;
                  final isOff = colIndex > 0 && value.trim() == 'OFF';
                  final onLeave =
                      colIndex > 0 && value.toLowerCase().contains('on leave');
                  final bg = isOff
                      ? offColor
                      : onLeave
                          ? onLeaveColor
                          : rowBg;
                  return pw.Container(
                    color: bg,
                    padding: const pw.EdgeInsets.all(5),
                    child: pw.Text(
                      value,
                      style: pw.TextStyle(color: textColor, fontSize: 8),
                      textAlign: colIndex == 0
                          ? pw.TextAlign.left
                          : pw.TextAlign.center,
                    ),
                  );
                }).toList(),
              );
            }),
          ],
        ),
      ],
    ),
  );

  final safeName =
      businessName.toLowerCase().replaceAll(RegExp(r'\s+'), '-');
  final weekKey = ownerDateKey(weekStart);
  final dir = await getTemporaryDirectory();
  final file = File('${dir.path}/$safeName-schedule-$weekKey.pdf');
  await file.writeAsBytes(await doc.save());
  return file.path;
}
