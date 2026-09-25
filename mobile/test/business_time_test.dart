import 'package:aroll_mobile/core/utils/business_time.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const utcIso = '2026-09-17T04:58:14.165126+00:00';

  test('UTC punch displays 12:58 PM in Asia/Manila, not device local', () {
    final utc = DateTime.parse(utcIso);
    expect(utc.isUtc, isTrue);
    expect(
      formatBusinessAttendanceTime(utc, timeZone: 'Asia/Manila'),
      '12:58 PM',
    );
  });

  test('same UTC punch is 9:58 PM in America/Los_Angeles', () {
    final utc = DateTime.parse(utcIso);
    expect(
      formatBusinessAttendanceTime(utc, timeZone: 'America/Los_Angeles'),
      '9:58 PM',
    );
  });

  test('ISO helper uses the business timezone, not the device timezone', () {
    expect(
      formatBusinessAttendanceTimeIso(utcIso, timeZone: 'Asia/Manila'),
      '12:58 PM',
    );
    expect(
      formatBusinessAttendanceTimeIso(utcIso, timeZone: 'America/Los_Angeles'),
      '9:58 PM',
    );
  });

  test('Manila wall clock is not the Pacific evening clock', () {
    final utc = DateTime.parse(utcIso);
    final manila = toBusinessWallClock(utc, 'Asia/Manila');
    final pacific = toBusinessWallClock(utc, 'America/Los_Angeles');
    expect(manila.hour, 12);
    expect(manila.minute, 58);
    expect(pacific.hour, 21);
    expect(pacific.minute, 58);
    expect(manila.day, 17);
    expect(pacific.day, 16);
  });

  group('Time In availability uses business timezone', () {
    final workDate = DateTime(2026, 9, 17);

    test('early Time In at 12:14 AM Manila is available', () {
      final nowUtc = DateTime.utc(2026, 9, 16, 16, 14);
      expect(
        isBusinessShiftOpenForTimeIn(
          workDate: workDate,
          startHmm: '00:15',
          endHmm: '08:00',
          nowUtc: nowUtc,
          timeZone: 'Asia/Manila',
        ),
        isTrue,
      );
    });

    test('late Time In at 12:41 AM Manila is still available', () {
      final nowUtc = DateTime.utc(2026, 9, 16, 16, 41); // 00:41 Manila
      expect(
        isBusinessShiftOpenForTimeIn(
          workDate: workDate,
          startHmm: '00:15',
          endHmm: '08:00',
          nowUtc: nowUtc,
          timeZone: 'Asia/Manila',
        ),
        isTrue,
      );
      expect(
        resolveEmployeeTimeInAvailable(
          backendFlag: true,
          workDate: workDate,
          startHmm: '00:15',
          endHmm: '08:00',
          timeZone: 'Asia/Manila',
          nowUtc: nowUtc,
        ),
        isTrue,
      );
    });

    test('backend false at 8:00 AM Manila disables Time In', () {
      final nowUtc = DateTime.utc(2026, 9, 17, 0, 0); // 08:00 Manila
      expect(
        isBusinessShiftOpenForTimeIn(
          workDate: workDate,
          startHmm: '00:15',
          endHmm: '08:00',
          nowUtc: nowUtc,
          timeZone: 'Asia/Manila',
        ),
        isFalse,
      );
      expect(
        resolveEmployeeTimeInAvailable(
          backendFlag: false,
          workDate: workDate,
          startHmm: '00:15',
          endHmm: '08:00',
          timeZone: 'Asia/Manila',
          nowUtc: DateTime.utc(2026, 9, 16, 16, 41),
        ),
        isFalse,
      );
    });

    test('missing backend flag falls back to business timezone window', () {
      expect(
        parseTimeInAvailableFlag({'status': 'not_started'}),
        isNull,
      );
      expect(
        parseTimeInAvailableFlag({'time_in_available': true}),
        isTrue,
      );
      expect(
        parseTimeInAvailableFlag({'time_in_available': false}),
        isFalse,
      );
      expect(
        resolveEmployeeTimeInAvailable(
          backendFlag: null,
          workDate: workDate,
          startHmm: '00:15',
          endHmm: '08:00',
          timeZone: 'Asia/Manila',
          nowUtc: DateTime.utc(2026, 9, 16, 16, 41),
        ),
        isTrue,
      );
      expect(
        resolveEmployeeTimeInAvailable(
          backendFlag: null,
          workDate: workDate,
          startHmm: '00:15',
          endHmm: '08:00',
          timeZone: 'Asia/Manila',
          nowUtc: DateTime.utc(2026, 9, 17, 0, 0),
        ),
        isFalse,
      );
    });

    test('Pacific 12:41 AM is Manila 3:41 PM and Time In is closed', () {
      final nowUtc = DateTime.utc(2026, 9, 17, 7, 41);
      final manila = toBusinessWallClock(nowUtc, 'Asia/Manila');
      final pacific = toBusinessWallClock(nowUtc, 'America/Los_Angeles');
      expect(pacific.hour, 0);
      expect(pacific.minute, 41);
      expect(manila.hour, 15);
      expect(manila.minute, 41);
      expect(
        isBusinessShiftOpenForTimeIn(
          workDate: workDate,
          startHmm: '00:15',
          endHmm: '08:00',
          nowUtc: nowUtc,
          timeZone: 'Asia/Manila',
        ),
        isFalse,
      );
    });

    test('already-ended 8:00 AM Manila is not available', () {
      final nowUtc = DateTime.utc(2026, 9, 17, 0, 0); // 08:00 Manila
      expect(
        isBusinessShiftOpenForTimeIn(
          workDate: workDate,
          startHmm: '00:15',
          endHmm: '08:00',
          nowUtc: nowUtc,
          timeZone: 'Asia/Manila',
        ),
        isFalse,
      );
    });

    test('Pacific 12:14 AM is Manila 3:14 PM and is not an active 12:14 AM shift', () {
      final nowUtc = DateTime.utc(2026, 9, 17, 7, 14);
      final manila = toBusinessWallClock(nowUtc, 'Asia/Manila');
      final pacific = toBusinessWallClock(nowUtc, 'America/Los_Angeles');
      expect(pacific.hour, 0);
      expect(pacific.minute, 14);
      expect(manila.hour, 15);
      expect(manila.minute, 14);
      expect(
        isBusinessShiftOpenForTimeIn(
          workDate: workDate,
          startHmm: '00:15',
          endHmm: '08:00',
          nowUtc: nowUtc,
          timeZone: 'Asia/Manila',
        ),
        isFalse,
      );
    });

    test('overnight 22:00-01:00 stays open at 00:59 and closes at 01:00', () {
      final work = DateTime(2026, 9, 16);
      expect(
        isBusinessShiftOpenForTimeIn(
          workDate: work,
          startHmm: '22:00',
          endHmm: '01:00',
          nowUtc: DateTime.utc(2026, 9, 16, 16, 59), // 00:59 Manila
          timeZone: 'Asia/Manila',
        ),
        isTrue,
      );
      expect(
        isBusinessShiftOpenForTimeIn(
          workDate: work,
          startHmm: '22:00',
          endHmm: '01:00',
          nowUtc: DateTime.utc(2026, 9, 16, 17, 0), // 01:00 Manila
          timeZone: 'Asia/Manila',
        ),
        isFalse,
      );
    });

    test('Pacific 1:25 AM displays as 4:25 PM in Asia/Manila', () {
      final utc = DateTime.utc(2026, 9, 17, 8, 25);
      expect(toBusinessWallClock(utc, 'America/Los_Angeles').hour, 1);
      expect(toBusinessWallClock(utc, 'America/Los_Angeles').minute, 25);
      expect(toBusinessWallClock(utc, 'Asia/Manila').hour, 16);
      expect(toBusinessWallClock(utc, 'Asia/Manila').minute, 25);
      expect(businessWallClockFields(utc, timeZone: 'Asia/Manila').hour, 16);
      expect(businessWallClockFields(utc, timeZone: 'Asia/Manila').minute, 25);
      expect(businessWallClockFields(utc, timeZone: 'America/Los_Angeles').hour, 1);
      expect(
        formatWallClockTime(hour: 16, minute: 25),
        '4:25 PM',
      );
      expect(
        formatBusinessAttendanceTime(utc, timeZone: 'Asia/Manila'),
        '4:25 PM',
      );
      expect(
        formatBusinessAttendanceTime(utc, timeZone: 'Asia/Manila'),
        isNot('1:25 AM'),
      );
      expect(
        formatBusinessDateLabel(utc, timeZone: 'Asia/Manila'),
        'Thursday, September 17',
      );
      expect(
        formatBusinessTimezoneCaption('Asia/Manila'),
        'Business time · Asia/Manila',
      );
    });

    test('Pacific 1:14 AM displays as 4:14 PM in Asia/Manila', () {
      final utc = DateTime.utc(2026, 9, 17, 8, 14);
      expect(toBusinessWallClock(utc, 'America/Los_Angeles').hour, 1);
      expect(toBusinessWallClock(utc, 'America/Los_Angeles').minute, 14);
      expect(
        formatBusinessAttendanceTime(utc, timeZone: 'Asia/Manila'),
        '4:14 PM',
      );
      expect(
        formatBusinessDateLabel(utc, timeZone: 'Asia/Manila'),
        'Thursday, September 17',
      );
      expect(
        formatBusinessTimezoneCaption('Asia/Manila'),
        'Business time · Asia/Manila',
      );
    });

    test('Manila device still displays Manila business time', () {
      final utc = DateTime.utc(2026, 9, 17, 8, 25);
      expect(toBusinessWallClock(utc, 'Asia/Manila').hour, 16);
      expect(
        formatBusinessAttendanceTime(utc, timeZone: 'Asia/Manila'),
        '4:25 PM',
      );
    });

    test('business date follows Manila across a Pacific date boundary', () {
      final utc = DateTime.utc(2026, 9, 17, 0, 14);
      expect(
        formatBusinessAttendanceTime(utc, timeZone: 'America/Los_Angeles'),
        '5:14 PM',
      );
      expect(
        formatBusinessDateLabel(utc, timeZone: 'America/Los_Angeles'),
        'Wednesday, September 16',
      );
      expect(
        formatBusinessAttendanceTime(utc, timeZone: 'Asia/Manila'),
        '8:14 AM',
      );
      expect(
        formatBusinessDateLabel(utc, timeZone: 'Asia/Manila'),
        'Thursday, September 17',
      );
    });

    test('missing business timezone formats UTC fields, not device local', () {
      final utc = DateTime.utc(2026, 9, 17, 8, 25);
      expect(formatBusinessAttendanceTime(utc), '8:25 AM');
      expect(formatBusinessAttendanceTime(utc), isNot('1:25 AM'));
      expect(
        formatBusinessDateLabel(utc),
        'Thursday, September 17',
      );
      expect(
        formatBusinessTimezoneCaption(null),
        'UTC · business timezone unavailable',
      );
      expect(
        formatBusinessTimezoneCaption(''),
        'UTC · business timezone unavailable',
      );
      expect(
        resolveBusinessTimeZoneName([null, '', '  ', 'Asia/Manila']),
        'Asia/Manila',
      );
    });
  });
}
