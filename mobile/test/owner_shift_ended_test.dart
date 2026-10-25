import 'package:aroll_mobile/presentation/owner/owner_schedule_utils.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final manilaAfternoon = DateTime.utc(2026, 10, 21, 6);
  final manilaMorning = DateTime.utc(2026, 10, 21, 2);

  test('rejects a shift that ended yesterday or earlier today', () {
    expect(
      ownerShiftHasEnded(
        workDate: '2026-10-20',
        startTime: '08:00:00',
        endTime: '12:00:00',
        timeZone: 'Asia/Manila',
        now: manilaAfternoon,
      ),
      isTrue,
    );
    expect(
      ownerShiftHasEnded(
        workDate: '2026-10-21',
        startTime: '08:00:00',
        endTime: '12:00:00',
        timeZone: 'Asia/Manila',
        now: manilaAfternoon,
      ),
      isTrue,
    );
  });

  test('allows a future shift, an ongoing shift, and a shift later today', () {
    expect(
      ownerShiftHasEnded(
        workDate: '2026-10-22',
        startTime: '08:00:00',
        endTime: '12:00:00',
        timeZone: 'Asia/Manila',
        now: manilaAfternoon,
      ),
      isFalse,
    );
    expect(
      ownerShiftHasEnded(
        workDate: '2026-10-21',
        startTime: '08:00:00',
        endTime: '12:00:00',
        timeZone: 'Asia/Manila',
        now: manilaMorning,
      ),
      isFalse,
    );
    expect(
      ownerShiftHasEnded(
        workDate: '2026-10-21',
        startTime: '13:00:00',
        endTime: '17:00:00',
        timeZone: 'Asia/Manila',
        now: manilaMorning,
      ),
      isFalse,
    );
  });

  test('keeps an overnight shift open until the next morning', () {
    expect(
      ownerShiftHasEnded(
        workDate: '2026-10-21',
        startTime: '22:00:00',
        endTime: '06:00:00',
        timeZone: 'Asia/Manila',
        now: DateTime.utc(2026, 10, 21, 21),
      ),
      isFalse,
    );
    expect(
      ownerShiftHasEnded(
        workDate: '2026-10-21',
        startTime: '22:00:00',
        endTime: '06:00:00',
        timeZone: 'Asia/Manila',
        now: DateTime.utc(2026, 10, 21, 22),
      ),
      isTrue,
    );
  });

  test('compares the business timezone instead of the calendar date alone', () {
    final sameInstant = DateTime.utc(2026, 10, 22, 6);
    expect(
      ownerShiftHasEnded(
        workDate: '2026-10-21',
        startTime: '22:00:00',
        endTime: '23:30:00',
        timeZone: 'America/Los_Angeles',
        now: sameInstant,
      ),
      isFalse,
    );
    expect(
      ownerShiftHasEnded(
        workDate: '2026-10-21',
        startTime: '08:00:00',
        endTime: '12:00:00',
        timeZone: 'Asia/Manila',
        now: sameInstant,
      ),
      isTrue,
    );
  });
}
