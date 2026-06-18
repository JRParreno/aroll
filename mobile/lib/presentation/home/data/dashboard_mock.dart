import 'package:aroll_mobile/presentation/home/models/dashboard_models.dart';

class DashboardMock {
  static TodayShift todayShift(DateTime now) {
    final weekday = now.weekday;
    if (weekday == DateTime.saturday || weekday == DateTime.sunday) {
      return TodayShift(
        label: 'No shift assigned',
        startTime: now,
        endTime: now,
        status: ShiftStatus.offToday,
      );
    }

    final start = DateTime(now.year, now.month, now.day, 8, 0);
    final end = DateTime(now.year, now.month, now.day, 17, 0);

    ShiftStatus status;
    if (now.isBefore(start)) {
      status = ShiftStatus.upcoming;
    } else if (now.isAfter(end)) {
      status = ShiftStatus.offToday;
    } else {
      status = ShiftStatus.onDuty;
    }

    return TodayShift(
      label: 'Regular shift',
      startTime: start,
      endTime: end,
      status: status,
    );
  }

  static PayrollSummary currentPayroll(DateTime now) {
    final day = now.day;
    final isFirstHalf = day <= 15;
    final startDay = isFirstHalf ? 1 : 16;
    final endDay = isFirstHalf ? 15 : _daysInMonth(now.year, now.month);
    final periodLabel =
        '${_monthShort(now.month)} $startDay–$endDay, ${now.year}';

    return PayrollSummary(
      periodLabel: periodLabel,
      amount: isFirstHalf ? 12450.75 : 8920.0,
    );
  }

  static PerformanceSnapshot performance(PerformancePeriod period) {
    final data = switch (period) {
      PerformancePeriod.weekly => const {
          'On Time': 4,
          'Late': 1,
          'Under Time': 0,
          'Over Time': 1,
          'Absent': 0,
        },
      PerformancePeriod.monthly => const {
          'On Time': 18,
          'Late': 3,
          'Under Time': 1,
          'Over Time': 2,
          'Absent': 1,
        },
      PerformancePeriod.yearly => const {
          'On Time': 210,
          'Late': 24,
          'Under Time': 8,
          'Over Time': 15,
          'Absent': 6,
        },
    };

    final colors = {
      'On Time': 0xFF2E7D32,
      'Late': 0xFFEF6C00,
      'Under Time': 0xFFF9A825,
      'Over Time': 0xFF1565C0,
      'Absent': 0xFFC62828,
    };

    return PerformanceSnapshot(
      metrics: data.entries
          .map(
            (e) => PerformanceMetric(
              label: e.key,
              value: e.value,
              colorArgb: colors[e.key]!,
            ),
          )
          .toList(),
    );
  }

  static int _daysInMonth(int year, int month) {
    return DateTime(year, month + 1, 0).day;
  }

  static String _monthShort(int month) {
    const names = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return names[month - 1];
  }
}
