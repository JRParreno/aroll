import 'dart:async';

import 'package:aroll_mobile/core/app_state.dart';
import 'package:aroll_mobile/core/di/injection.dart';
import 'package:aroll_mobile/domain/entities/user_session.dart';
import 'package:aroll_mobile/domain/repositories/employee_repository.dart';
import 'package:aroll_mobile/presentation/employee/employee_notification_badge.dart';
import 'package:aroll_mobile/presentation/employee/employee_notifications_screen.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final earlier = DateTime.utc(2026, 10, 18, 1).toIso8601String();
  final latest = DateTime.utc(2026, 10, 18, 3).toIso8601String();
  final arrivedAt = DateTime.utc(2026, 10, 18, 5).toIso8601String();

  Map<String, dynamic> item({
    required String id,
    required String title,
    required String createdAt,
    bool read = false,
  }) {
    return {
      'id': id,
      'title': title,
      'message': '$title details',
      'type': 'schedule_assigned',
      'is_read': read,
      'created_at': createdAt,
      'deep_link': '/schedule',
      'entity_id': 'shift-1',
    };
  }

  List<Map<String, dynamic>> sample() => [
        item(id: 'n1', title: 'Shift assigned', createdAt: earlier),
        item(id: 'n2', title: 'Payroll ready', createdAt: latest),
      ];

  test('opening the inbox ignores a stale unread total', () {
    expect(newestNotificationCreatedAt(sample()), latest);
    expect(
      advanceNotificationSeenThrough(latest, earlier),
      latest,
    );
    expect(
      resolveEmployeeNotificationBadge(
        seenThroughCreatedAt: latest,
        unreadCount: 5,
        unreadCountAfterSeenThrough: 0,
      ),
      0,
    );
    expect(
      resolveEmployeeNotificationBadge(
        seenThroughCreatedAt: latest,
        unreadCount: 5,
        unreadCountAfterSeenThrough: 1,
      ),
      1,
    );
    expect(
      resolveEmployeeNotificationBadge(
        seenThroughCreatedAt: null,
        unreadCount: 5,
        unreadCountAfterSeenThrough: 0,
      ),
      5,
    );
  });

  test('watermark survives a new store load and stays per employee', () async {
    final saved = <String, String>{};
    final store = EmployeeNotificationBadgeStore(
      read: (key) async => saved[key],
      write: (key, value) async {
        saved[key] = value;
      },
    );
    final seen = await store.acknowledge('employee-1', sample());
    expect(seen, latest);

    final reloaded = EmployeeNotificationBadgeStore(
      read: (key) async => saved[key],
      write: (key, value) async {
        saved[key] = value;
      },
    );
    expect(await reloaded.seenThrough('employee-1'), latest);
    expect(await reloaded.seenThrough('employee-2'), isNull);
    expect(
      await reloaded.acknowledge(
        'employee-1',
        [item(id: 'old', title: 'Old', createdAt: earlier)],
      ),
      latest,
    );
  });

  test('mark all keeps records and leaves a later notification unread', () {
    final before = sample();
    final after = markNotificationsReadThrough(before, latest);
    expect(after, hasLength(before.length));
    expect(after.every((row) => row['is_read'] == true), isTrue);
    expect(
      notificationRecordsRetained(before: before, after: after),
      isTrue,
    );
    final withArrival = [
      ...after,
      item(id: 'new', title: 'New alert', createdAt: arrivedAt),
    ];
    expect(
      intendedNotificationsMarked(before: before, after: withArrival),
      isTrue,
    );
    expect(withArrival.last['is_read'], isFalse);
    expect(
      notificationRecordsRetained(before: before, after: withArrival),
      isTrue,
    );
    expect(
      intendedNotificationsMarked(before: before, after: before),
      isFalse,
    );
  });

  group('employee inbox', () {
    late _FakeNotificationsRepo repo;
    late EmployeeNotificationBadgeStore store;

    setUp(() async {
      await sl.reset();
      repo = _FakeNotificationsRepo(sample());
      store = EmployeeNotificationBadgeStore();
      sl.registerSingleton<EmployeeRepository>(repo);
      sl.registerSingleton(store);
      sl.registerSingleton(
        AppState()
          ..setSession(
            const UserSession(
              userId: 'employee-1',
              employeeId: 'e1',
              businessId: 'b1',
              fullName: 'Casey',
              position: 'Staff',
              role: 'employee',
              businessName: 'Test Biz',
            ),
            mustChange: false,
          ),
      );
    });

    tearDown(() async {
      await sl.reset();
    });

    testWidgets('opening the inbox stores the watermark', (tester) async {
      await _pumpInbox(tester);
      expect(find.text('Shift assigned'), findsOneWidget);
      expect(find.text('Payroll ready'), findsOneWidget);
      expect(await store.seenThrough('employee-1'), latest);
      expect(
        resolveEmployeeNotificationBadge(
          seenThroughCreatedAt: await store.seenThrough('employee-1'),
          unreadCount: repo.inbox.where(notificationIsUnread).length,
          unreadCountAfterSeenThrough: 0,
        ),
        0,
      );
      await _disposeInbox(tester);
    });

    testWidgets('prepared inbox is not fetched again', (tester) async {
      store.rememberPrepared(sample());
      await store.acknowledge('employee-1', sample());
      await _pumpInbox(tester);
      expect(repo.inboxLoads, 0);
      expect(find.text('Shift assigned'), findsOneWidget);
      await _disposeInbox(tester);
    });

    testWidgets('mark all read persists, keeps rows, and ignores a new one',
        (tester) async {
      repo.addArrival = item(
        id: 'new',
        title: 'New alert',
        createdAt: arrivedAt,
      );
      await _pumpInbox(tester);
      await tester.tap(find.text('Mark all read'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(repo.markCalls, 1);
      expect(repo.createdThrough, latest);
      expect(find.text('All notifications marked as read.'), findsOneWidget);
      expect(find.text('Shift assigned'), findsOneWidget);
      expect(find.text('Payroll ready'), findsOneWidget);
      expect(find.text('New alert'), findsOneWidget);
      expect(repo.inbox.singleWhere((row) => row['id'] == 'n1')['is_read'], isTrue);
      expect(repo.inbox.singleWhere((row) => row['id'] == 'n2')['is_read'], isTrue);
      expect(repo.inbox.singleWhere((row) => row['id'] == 'new')['is_read'], isFalse);
      expect(repo.inbox, hasLength(3));
      await _disposeInbox(tester);
    });

    testWidgets('mark all read failure keeps unread rows and does not claim success',
        (tester) async {
      repo.failMark = true;
      await _pumpInbox(tester);
      await tester.tap(find.text('Mark all read'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.text('database unavailable'), findsOneWidget);
      expect(find.text('All notifications marked as read.'), findsNothing);
      expect(find.text('Shift assigned'), findsOneWidget);
      expect(repo.inbox.every(notificationIsUnread), isTrue);
      expect(repo.markCalls, 1);
      await _disposeInbox(tester);
    });

    testWidgets('repeated taps do not send a second mark-all request',
        (tester) async {
      final gate = Completer<void>();
      repo.markGate = gate.future;
      await _pumpInbox(tester);
      await tester.tap(find.text('Mark all read'));
      await tester.pump();
      await tester.tap(find.text('Mark all read'));
      await tester.pump();
      expect(repo.markCalls, 1);
      gate.complete();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(repo.markCalls, 1);
      await _disposeInbox(tester);
    });

    testWidgets('empty and already-read inboxes do not call mark all',
        (tester) async {
      repo.inbox = [];
      await _pumpInbox(tester);
      await tester.tap(find.text('Mark all read'));
      await tester.pump();
      expect(find.text('No unread notifications.'), findsOneWidget);
      expect(repo.markCalls, 0);
      await _disposeInbox(tester);
    });

    testWidgets('an inbox with nothing unread does not call mark all',
        (tester) async {
      repo.inbox = [
        item(id: 'n1', title: 'Shift assigned', createdAt: latest, read: true),
      ];
      await _pumpInbox(tester);
      await tester.tap(find.text('Mark all read'));
      await tester.pump();
      expect(find.text('No unread notifications.'), findsOneWidget);
      expect(repo.markCalls, 0);
      expect(find.text('Shift assigned'), findsOneWidget);
      await _disposeInbox(tester);
    });
  });
}

Future<void> _pumpInbox(WidgetTester tester) async {
  tester.view.physicalSize = const Size(900, 1400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(const MaterialApp(home: EmployeeNotificationsScreen()));
  await tester.pump();
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 20));
}

Future<void> _disposeInbox(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(milliseconds: 20));
}

