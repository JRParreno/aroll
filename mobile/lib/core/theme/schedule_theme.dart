import 'package:equatable/equatable.dart';
import 'package:flutter/material.dart';

const scheduleWeekdayLabels = [
  'Mon',
  'Tue',
  'Wed',
  'Thu',
  'Fri',
  'Sat',
  'Sun',
];

class ScheduleTableColors extends Equatable {
  const ScheduleTableColors({
    required this.header,
    required this.row1,
    required this.row2,
    required this.row3,
    required this.row4,
    required this.row5,
    required this.off,
    required this.text,
  });

  final String header;
  final String row1;
  final String row2;
  final String row3;
  final String row4;
  final String row5;
  final String off;
  final String text;

  static const defaults = ScheduleTableColors(
    header: '#1E3A5F',
    row1: '#FFE5A3',
    row2: '#FFB166',
    row3: '#B8F28C',
    row4: '#B9D8F7',
    row5: '#F2A7EA',
    off: '#F8B4B4',
    text: '#111827',
  );

  List<String> get rowPalette => [row1, row2, row3, row4, row5];

  ScheduleTableColors copyWith({
    String? header,
    String? row1,
    String? row2,
    String? row3,
    String? row4,
    String? row5,
    String? off,
    String? text,
  }) {
    return ScheduleTableColors(
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

  Map<String, String> toJson() => {
        'header': header,
        'row1': row1,
        'row2': row2,
        'row3': row3,
        'row4': row4,
        'row5': row5,
        'off': off,
        'text': text,
      };

  factory ScheduleTableColors.fromJson(Map<String, dynamic>? json) {
    if (json == null) return defaults;
    return ScheduleTableColors(
      header: json['header'] as String? ?? defaults.header,
      row1: json['row1'] as String? ?? defaults.row1,
      row2: json['row2'] as String? ?? defaults.row2,
      row3: json['row3'] as String? ?? defaults.row3,
      row4: json['row4'] as String? ?? defaults.row4,
      row5: json['row5'] as String? ?? defaults.row5,
      off: json['off'] as String? ?? defaults.off,
      text: json['text'] as String? ?? defaults.text,
    );
  }

  @override
  List<Object?> get props => [header, row1, row2, row3, row4, row5, off, text];
}

class ScheduleDisplaySettings extends Equatable {
  const ScheduleDisplaySettings({
    required this.defaultStart,
    required this.defaultEnd,
    required this.visibleDays,
  });

  final String defaultStart;
  final String defaultEnd;
  final List<String> visibleDays;

  static const defaults = ScheduleDisplaySettings(
    defaultStart: '09:00',
    defaultEnd: '17:00',
    visibleDays: scheduleWeekdayLabels,
  );

  ScheduleDisplaySettings copyWith({
    String? defaultStart,
    String? defaultEnd,
    List<String>? visibleDays,
  }) {
    return ScheduleDisplaySettings(
      defaultStart: defaultStart ?? this.defaultStart,
      defaultEnd: defaultEnd ?? this.defaultEnd,
      visibleDays: visibleDays ?? this.visibleDays,
    );
  }

  Map<String, dynamic> toJson() => {
        'default_start': defaultStart,
        'default_end': defaultEnd,
        'visible_days': visibleDays,
      };

  factory ScheduleDisplaySettings.fromJson(Map<String, dynamic>? json) {
    if (json == null) return defaults;
    final days = json['visible_days'];
    return ScheduleDisplaySettings(
      defaultStart: json['default_start'] as String? ?? defaults.defaultStart,
      defaultEnd: json['default_end'] as String? ?? defaults.defaultEnd,
      visibleDays: days is List
          ? days.whereType<String>().toList(growable: false)
          : defaults.visibleDays,
    );
  }

  @override
  List<Object?> get props => [defaultStart, defaultEnd, visibleDays];
}

Color scheduleColorFromHex(String hex) {
  var normalized = hex.replaceAll('#', '');
  if (normalized.length == 3) {
    normalized = normalized.split('').map((char) => '$char$char').join();
  }
  if (normalized.length == 6) {
    normalized = 'FF$normalized';
  }
  final value = int.tryParse(normalized, radix: 16);
  if (value == null) return const Color(0xFF111827);
  return Color(value);
}

String scheduleColorToHex(Color color) {
  final value = color.toARGB32() & 0xFFFFFF;
  return '#${value.toRadixString(16).padLeft(6, '0').toUpperCase()}';
}
