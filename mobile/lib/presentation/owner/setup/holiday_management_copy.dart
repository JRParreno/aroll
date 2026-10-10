// Owner-facing Holiday Management copy shared with Web terminology.
// Explains existing payroll behavior — does not recompute payroll.

typedef HolidayRulesMode = String; // philippine_labor | custom_company

class HolidayTerms {
  static const holidayType = 'Holiday Type';
  static const workedPremium = 'Holiday Pay Rate';
  static const payWhenNotWorking = 'Pay Scheduled Day When Not Working';
  static const holidayOtPremium = 'Holiday OT Premium';
  static const active = 'Active';
  static const inactive = 'Inactive';
  static const ruleSummary = 'Holiday Rule Summary';
  static const holidayRules = 'Holiday Rules';
  static const howHolidayPayWorks = 'How Holiday Pay Works';
  static const holidays = 'Holidays';
  static const editHolidayPay = 'Edit holiday pay';
  static const payScheduledDay = 'Pay Scheduled Day';
}

class HolidayMenuOption {
  const HolidayMenuOption(this.id, this.title, this.detail);
  final String id;
  final String title;
  final String detail;
}

const holidayPayRateOptions = <HolidayMenuOption>[
  HolidayMenuOption('1.0', 'Regular Pay', '100%'),
  HolidayMenuOption('1.3', '130% Holiday Pay', '130%'),
  HolidayMenuOption('1.5', '150% Holiday Pay', '150%'),
  HolidayMenuOption('2.0', 'Double Pay', '200%'),
  HolidayMenuOption('2.5', '250% Holiday Pay', '250%'),
  HolidayMenuOption('3.0', 'Triple Pay', '300%'),
];

const holidayPayRateMenuOptions = <HolidayMenuOption>[
  ...holidayPayRateOptions,
  HolidayMenuOption('custom', 'Custom', 'Enter a percent'),
];

const holidayOtOptions = <HolidayMenuOption>[
  HolidayMenuOption('0', 'No Extra OT', '0%'),
  HolidayMenuOption('30', '30% Extra', '30%'),
  HolidayMenuOption('custom', 'Custom', 'Enter a percent'),
];

({String title, String detail}) holidayPayRateParts(double multiplier) {
  final safe = multiplier.isFinite && multiplier > 0 ? multiplier : 1.0;
  for (final option in holidayPayRateOptions) {
    final value = double.parse(option.id);
    if ((value - safe).abs() < _presetEps) {
      return (title: option.title, detail: option.detail);
    }
  }
  final pct = holidayPayRatePercent(safe);
  final pctText =
      pct == pct.roundToDouble() ? '${pct.toInt()}' : pct.toStringAsFixed(1);
  return (title: '$pctText% Pay', detail: '$pctText%');
}

String holidayPayRateCardLine(double multiplier) {
  final parts = holidayPayRateParts(multiplier);
  if (isHolidayPayRatePreset(multiplier)) {
    return '${parts.title} · ${parts.detail}';
  }
  return parts.detail;
}

String holidayOtCardLine(num? value) {
  if (value == null || value == 0) return 'No Extra OT';
  if ((value - 30).abs() < _presetEps) return '30%';
  final whole = value == value.roundToDouble();
  return whole ? '${value.toInt()}%' : '$value%';
}

class HolidayPayRatePreset {
  const HolidayPayRatePreset(this.multiplier, this.label);
  final double multiplier;
  final String label;
}

const holidayPayRatePresets = <HolidayPayRatePreset>[
  HolidayPayRatePreset(1.0, 'Regular Pay — 100%'),
  HolidayPayRatePreset(1.3, '130% Pay'),
  HolidayPayRatePreset(1.5, '150% Pay'),
  HolidayPayRatePreset(2.0, 'Double Pay — 200%'),
  HolidayPayRatePreset(2.5, '250% Pay'),
  HolidayPayRatePreset(3.0, 'Triple Pay — 300%'),
];

const _presetEps = 0.0001;

bool isHolidayPayRatePreset(double multiplier) =>
    holidayPayRatePresets.any((p) => (p.multiplier - multiplier).abs() < _presetEps);

