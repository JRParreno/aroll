/// Remaining whole seconds until [availableAt]. Never negative.
int resendSecondsRemaining(DateTime? availableAt, DateTime now) {
  if (availableAt == null) return 0;
  final seconds = availableAt.toUtc().difference(now.toUtc()).inSeconds;
  if (seconds <= 0) return 0;
  return seconds;
}

/// `Resend code in 02:59` for a 179-second wait. 180 seconds is `03:00`.
String resendCountdownLabel(int seconds) {
  final safe = seconds < 0 ? 0 : seconds;
  final minutes = (safe ~/ 60).toString().padLeft(2, '0');
  final remainder = (safe % 60).toString().padLeft(2, '0');
  return 'Resend code in $minutes:$remainder';
}

DateTime? resendAvailableAtFrom({
  String? isoTimestamp,
  int? retryAfterSeconds,
  DateTime? now,
}) {
  final parsed = isoTimestamp == null || isoTimestamp.isEmpty
      ? null
      : DateTime.tryParse(isoTimestamp);
  if (parsed != null) return parsed.toUtc();
  final seconds = retryAfterSeconds ?? 0;
  if (seconds <= 0) return null;
  return (now ?? DateTime.now()).toUtc().add(Duration(seconds: seconds));
}