class _FakeNotificationsRepo extends Fake implements EmployeeRepository {
  _FakeNotificationsRepo(this.inbox);

  List<Map<String, dynamic>> inbox;
  int markCalls = 0;
  int inboxLoads = 0;
  bool failMark = false;
  String? createdThrough;
  Future<void>? markGate;
  Map<String, dynamic>? addArrival;

  @override
  Future<List<Map<String, dynamic>>> notifications({
    bool unreadOnly = false,
    int limit = 50,
  }) async {
    if (!unreadOnly) inboxLoads += 1;
    final rows = unreadOnly
        ? inbox.where(notificationIsUnread).toList()
        : inbox;
    return [
      for (final row in rows) Map<String, dynamic>.from(row),
    ];
  }

  @override
  Future<int> markAllNotificationsRead({String? createdThrough}) async {
    markCalls += 1;
    this.createdThrough = createdThrough;
    final gate = markGate;
    if (gate != null) await gate;
    if (failMark) {
      throw DioException(
        requestOptions: RequestOptions(path: '/notifications/read-all'),
        response: Response(
          requestOptions: RequestOptions(path: '/notifications/read-all'),
          statusCode: 500,
          data: {'detail': 'database unavailable'},
        ),
      );
    }
    inbox = markNotificationsReadThrough(inbox, createdThrough);
    final arrival = addArrival;
    if (arrival != null) {
      inbox = [...inbox, Map<String, dynamic>.from(arrival)];
      addArrival = null;
    }
    return inbox.where((row) => row['is_read'] == true).length;
  }

  @override
  Future<void> markNotificationRead(String notificationId) async {}
}
