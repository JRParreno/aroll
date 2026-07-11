import 'package:intl/intl.dart';

/// Canonical PHP peso formatter shared by all screens.
///
/// Uses locale `en_PH` with the `₱` symbol and 2 decimal places so the output
/// is consistent whether shown on employee or owner screens, or embedded in a
/// generated PDF.
String formatPeso(num value) {
  return NumberFormat.currency(
    locale: 'en_PH',
    symbol: '₱',
    decimalDigits: 2,
  ).format(value);
}