double holidayPayRatePercent(double multiplier) {
  final safe = multiplier.isFinite && multiplier > 0 ? multiplier : 1.0;
  return (safe * 1000).round() / 10.0;
}

String holidayPayRateLabel(double multiplier) {
  final safe = multiplier.isFinite && multiplier > 0 ? multiplier : 1.0;
  for (final p in holidayPayRatePresets) {
    if ((p.multiplier - safe).abs() < _presetEps) return p.label;
  }
  final pct = holidayPayRatePercent(safe);
  final pctText = pct == pct.roundToDouble()
      ? '${pct.toInt()}'
      : pct.toStringAsFixed(1);
  return '$pctText% Pay';
}

double percentToPayMultiplier(double percent) => percent / 100.0;

String multiplierToPercentInput(double multiplier) {
  final safe = multiplier.isFinite && multiplier > 0 ? multiplier : 1.0;
  final pct = holidayPayRatePercent(safe);
  return pct == pct.roundToDouble() ? '${pct.toInt()}' : '$pct';
}

String holidayPayRateExplanation(double multiplier) {
  final label = holidayPayRateLabel(multiplier);
  final safe = multiplier.isFinite && multiplier > 0 ? multiplier : 1.0;
  final pct = holidayPayRatePercent(safe);
  final pctText = pct == pct.roundToDouble()
      ? '${pct.toInt()}'
      : pct.toStringAsFixed(1);
  return '$label. Employees who work this holiday receive $pctText% of their '
      'applicable normal pay (total pay rate, not an additional premium).';
}

String holidayPayRateExample(double multiplier) {
  final safe = multiplier.isFinite && multiplier > 0 ? multiplier : 1.0;
  const exampleBase = 500.0;
  final total = (exampleBase * safe * 100).round() / 100.0;
  final pct = holidayPayRatePercent(safe);
  final pctText = pct == pct.roundToDouble()
      ? '${pct.toInt()}'
      : pct.toStringAsFixed(1);
  final totalText = total == total.roundToDouble()
      ? '${total.toInt()}'
      : total.toStringAsFixed(2);
  return 'Example: if applicable normal pay is ₱${exampleBase.toInt()}, '
      'this holiday rate is ₱$totalText ($pctText% total) before other '
      'applicable adjustments.';
}

String holidayOtPremiumOwnerLabel(num? value) {
  if (value == null || value == 0) {
    return 'No additional holiday OT premium — 0%';
  }
  if ((value - 30).abs() < _presetEps) {
    return '30% additional — 30%';
  }
  return '$value% additional';
}

String holidayTypeLabel(String type) {
  switch (type) {
    case 'regular':
      return 'Regular Holiday';
    case 'special_non_working':
      return 'Special Non-Working Day';
    case 'company':
      return 'Company Holiday';
    default:
      return type;
  }
}

String holidayTypeDescription(String type) {
  switch (type) {
    case 'regular':
      return 'Uses the existing Philippine Labor holiday policy in Aroll+.';
    case 'special_non_working':
      return 'Uses the existing Philippine Labor special non-working-day policy in Aroll+.';
    case 'company':
      return "Uses your business's configured company-holiday behavior.";
    default:
      return 'Uses the holiday settings saved for this date.';
  }
}

String rulesModeLabel(String mode) => mode == 'custom_company'
    ? 'Custom company rules'
    : 'Philippine labor rules';

String rulesModeDescription(String mode) {
  if (mode == 'custom_company') {
    return "Each holiday's Pay Scheduled Day When Not Working setting and Holiday Pay Rate are used directly.";
  }
  return 'Regular holidays pay the scheduled day even if unworked. Special non-working days follow no-work-no-pay unless worked. Company holidays follow the Pay Scheduled Day When Not Working setting.';
}

class UnworkedRulePresentation {
  const UnworkedRulePresentation({
    required this.editable,
    required this.effectivePaysUnworked,
    required this.title,
    required this.explanation,
  });

  final bool editable;
  final bool effectivePaysUnworked;
  final String title;
  final String explanation;
}

