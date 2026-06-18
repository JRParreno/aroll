import 'package:flutter/foundation.dart';

bool parseApiBool(dynamic value, {bool fallback = false}) {
  if (value is bool) return value;
  if (value == 'true' || value == 1) return true;
  if (value == 'false' || value == 0) return false;
  debugPrint('[nav-debug] unexpected bool value: $value (${value.runtimeType})');
  return fallback;
}
