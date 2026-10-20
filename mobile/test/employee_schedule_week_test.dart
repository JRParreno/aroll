import 'package:flutter_test/flutter_test.dart';

/// Mirrors Employee My Schedule Monday–Sunday week math.
DateTime _dateOnly(DateTime value) =>
    DateTime(value.year, value.month, value.day);

List<DateTime> mondayWeekDays(DateTime anchor) {
  final day = _dateOnly(anchor);
  final start = day.subtract(Duration(days: day.weekday - 1));
  return List.generate(7, (i) => start.add(Duration(days: i)));
}

void main() {
  test('week always starts Monday and ends Sunday', () {
    // Wednesday Sep 24, 2025 → week Mon Sep 22 … Sun Sep 28
    final week = mondayWeekDays(DateTime(2025, 9, 24));
    expect(week.length, 7);
    expect(week.first, DateTime(2025, 9, 22));
    expect(week.first.weekday, DateTime.monday);
    expect(week.last, DateTime(2025, 9, 28));
    expect(week.last.weekday, DateTime.sunday);
  });

  test('next week advances exactly 7 days across month boundary', () {
    final week1 = mondayWeekDays(DateTime(2025, 9, 22));
    final week2Start = week1.first.add(const Duration(days: 7));
    final week2 = mondayWeekDays(week2Start);
    expect(week2.first, DateTime(2025, 9, 29));
    expect(week2.last, DateTime(2025, 10, 5));
    expect(week2.first.weekday, DateTime.monday);
    expect(week2.last.weekday, DateTime.sunday);
  });

  test('year transition week remains Monday–Sunday', () {
    // Tue Dec 30, 2025 → Mon Dec 29 … Sun Jan 4, 2026
    final week = mondayWeekDays(DateTime(2025, 12, 30));
    expect(week.first, DateTime(2025, 12, 29));
    expect(week.last, DateTime(2026, 1, 4));
    expect(week.first.weekday, DateTime.monday);
    expect(week.last.weekday, DateTime.sunday);
  });
}