UnworkedRulePresentation unworkedRulePresentation({
  required String mode,
  required String holidayType,
  required bool isPaid,
}) {
  if (mode == 'custom_company') {
    return UnworkedRulePresentation(
      editable: true,
      effectivePaysUnworked: isPaid,
      title: HolidayTerms.payWhenNotWorking,
      explanation: 'Pay their scheduled day if they do not work.',
    );
  }
  if (holidayType == 'regular') {
    return const UnworkedRulePresentation(
      editable: false,
      effectivePaysUnworked: true,
      title: HolidayTerms.payWhenNotWorking,
      explanation:
          'Regular holidays are paid even when the employee does not work.',
    );
  }
  if (holidayType == 'special_non_working') {
    return const UnworkedRulePresentation(
      editable: false,
      effectivePaysUnworked: false,
      title: HolidayTerms.payWhenNotWorking,
      explanation:
          'Special non-working days are not paid when the employee does not work.',
    );
  }
  return UnworkedRulePresentation(
    editable: true,
    effectivePaysUnworked: isPaid,
    title: HolidayTerms.payWhenNotWorking,
    explanation: 'Pay their scheduled day if they do not work.',
  );
}

String workedPremiumHelperText(double factor) => holidayPayRateExplanation(factor);

String? multiplierWarning(double? factor) {
  if (factor == null || factor.isNaN) return null;
  if (factor <= 0) {
    return 'Values of 0% or less are unusual. Current payroll treats invalid rates as Regular Pay — 100%.';
  }
  return null;
}

String workedRateNote(double multiplier, {required bool custom}) {
  if (custom) {
    return 'Enter the total pay rate. 200% is double pay, not 200% on top.';
  }
  if ((multiplier - 1).abs() < 0.0001) {
    return 'Regular pay. No extra holiday pay.';
  }
  if ((multiplier - 2).abs() < 0.0001) {
    return 'Double pay for eligible holiday work.';
  }
  return 'Extra pay when employees work this holiday.';
}

String otPremiumNote(String? raw) {
  return 'Extra pay for approved overtime worked this holiday.';
}

String otPremiumWarning(String? raw) => otPremiumNote(raw);

class DuplicateHolidayHit {
  const DuplicateHolidayHit({
    required this.id,
    required this.name,
    required this.holidayType,
  });

  final String id;
  final String name;
  final String holidayType;
}

DuplicateHolidayHit? findDuplicateActiveHoliday({
  required List<Map<String, dynamic>> holidays,
  required String holidayDate,
  String? excludeId,
}) {
  if (holidayDate.isEmpty) return null;
  for (final h in holidays) {
    final id = '${h['id']}';
    final active = h['is_active'] != false;
    if (!active) continue;
    if (excludeId != null && id == excludeId) continue;
    if ('${h['holiday_date']}' == holidayDate) {
      return DuplicateHolidayHit(
        id: id,
        name: '${h['name']}',
        holidayType: '${h['holiday_type']}',
      );
    }
  }
  return null;
}

class RuleSummaryLines {
  const RuleSummaryLines({
    required this.holiday,
    required this.type,
    required this.typeDescription,
    required this.worked,
    required this.unworked,
    required this.overtime,
    required this.restDay,
    required this.multipleShifts,
  });

  final String holiday;
  final String type;
  final String typeDescription;
  final List<String> worked;
  final List<String> unworked;
  final List<String> overtime;
  final List<String> restDay;
  final List<String> multipleShifts;
}

