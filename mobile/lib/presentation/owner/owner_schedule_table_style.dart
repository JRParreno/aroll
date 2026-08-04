import 'package:flutter/material.dart';

/// Matches the web owner schedule table customization palette.
class OwnerScheduleTableColors {
  const OwnerScheduleTableColors({
    required this.header,
    required this.row1,
    required this.row2,
    required this.row3,
    required this.row4,
    required this.row5,
    required this.off,
    required this.text,
  });

  final Color header;
  final Color row1;
  final Color row2;
  final Color row3;
  final Color row4;
  final Color row5;
  final Color off;
  final Color text;

  static const defaults = OwnerScheduleTableColors(
    header: Color(0xFF1E3A5F),
    row1: Color(0xFFFFE5A3),
    row2: Color(0xFFFFB166),
    row3: Color(0xFFB8F28C),
    row4: Color(0xFFB9D8F7),
    row5: Color(0xFFF2A7EA),
    off: Color(0xFFF8B4B4),
    text: Color(0xFF111827),
  );

  static const onLeave = Color(0xFFFECACA);

  static const textChoices = <Color>[
    Color(0xFF111827),
    Color(0xFFFFFFFF),
    Color(0xFF1E3A5F),
    Color(0xFF6B7280),
  ];

  static const swatchPalette = <Color>[
    Color(0xFF1E3A5F),
    Color(0xFF284B73),
    Color(0xFF3B82F6),
    Color(0xFFFFE5A3),
    Color(0xFFFFB166),
    Color(0xFFB8F28C),
    Color(0xFFB9D8F7),
    Color(0xFFF2A7EA),
    Color(0xFFF8B4B4),
    Color(0xFFFECACA),
    Color(0xFF111827),
    Color(0xFF6B7280),
    Color(0xFFFFFFFF),
    Color(0xFFFEF3C7),
    Color(0xFFD1FAE5),
    Color(0xFFE0E7FF),
  ];

  List<Color> get rowColors => [row1, row2, row3, row4, row5];

  OwnerScheduleTableColors copyWith({
    Color? header,
    Color? row1,
    Color? row2,
    Color? row3,
    Color? row4,
    Color? row5,
    Color? off,
    Color? text,
  }) {
    return OwnerScheduleTableColors(
      header: header ?? this.header,
      row1: row1 ?? this.row1,
      row2: row2 ?? this.row2,
      row3: row3 ?? this.row3,
      row4: row4 ?? this.row4,
      row5: row5 ?? this.row5,
      off: off ?? this.off,
      text: text ?? this.text,
    );
  }
}

String ownerScheduleTimeOfDayToString(TimeOfDay time) {
  final hour = time.hour.toString().padLeft(2, '0');
  final minute = time.minute.toString().padLeft(2, '0');
  return '$hour:$minute';
}

TimeOfDay ownerScheduleParseTimeOfDay(String value) {
  final parts = value.split(':');
  final hour = int.tryParse(parts.isNotEmpty ? parts[0] : '') ?? 9;
  final minute = int.tryParse(parts.length > 1 ? parts[1] : '') ?? 0;
  return TimeOfDay(hour: hour.clamp(0, 23), minute: minute.clamp(0, 59));
}
