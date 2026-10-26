// Presentation-only helpers for same-day multi-shift Shift History grouping.
// Does not recalculate payroll — groups existing rows and sums existing
// authoritative `shift_net` values for FINAL SHIFT NET.

class ShiftHistoryShiftNetSum {
  const ShiftHistoryShiftNetSum({
    required this.unresolved,
    required this.total,
    required this.parts,
  });

  final bool unresolved;
  final double? total;
  final List<double> parts;
}

/// Finite number only — rejects null/NaN/Infinity/non-numbers.
double? asFiniteShiftNet(Object? value) {
  if (value is! num) return null;
  final d = value.toDouble();
  if (d.isNaN || d.isInfinite) return null;
  return d;
}

List<T> sortSameDayShifts<T>({
  required List<T> items,
  required String? Function(T) shiftName,
  required String? Function(T) scheduledStart,
}) {
  final copy = List<T>.from(items);
  copy.sort((a, b) {
    final as = scheduledStart(a) ?? shiftName(a) ?? '';
    final bs = scheduledStart(b) ?? shiftName(b) ?? '';
    return as.compareTo(bs);
  });
  return copy;
}

/// Group a flat employee (single-person) list by work date.
/// Returns either a single item or a multi list (length >= 2) per date.
List<dynamic> buildEmployeeShiftHistoryEntries<T>({
  required List<T> items,
  required DateTime Function(T) dateOf,
  required String? Function(T) shiftName,
  required String? Function(T) scheduledStart,
}) {
  final byDate = <String, List<T>>{};
  final order = <String>[];
  for (final item in items) {
    final d = dateOf(item);
    final key =
        '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
    if (!byDate.containsKey(key)) {
      byDate[key] = [];
      order.add(key);
    }
    byDate[key]!.add(item);
  }
  final result = <dynamic>[];
  for (final key in order) {
    final dayItems = sortSameDayShifts(
      items: byDate[key]!,
      shiftName: shiftName,
      scheduledStart: scheduledStart,
    );
    if (dayItems.length >= 2) {
      result.add(dayItems);
    } else {
      result.add(dayItems.first);
    }
  }
  return result;
}

/// Group owner rows for one date by employee_id.
List<dynamic> buildOwnerDayBlocks({
  required List<Map<String, dynamic>> rows,
}) {
  final byEmployee = <String, List<Map<String, dynamic>>>{};
  final order = <String>[];
  for (final item in rows) {
    final id = '${item['employee_id'] ?? ''}';
    if (!byEmployee.containsKey(id)) {
      byEmployee[id] = [];
      order.add(id);
    }
    byEmployee[id]!.add(item);
  }
  final result = <dynamic>[];
  for (final id in order) {
    final items = sortSameDayShifts(
      items: byEmployee[id]!,
      shiftName: (m) => m['shift_name'] as String?,
      scheduledStart: (m) => m['scheduled_start'] as String?,
    );
    if (items.length >= 2) {
      result.add(items);
    } else {
      result.add(items.first);
    }
  }
  return result;
}

/// FINAL SHIFT NET for a same-day multi-shift group.
/// Sums existing authoritative per-shift `shiftNet` only.
/// Missing/invalid shift_net → total null (unavailable); never 0 or earned.
ShiftHistoryShiftNetSum sumAuthoritativeShiftNet(
  Iterable<({double? shiftNet, bool historicalRateRequired})> items,
) {
  final list = items.toList();
  if (list.any((i) => i.historicalRateRequired)) {
    return const ShiftHistoryShiftNetSum(
      unresolved: true,
      total: null,
      parts: [],
    );
  }
  if (list.isEmpty) {
    return const ShiftHistoryShiftNetSum(
      unresolved: false,
      total: null,
      parts: [],
    );
  }
  final parts = <double>[];
  for (final i in list) {
    final net = asFiniteShiftNet(i.shiftNet);
    if (net == null) {
      // Do not partial-sum or fall back to earned / 0.
      return const ShiftHistoryShiftNetSum(
        unresolved: false,
        total: null,
        parts: [],
      );
    }
    parts.add(net);
  }
  return ShiftHistoryShiftNetSum(
    unresolved: false,
    total: parts.fold<double>(0, (a, b) => a + b),
    parts: parts,
  );
}

/// Owner map rows: read `shift_net` without coercing invalid values to 0.
ShiftHistoryShiftNetSum sumAuthoritativeShiftNetFromMaps(
  Iterable<Map<String, dynamic>> items,
) {
  return sumAuthoritativeShiftNet(
    items.map(
      (item) => (
        shiftNet: asFiniteShiftNet(item['shift_net']),
        historicalRateRequired: item['historical_rate_required'] == true ||
            '${item['payroll_status'] ?? ''}' == 'historical_rate_required',
      ),
    ),
  );
}