RuleSummaryLines buildRuleSummary({
  required String name,
  required String holidayType,
  required String mode,
  required bool isPaid,
  required double payMultiplier,
  required String? otPremiumRaw,
}) {
  final unworked = unworkedRulePresentation(
    mode: mode,
    holidayType: holidayType,
    isPaid: isPaid,
  );
  final factor =
      payMultiplier.isFinite && payMultiplier > 0 ? payMultiplier : 1.0;
  final otTrimmed = (otPremiumRaw ?? '').trim();
  final otNum = otTrimmed.isEmpty ? null : num.tryParse(otTrimmed);
  final otLabel = holidayOtPremiumOwnerLabel(otNum);

  return RuleSummaryLines(
    holiday: name.trim().isEmpty ? '(Untitled holiday)' : name.trim(),
    type: holidayTypeLabel(holidayType),
    typeDescription: holidayTypeDescription(holidayType),
    worked: [
      holidayPayRateExplanation(factor),
      holidayPayRateExample(factor),
    ],
    unworked: [
      unworked.effectivePaysUnworked
          ? 'Scheduled-day entitlement according to the current holiday policy'
          : 'No scheduled-day holiday entitlement when the employee does not work',
      unworked.explanation,
    ],
    overtime: [
      'Approved overtime uses your business OT ₱/minute rate',
      'Holiday OT Premium: $otLabel',
    ],
    restDay: [
      'Existing rest-day premium rules still apply separately when the assignment is rest-day work',
    ],
    multipleShifts: [
      'Holiday pay automatically follows the employee\'s existing pay basis.',
      'Multiple shifts on the same day are handled automatically by Aroll+.',
    ],
  );
}

String compactRuleLine({
  required String mode,
  required String holidayType,
  required bool isPaid,
  required double payMultiplier,
}) {
  final unworked = unworkedRulePresentation(
    mode: mode,
    holidayType: holidayType,
    isPaid: isPaid,
  );
  final factor =
      payMultiplier.isFinite && payMultiplier > 0 ? payMultiplier : 1.0;
  final worked = holidayPayRateLabel(factor);
  final notWorked = unworked.effectivePaysUnworked
      ? 'Pay Scheduled Day'
      : 'No pay if unworked';
  return '$worked · $notWorked';
}

String shortWorkedPremiumHint() =>
    'Extra pay when employees work this holiday.';

class HowHolidayPayPrimary {
  const HowHolidayPayPrimary(this.title, this.summary, this.detail);
  final String title;
  final String summary;
  final String detail;
}

const howHolidayPayWorksPrimary = <HowHolidayPayPrimary>[
  HowHolidayPayPrimary(
    'When an employee works on a holiday',
    'They receive the Holiday Pay Rate you configured for eligible work (total pay rate, such as Double Pay — 200%).',
    'The existing pay_multiplier is a total-pay factor (2.0 = 200% total). Payroll still applies the same holiday premium rules as before.',
  ),
  HowHolidayPayPrimary(
    'When an employee does not work',
    'Some holidays still pay a scheduled-day amount; others do not. This follows your holiday type and Holiday Rules mode.',
    'Under Philippine labor rules, Regular Holidays pay when unworked; Special Non-Working Days do not. Company holidays follow Pay Scheduled Day When Not Working.',
  ),
  HowHolidayPayPrimary(
    'How overtime is handled',
    'Approved OT uses your business OT ₱/minute rate, plus this holiday’s Holiday OT Premium. Blank premium means 0%.',
    'Rest-day premiums remain separate. Unused business OT percentage fields do not control holiday OT.',
  ),
  HowHolidayPayPrimary(
    'Daily vs Hourly employees',
    'Holiday pay automatically follows the employee\'s existing pay basis. Daily and Hourly employees use the payroll rules already configured in Aroll+.',
    'Aroll+ does not stack a separate Daily holiday entitlement for every shift on the same date. Multiple shifts on the same day are handled automatically.',
  ),
  HowHolidayPayPrimary(
    'After payroll is finalized',
    'Finalized payroll uses the saved snapshot. Changing a holiday later does not change finalized payroll.',
    'Live unfinalized periods recalculate from current holiday settings.',
  ),
];

/// Legacy long sections kept for older references; prefer [howHolidayPayWorksPrimary].
class HowHolidayPaySection {
  const HowHolidayPaySection(this.title, this.body);
  final String title;
  final String body;
}

const howHolidayPayWorksSections = <HowHolidayPaySection>[
  HowHolidayPaySection(
    'Worked holiday',
    'When an employee completes qualifying attendance on a holiday, they receive the Holiday Pay Rate (total pay rate) configured for that holiday.',
  ),
  HowHolidayPaySection(
    'Finalized payroll',
    'Finalized payroll uses the saved payroll snapshot. Changing a holiday later does not change finalized payroll.',
  ),
];
