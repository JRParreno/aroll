import 'package:aroll_mobile/presentation/owner/owner_schedule_utils.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('ownerWeekStart uses Monday across month and year boundaries', () {
    expect(ownerWeekStart(DateTime(2026, 9, 24)), DateTime(2026, 9, 21));
    expect(ownerWeekStart(DateTime(2026, 10, 1)), DateTime(2026, 9, 28));
    expect(ownerWeekStart(DateTime(2027, 1, 1)), DateTime(2026, 12, 28));
  });

  test('ownerAssignmentDateKey matches today when work_date is ISO datetime', () {
    expect(ownerAssignmentDateKey('2026-10-01'), '2026-10-01');
    expect(ownerAssignmentDateKey('2026-10-01T00:00:00.000Z'), '2026-10-01');
  });

  test('library max height stays within a short phone and shrinks for the keyboard', () {
    final shortPhone = ownerScheduleLibraryMaxHeight(
      screenHeight: 640,
      paddingTop: 24,
      paddingBottom: 16,
      viewInsetBottom: 0,
    );
    expect(shortPhone <= 640 * 0.72, isTrue);
    expect(shortPhone >= 220, isTrue);
    final withKeyboard = ownerScheduleLibraryMaxHeight(
      screenHeight: 640,
      paddingTop: 24,
      paddingBottom: 16,
      viewInsetBottom: 280,
    );
    expect(withKeyboard < shortPhone, isTrue);
    expect(withKeyboard >= 220, isTrue);
  });

  test('template apply range stays independent of the selected calendar date', () {
    final range = ownerTemplateApplyRange(
      DateTime(2026, 11, 2),
      DateTime(2026, 11, 6),
    );
    expect(ownerDateKey(range.start), '2026-11-02');
    expect(ownerDateKey(range.end), '2026-11-06');
    expect(ownerRestDayPremiumInitialValue(), isFalse);
  });

  test('ownerScheduleRangeError accepts a single date and rejects inverted ranges', () {
    expect(
      ownerScheduleRangeError(DateTime(2026, 10, 19), DateTime(2026, 10, 19)),
      isNull,
    );
    expect(
      ownerScheduleRangeError(DateTime(2026, 10, 19), DateTime(2026, 10, 25)),
      isNull,
    );
    expect(
      ownerScheduleRangeError(DateTime(2026, 10, 25), DateTime(2026, 10, 19)),
      'End date must be the same as or later than the start date.',
    );
  });

  test('ownerAssignmentsOnDate matches today for plain and ISO work_date', () {
    final rows = ownerAssignmentsOnDate(
      [
        {'id': 'plain', 'work_date': '2026-10-01'},
        {'id': 'iso', 'work_date': '2026-10-01T16:00:00.000Z'},
        {'id': 'other', 'work_date': '2026-10-02'},
      ],
      '2026-10-01',
    );
    expect(rows.map((row) => row['id']), ['plain', 'iso']);
    expect(ownerAssignmentsOnDate(rows, '2026-10-03'), isEmpty);
  });

  test('ownerBuildScheduleMatrix keeps copied employees on the same weekday', () {
    final weekStart = DateTime(2026, 9, 28);
    final matrix = ownerBuildScheduleMatrix(
      employees: [
        {'id': 'emp-1', 'full_name': 'Ana Cruz'},
      ],
      assignments: [
        {
          'id': 'asg-1',
          'employee_id': 'emp-1',
          'work_date': '2026-10-01T00:00:00.000Z',
          'shift_id': 'shift-1',
        },
      ],
      weekStart: weekStart,
    );
    final thursday = (matrix.first['cells'] as List)[3] as List;
    expect(thursday, isNotEmpty);
    expect(thursday.first['id'], 'asg-1');
  });

  test('multi-weekday template employees appear on every Nov 2-6 date', () {
    const dates = [
      '2026-11-02',
      '2026-11-03',
      '2026-11-04',
      '2026-11-05',
      '2026-11-06',
    ];
    final assignments = [
      for (final workDate in dates) ...[
        {
          'id': 'aina-$workDate',
          'employee_id': 'emp-aina',
          'employee_name': 'Aina Bejer',
          'work_date': workDate,
          'shift_id': 'morning',
          'is_rest_day_work': false,
        },
        {
          'id': 'ali-$workDate',
          'employee_id': 'emp-ali',
          'employee_name': 'Ali Cornal',
          'work_date': '${workDate}T00:00:00.000Z',
          'shift_id': 'evening',
          'is_rest_day_work': false,
        },
      ],
    ];
    for (final day in dates) {
      expect(ownerAssignmentsOnDate(assignments, day).length, 2);
    }
    final matrix = ownerBuildScheduleMatrix(
      employees: const [],
      assignments: assignments,
      weekStart: ownerWeekStart(DateTime(2026, 11, 2)),
    );
    expect(matrix.length, 2);
    for (final index in [0, 1, 2, 3, 4]) {
      expect((matrix[0]['cells'] as List)[index], isNotEmpty);
      expect((matrix[1]['cells'] as List)[index], isNotEmpty);
    }
  });

  test('weekly refresh shows assignments on every Nov 2-6 date', () {
    const dates = [
      '2026-11-02',
      '2026-11-03',
      '2026-11-04',
      '2026-11-05',
      '2026-11-06',
    ];
    final assignments = [
      for (final workDate in dates) ...[
        {
          'id': 'ana-$workDate',
          'employee_id': 'emp-1',
          'employee_name': 'Ana Cruz',
          'work_date': workDate,
          'shift_id': 'morning',
        },
        {
          'id': 'ben-$workDate',
          'employee_id': 'emp-2',
          'employee_name': 'Ben Reyes',
          'work_date': '${workDate}T00:00:00.000Z',
          'shift_id': 'afternoon',
        },
      ],
    ];
    for (final day in dates) {
      final rows = ownerAssignmentsOnDate(assignments, day);
      expect(rows.length, 2);
      expect(
        rows.map((row) => row['employee_name']).toList()..sort(),
        ['Ana Cruz', 'Ben Reyes'],
      );
    }
    final weekStart = ownerWeekStart(DateTime(2026, 11, 2));
    expect(ownerDateKey(weekStart), '2026-11-02');
    final matrix = ownerBuildScheduleMatrix(
      employees: const [],
      assignments: assignments,
      weekStart: weekStart,
    );
    expect(matrix.length, 2);
    for (final index in [0, 1, 2, 3, 4]) {
      expect((matrix[0]['cells'] as List)[index], isNotEmpty);
      expect((matrix[1]['cells'] as List)[index], isNotEmpty);
    }
    expect((matrix[0]['cells'] as List)[5], isEmpty);
    expect((matrix[0]['cells'] as List)[6], isEmpty);
  });

  test('ownerBuildScheduleMatrix shows assignment-only employees', () {
    final matrix = ownerBuildScheduleMatrix(
      employees: const [],
      assignments: [
        {
          'id': 'asg-2',
          'employee_id': 'emp-9',
          'employee_name': 'Cara Lim',
          'work_date': '2026-10-01',
          'shift_id': 'shift-1',
        },
      ],
      weekStart: DateTime(2026, 9, 28),
    );
    expect(matrix.single['employee']['full_name'], 'Cara Lim');
    expect((matrix.single['cells'] as List)[3], isNotEmpty);
    expect((matrix.single['cells'] as List)[0], isEmpty);
  });
}
