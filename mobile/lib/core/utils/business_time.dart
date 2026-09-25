import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

bool _tzInitialized = false;

void ensureBusinessTimeZones() {
  if (_tzInitialized) return;
  tzdata.initializeTimeZones();
  _tzInitialized = true;
}

const _weekdayNames = [
  'Monday',
  'Tuesday',
  'Wednesday',
  'Thursday',
  'Friday',
  'Saturday',
  'Sunday',
];

const _monthNames = [
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December',
];

/// Calendar fields after timezone conversion. Never pass this to [DateFormat]
/// as a UTC/local [DateTime] — that reinterprets the instant in the device zone.
DateTime _naiveWallClock(DateTime value) {
  return DateTime(
    value.year,
    value.month,
    value.day,
    value.hour,
    value.minute,
    value.second,
    value.millisecond,
    value.microsecond,
  );
}

/// 12-hour clock from already-converted hour/minute integers.
String formatWallClockTime({required int hour, required int minute}) {
  final clampedHour = hour.clamp(0, 23).toInt();
  final clampedMinute = minute.clamp(0, 59).toInt();
  final suffix = clampedHour >= 12 ? 'PM' : 'AM';
  final hour12 = clampedHour % 12 == 0 ? 12 : clampedHour % 12;
  return '$hour12:${clampedMinute.toString().padLeft(2, '0')} $suffix';
}

String formatWallClockDate({
  required int year,
  required int month,
  required int day,
}) {
  final civil = DateTime.utc(year, month, day);
  return '${_weekdayNames[civil.weekday - 1]}, ${_monthNames[month - 1]} $day';
}

/// Civil wall-clock fields in a named IANA zone. Display formatters must use
/// these integers; they must not pass a [DateTime] to [DateFormat].
class BusinessWallClockFields {
  const BusinessWallClockFields({
    required this.year,
    required this.month,
    required this.day,
    required this.hour,
    required this.minute,
  });

  final int year;
  final int month;
  final int day;
  final int hour;
  final int minute;
}

BusinessWallClockFields businessWallClockFields(
  DateTime instant, {
  String? timeZone,
}) {
  ensureBusinessTimeZones();
  final utc = instant.toUtc();
  final name = resolveBusinessTimeZoneName([timeZone]);
  if (name == null) {
    return BusinessWallClockFields(
      year: utc.year,
      month: utc.month,
      day: utc.day,
      hour: utc.hour,
      minute: utc.minute,
    );
  }
  try {
    final converted = tz.TZDateTime.from(utc, tz.getLocation(name));
    return BusinessWallClockFields(
      year: converted.year,
      month: converted.month,
      day: converted.day,
      hour: converted.hour,
      minute: converted.minute,
    );
  } on Object {
    return BusinessWallClockFields(
      year: utc.year,
      month: utc.month,
      day: utc.day,
      hour: utc.hour,
      minute: utc.minute,
    );
  }
}

String? resolveBusinessTimeZoneName(Iterable<String?> candidates) {
  for (final candidate in candidates) {
    final name = candidate?.trim();
    if (name != null && name.isNotEmpty) return name;
  }
  return null;
}

String formatBusinessTimezoneCaption(String? timeZone) {
  final name = resolveBusinessTimeZoneName([timeZone]);
  if (name == null) return 'UTC · business timezone unavailable';
  return 'Business time · $name';
}

/// Convert [instant] to a naive wall-clock [DateTime] in [timeZone].
///
/// Use [hour]/[minute]/[year]/[month]/[day] from the result. Do not pass the
/// returned value to [DateFormat], which would localize it to the device zone.
DateTime toBusinessWallClock(DateTime instant, String timeZone) {
  ensureBusinessTimeZones();
  try {
    final location = tz.getLocation(timeZone);
    final converted = tz.TZDateTime.from(instant.toUtc(), location);
    return _naiveWallClock(converted);
  } on Object {
    return _naiveWallClock(instant.toUtc());
  }
}

String formatBusinessAttendanceTime(
  DateTime? instant, {
  String? timeZone,
  String fallback = '--',
}) {
  if (instant == null) return fallback;
  final wall = businessWallClockFields(instant, timeZone: timeZone);
  return formatWallClockTime(hour: wall.hour, minute: wall.minute);
}

String formatBusinessAttendanceTimeIso(
  String? iso, {
  String? timeZone,
  String fallback = '--:--',
}) {
  if (iso == null || iso.isEmpty) return fallback;
  final parsed = DateTime.tryParse(iso);
  return formatBusinessAttendanceTime(
    parsed,
    timeZone: timeZone,
    fallback: fallback,
  );
}

DateTime businessNowWallClock(String? timeZone, {DateTime? utcNow}) {
  final instant = (utcNow ?? DateTime.now()).toUtc();
  final name = resolveBusinessTimeZoneName([timeZone]);
  if (name == null) return _naiveWallClock(instant);
  return toBusinessWallClock(instant, name);
}

String formatBusinessDateLabel(DateTime instant, {String? timeZone}) {
  final wall = businessWallClockFields(instant, timeZone: timeZone);
  return formatWallClockDate(
    year: wall.year,
    month: wall.month,
    day: wall.day,
  );
}

DateTime? _combineBusinessDateAndTime(DateTime workDate, String hhmm) {
  final parts = hhmm.split(':');
  if (parts.length < 2) return null;
  final hour = int.tryParse(parts[0]);
  final minute = int.tryParse(parts[1]);
  if (hour == null || minute == null) return null;
  return DateTime(workDate.year, workDate.month, workDate.day, hour, minute);
}

/// Whether [nowUtc] is still before scheduled end in [timeZone].
///
/// [startHmm]/[endHmm] are business-local wall clocks (`HH:mm`). Overnight
/// shifts (`end <= start`) end on the next calendar day.
bool isBusinessShiftOpenForTimeIn({
  required DateTime workDate,
  required String startHmm,
  required String endHmm,
  required DateTime nowUtc,
  required String timeZone,
}) {
  final wall = toBusinessWallClock(nowUtc.toUtc(), timeZone);
  final start = _combineBusinessDateAndTime(workDate, startHmm);
  var end = _combineBusinessDateAndTime(workDate, endHmm);
  if (end == null) return false;
  if (start != null && !end.isAfter(start)) {
    end = end.add(const Duration(days: 1));
  }
  return wall.isBefore(end);
}

/// Parse the backend `time_in_available` flag. Null if the key is missing.
bool? parseTimeInAvailableFlag(Map<String, dynamic> json) {
  if (!json.containsKey('time_in_available')) return null;
  return json['time_in_available'] == true;
}

/// Backend flag is authoritative. Client business-TZ math is only a fallback
/// when the payload omitted `time_in_available`.
bool resolveEmployeeTimeInAvailable({
  required bool? backendFlag,
  DateTime? workDate,
  String? startHmm,
  String? endHmm,
  String? timeZone,
  DateTime? nowUtc,
}) {
  if (backendFlag != null) return backendFlag;
  if (workDate == null || startHmm == null || endHmm == null) return false;
  final tz = timeZone?.trim();
  if (tz == null || tz.isEmpty) return false;
  return isBusinessShiftOpenForTimeIn(
    workDate: workDate,
    startHmm: startHmm,
    endHmm: endHmm,
    nowUtc: nowUtc ?? DateTime.now().toUtc(),
    timeZone: tz,
  );
}