String shiftIndexLabel(int index, String? shiftName) {
  final base = 'Shift ${index + 1}';
  final name = (shiftName ?? '').trim();
  return name.isEmpty ? base : '$base — $name';
}

/// Presentation-only Additional Pay / Deduction lines from authoritative fields.
/// Holiday pay is shown only when the backend sent `holiday_pay`.
class ShiftPayLine {
  const ShiftPayLine({
    required this.key,
    required this.label,
    required this.amount,
    required this.kind,
  });

  final String key;
  final String label;
  final double amount;
  final String kind; // additional | deduction
}

double? _asPositiveAmount(Object? value) {
  if (value is! num) return null;
  final d = value.toDouble();
  if (d.isNaN || d.isInfinite || d <= 0) return null;
  return d;
}

double? _asPositiveMinutes(Object? value) {
  if (value is! num) return null;
  final d = value.toDouble();
  if (d.isNaN || d.isInfinite || d <= 0) return null;
  return d;
}

List<ShiftPayLine> buildAdditionalPayLines({
  Object? overtimePay,
  Object? overtimeMinutes,
  Object? restDayPremiumPay,
  Object? additionalPay,
  Object? holidayPay,
}) {
  final lines = <ShiftPayLine>[];
  final holiday = _asPositiveAmount(holidayPay);
  if (holiday != null) {
    lines.add(
      ShiftPayLine(
        key: 'holiday',
        label: 'Holiday Pay',
        amount: holiday,
        kind: 'additional',
      ),
    );
  }
  final otPay = _asPositiveAmount(overtimePay);
  if (otPay != null) {
    final mins = _asPositiveMinutes(overtimeMinutes);
    lines.add(
      ShiftPayLine(
        key: 'overtime',
        label: mins != null
            ? 'Overtime (${mins.round()} min)'
            : 'Overtime',
        amount: otPay,
        kind: 'additional',
      ),
    );
  }
  final rest =
      _asPositiveAmount(restDayPremiumPay) ?? _asPositiveAmount(additionalPay);
  if (rest != null) {
    lines.add(
      ShiftPayLine(
        key: 'rest_day',
        label: 'Rest-Day Premium',
        amount: rest,
        kind: 'additional',
      ),
    );
  }
  return lines;
}

/// Authoritative minute count for a label.
/// Whole values drop the decimal. Fractional values keep two places.
String formatMinuteCount(num minutes) {
  final rounded = (minutes * 100).round() / 100;
  if (rounded == rounded.truncateToDouble()) {
    return rounded.toInt().toString();
  }
  return rounded.toStringAsFixed(2);
}

List<ShiftPayLine> buildDeductionLines({
  Object? lateDeduction,
  Object? lateMinutes,
  Object? undertimeDeduction,
  Object? undertimeMinutes,
}) {
  final lines = <ShiftPayLine>[];
  final latePay = _asPositiveAmount(lateDeduction);
  final lateMins = _asPositiveMinutes(lateMinutes);
  if (latePay != null || lateMins != null) {
    lines.add(
      ShiftPayLine(
        key: 'late',
        label: lateMins != null
            ? 'Late (${formatMinuteCount(lateMins)} min)'
            : 'Late',
        amount: latePay ?? 0,
        kind: 'deduction',
      ),
    );
  }
  final utPay = _asPositiveAmount(undertimeDeduction);
  final utMins = _asPositiveMinutes(undertimeMinutes);
  if (utPay != null || utMins != null) {
    lines.add(
      ShiftPayLine(
        key: 'undertime',
        label: utMins != null
            ? 'Undertime (${utMins.round()} min)'
            : 'Undertime',
        amount: utPay ?? 0,
        kind: 'deduction',
      ),
    );
  }
  return lines;
}

class ShiftHistoryDayTotal {
  const ShiftHistoryDayTotal({
    required this.unresolved,
    required this.total,
    required this.fromReconciliation,
  });

  final bool unresolved;
  final double? total;
  final bool fromReconciliation;
}

