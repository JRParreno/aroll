import 'package:aroll_mobile/core/utils/resend_countdown.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('countdown stays accurate from a fixed server timestamp', () {
    final available = DateTime.utc(2026, 10, 18, 1, 3, 0);
    final now = DateTime.utc(2026, 10, 18, 1, 0, 1);
    expect(resendSecondsRemaining(available, now), 179);
    expect(resendCountdownLabel(179), 'Resend code in 02:59');
    expect(resendCountdownLabel(180), 'Resend code in 03:00');
    expect(resendSecondsRemaining(available, available), 0);
    expect(resendSecondsRemaining(null, now), 0);
  });

  test('rebuild does not restart a countdown that already started', () {
    final started = DateTime.utc(2026, 10, 18, 1, 0, 0);
    final available = resendAvailableAtFrom(
      retryAfterSeconds: 180,
      now: started,
    );
    final later = started.add(const Duration(seconds: 30));
    expect(resendSecondsRemaining(available, later), 150);
    expect(resendSecondsRemaining(available, later), 150);
  });
}
