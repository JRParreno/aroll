enum ShiftStatus { onDuty, upcoming, offToday }

enum PerformancePeriod { weekly, monthly, yearly }

class TodayShift {
  const TodayShift({
    required this.label,
    required this.startTime,
    required this.endTime,
    required this.status,
  });

  final String label;
  final DateTime startTime;
  final DateTime endTime;
  final ShiftStatus status;
}

class PayrollSummary {
  const PayrollSummary({
    required this.periodLabel,
    required this.amount,
  });

  final String periodLabel;
  final double amount;
}

class PerformanceMetric {
  const PerformanceMetric({
    required this.label,
    required this.value,
    required this.colorArgb,
  });

  final String label;
  final int value;
  final int colorArgb;
}

class PerformanceSnapshot {
  const PerformanceSnapshot({required this.metrics});

  final List<PerformanceMetric> metrics;
}