/// Prefer the backend day total when every row carries it.
/// Otherwise sum authoritative shift_net (older snapshots).
ShiftHistoryDayTotal historyDayTotalFromMaps(
  Iterable<Map<String, dynamic>> items,
) {
  final list = items.toList();
  if (list.any(
    (item) =>
        item['historical_rate_required'] == true ||
        '${item['payroll_status'] ?? ''}' == 'historical_rate_required',
  )) {
    return const ShiftHistoryDayTotal(
      unresolved: true,
      total: null,
      fromReconciliation: false,
    );
  }
  final reconciled = list.isNotEmpty &&
      list.every((item) => item.containsKey('reconciled_day_total'));
  if (reconciled) {
    return ShiftHistoryDayTotal(
      unresolved: false,
      total: asFiniteShiftNet(list.first['reconciled_day_total']),
      fromReconciliation: true,
    );
  }
  final legacy = sumAuthoritativeShiftNetFromMaps(list);
  return ShiftHistoryDayTotal(
    unresolved: legacy.unresolved,
    total: legacy.total,
    fromReconciliation: false,
  );
}

double? displayedShiftNetFromMap(Map<String, dynamic> item) {
  final reconciled = asFiniteShiftNet(item['reconciled_shift_total']);
  if (reconciled != null) return reconciled;
  return asFiniteShiftNet(item['shift_net']) ??
      asFiniteShiftNet(item['net_pay']) ??
      asFiniteShiftNet(item['earned']);
}

class ShiftPayFace {
  const ShiftPayFace({
    required this.showEarned,
    required this.earned,
    required this.holidayPay,
    required this.shiftTotal,
    required this.hideShiftTotal,
    this.baseLabel = 'Earned',
    this.restPay,
  });

  final bool showEarned;
  final double? earned;
  final String baseLabel;
  final double? restPay;
  final double? holidayPay;
  final double? shiftTotal;
  final bool hideShiftTotal;
}

class DateLevelPay {
  const DateLevelPay({
    this.dailyEntitlement,
    this.restDayPremium,
    this.holidayPay,
  });

  final double? dailyEntitlement;
  final double? restDayPremium;
  final double? holidayPay;
}

double? _positiveMoney(Object? value) {
  final amount = _finiteMoney(value);
  if (amount == null || amount <= 0) return null;
  return amount;
}

/// Date-level lines when two worked daily stamps share one entitlement.
DateLevelPay? dateLevelPayFromMaps(List<Map<String, dynamic>> items) {
  if (workedDailyStampCountMaps(items) < 2) return null;
  Map<String, dynamic>? daily;
  for (final item in items) {
    if (isWorkedDailyStampMap(item)) {
      daily = item;
      break;
    }
  }
  if (daily == null) return null;
  return DateLevelPay(
    dailyEntitlement: _positiveMoney(daily['expected_salary_pay']),
    restDayPremium: _positiveMoney(items.first['day_rest_day_pay']),
    holidayPay: _positiveMoney(items.first['day_holiday_pay']),
  );
}

class DateAdditionalPayLine {
  const DateAdditionalPayLine({
    required this.key,
    required this.label,
    required this.amount,
  });

  final String key;
  final String label;
  final double amount;
}

/// Date-level additions for two or more daily stamps.
/// Empty for hourly, single-daily, and mixed dates. Does not change Day Total.
List<DateAdditionalPayLine> dateLevelAdditionalPayFromMaps(
  List<Map<String, dynamic>> items,
) {
  final pay = dateLevelPayFromMaps(items);
  if (pay == null) return const [];
  final lines = <DateAdditionalPayLine>[];
  if (pay.restDayPremium != null) {
    lines.add(
      DateAdditionalPayLine(
        key: 'rest_day',
        label: 'Rest-Day Premium',
        amount: pay.restDayPremium!,
      ),
    );
  }
  if (pay.holidayPay != null) {
    lines.add(
      DateAdditionalPayLine(
        key: 'holiday',
        label: 'Holiday Premium',
        amount: pay.holidayPay!,
      ),
    );
  }
  return lines;
}

double? _finiteMoney(Object? value) {
  final amount = asFiniteShiftNet(value);
  if (amount == null) return null;
  return (amount * 100).round() / 100;
}

bool isWorkedDailyStampMap(Map<String, dynamic> item) {
  if (item['historical_rate_required'] == true) return false;
  if (item['holiday_included_in_shift_net'] == true) return false;
  if ('${item['status'] ?? ''}' == 'on_leave') return false;
  if ('${item['status'] ?? ''}' == 'holiday_paid') return false;
  return '${item['pay_basis_used'] ?? ''}'.toLowerCase() == 'daily' &&
      _finiteMoney(item['expected_salary_pay']) != null;
}

int workedDailyStampCountMaps(List<Map<String, dynamic>> items) {
  return items.where(isWorkedDailyStampMap).length;
}

