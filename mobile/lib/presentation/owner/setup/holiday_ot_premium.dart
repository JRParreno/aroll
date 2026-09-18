/// Parses the per-holiday OT premium field shared by Web and Mobile.
///
/// Empty / missing → unconfigured (`null`), which the payroll engine treats
/// as 0% holiday OT premium. Explicit `0` is also 0%.
double? parseHolidayOtPremium(String? raw) {
  if (raw == null) return null;
  final trimmed = raw.trim();
  if (trimmed.isEmpty) return null;
  return double.tryParse(trimmed);
}

String holidayOtPremiumDisplay(dynamic value) {
  if (value == null) return '';
  if (value is num) {
    if (value == value.roundToDouble()) {
      return '${value.toInt()}';
    }
    return '$value';
  }
  return '$value';
}

bool isHolidayOtPremiumInvalid(String? raw) {
  if (raw == null) return false;
  final trimmed = raw.trim();
  if (trimmed.isEmpty) return false;
  final parsed = double.tryParse(trimmed);
  return parsed == null || parsed < 0;
}