/// Status text for Shift History. Does not change payroll.
String shiftHistoryStatusLabelFromMap(Map<String, dynamic> item) {
  if ('${item['payroll_status'] ?? ''}' == 'historical_rate_required') {
    return 'Rate required';
  }
  final status = '${item['status'] ?? ''}';
  switch (status) {
    case 'late':
      return 'Late';
    case 'absent':
      return 'Absent';
    case 'in_progress':
      return 'In progress';
    case 'complete':
      return 'Present';
    case 'holiday_paid':
      return 'Paid Holiday — Not Worked';
    case 'on_leave':
      final amount = _finiteMoney(item['shift_net']) ?? _finiteMoney(item['earned']);
      if (amount != null && amount > 0) return 'Paid Leave';
      if (amount != null) return 'Unpaid Leave';
      return 'On leave';
    case 'incomplete':
      return 'Incomplete';
    default:
      return status.replaceAll('_', ' ');
  }
}

/// Employee-facing shift lines from payslip fields already booked.
ShiftPayFace presentShiftPayFromMap(
  Map<String, dynamic> item,
  List<Map<String, dynamic>> siblings,
) {
  if (item['historical_rate_required'] == true) {
    return const ShiftPayFace(
      showEarned: false,
      earned: null,
      holidayPay: null,
      shiftTotal: null,
      hideShiftTotal: false,
    );
  }
  if (item['status'] == 'holiday_paid' ||
      item['holiday_included_in_shift_net'] == true) {
    final credit =
        _finiteMoney(item['shift_net']) ?? _finiteMoney(item['earned']);
    return ShiftPayFace(
      showEarned: false,
      earned: null,
      holidayPay: credit != null && credit > 0 ? credit : null,
      shiftTotal: credit,
      hideShiftTotal: false,
    );
  }
  final dailyCount = workedDailyStampCountMaps(siblings);
  if (isWorkedDailyStampMap(item) && dailyCount >= 2) {
    return const ShiftPayFace(
      showEarned: false,
      earned: null,
      baseLabel: 'Daily Entitlement',
      holidayPay: null,
      shiftTotal: null,
      hideShiftTotal: true,
    );
  }
  if (isWorkedDailyStampMap(item) && dailyCount == 1) {
    final earned = _finiteMoney(item['expected_salary_pay']);
    final rest = _positiveMoney(item['day_rest_day_pay']);
    final holiday = _positiveMoney(item['day_holiday_pay']);
    final net = _finiteMoney(item['reconciled_shift_total']) ??
        _finiteMoney(item['shift_net']);
    final extras = (rest ?? 0) + (holiday ?? 0);
    return ShiftPayFace(
      showEarned: earned != null,
      earned: earned,
      baseLabel: 'Daily Entitlement',
      restPay: rest,
      holidayPay: holiday,
      shiftTotal: net == null ? null : ((net + extras) * 100).round() / 100,
      hideShiftTotal: false,
    );
  }
  final earned =
      _finiteMoney(item['expected_salary_pay']) ?? _finiteMoney(item['earned']);
  final rest = _positiveMoney(item['rest_day_premium_pay']);
  final holiday = item['holiday_included_in_shift_net'] == true
      ? null
      : _positiveMoney(item['holiday_pay']);
  final reconciled = _finiteMoney(item['reconciled_shift_total']);
  final net = _finiteMoney(item['shift_net']);
  final shiftTotal = reconciled ??
      (net == null ? null : ((net + (holiday ?? 0)) * 100).round() / 100);
  return ShiftPayFace(
    showEarned: earned != null,
    earned: earned,
    baseLabel: 'Base Pay',
    restPay: rest,
    holidayPay: holiday,
    shiftTotal: shiftTotal,
    hideShiftTotal: false,
  );
}

/// Day equation. A sole daily stamp already includes its holiday in the shift total.
String? historyDayEquationFromMaps(
  List<Map<String, dynamic>> items,
  double total,
  String Function(double) money,
) {
  if (workedDailyStampCountMaps(items) >= 2) return null;
  final parts = <String>[];
  var sum = 0.0;
  for (final item in items) {
    final face = presentShiftPayFromMap(item, items);
    final totalForShift = face.shiftTotal;
    if (face.hideShiftTotal || totalForShift == null) return null;
    parts.add(money(totalForShift));
    sum += totalForShift;
  }
  if (parts.length < 2) return null;
  final rounded = (sum * 100).round() / 100;
  final canonical = (total * 100).round() / 100;
  if ((rounded - canonical).abs() > 0.02) return null;
  return '${parts.join(' + ')} = ${money(total)}';
}
