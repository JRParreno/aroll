import 'dart:io';

import 'package:aroll_mobile/presentation/employee/employee_in_app_banner.dart';
import 'package:aroll_mobile/presentation/shared/in_app_notification_listener.dart';
import 'package:aroll_mobile/presentation/shared/notification_routing.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _item(
  String id, {
  String title = 'Title',
  String message = 'Message',
  bool read = false,
  String type = 'overtime_approved',
}) {
  return {
    'id': id,
    'title': title,
    'message': message,
    'is_read': read,
    'type': type,
    'deep_link': '/shift-history',
  };
}

void main() {
  test('owner poll interval stays 60 seconds', () {
    expect(ownerInAppPollInterval, const Duration(seconds: 60));
    expect(employeeInAppPollInterval.inSeconds, lessThan(15));
    expect(employeeInAppPollInterval.inSeconds, greaterThan(0));
    expect(employeeInAppBannerDuration, const Duration(seconds: 3));
  });

  test('first snapshot is primed and not shown', () {
    final controller = EmployeeInAppBannerController();
    controller.ingest([_item('old')]);
    expect(controller.primed, isTrue);
    expect(controller.queue, isEmpty);
    expect(controller.showNext(), isNull);
  });

  test('new unread items are queued immediately after the poll returns', () {
    final controller = EmployeeInAppBannerController();
    controller.prime([_item('old')]);
    controller.ingest([_item('old'), _item('new', title: 'Overtime Approved')]);
    expect(controller.showNext()?['id'], 'new');
  });

  test('read items and duplicates are ignored', () {
    final controller = EmployeeInAppBannerController();
    controller.prime(const []);
    controller.ingest([_item('a'), _item('a'), _item('b', read: true)]);
    expect(controller.queue.map((e) => e['id']), ['a']);
  });

  test('older events play before newer ones and do not overlap', () {
    final controller = EmployeeInAppBannerController();
    controller.prime(const []);
    controller.ingest([_item('newer'), _item('older')]);
    expect(controller.showNext()?['id'], 'older');
    expect(controller.queue.single['id'], 'newer');
  });

  test('stale dismiss does not hide a newer banner', () {
    final controller = EmployeeInAppBannerController();
    controller.prime(const []);
    controller.ingest([_item('b'), _item('a')]);
    expect(controller.showNext()?['id'], 'a');
    expect(controller.dismissIfCurrent('a'), isTrue);
    expect(controller.showNext()?['id'], 'b');
    expect(controller.dismissIfCurrent('a'), isFalse);
    expect(controller.visible?['id'], 'b');
  });

  test('dismissing a banner does not remove inbox data', () {
    final inbox = [_item('keep')];
    final controller = EmployeeInAppBannerController();
    controller.prime(const []);
    controller.ingest(inbox);
    controller.showNext();
    controller.dismissIfCurrent('keep');
    expect(inbox.single['id'], 'keep');
    expect(inbox.single['is_read'], isFalse);
  });

  test('tap destinations stay the same', () {
    expect(
      notificationDestination(type: 'overtime_approved', deepLink: '/shift-history'),
      '/shift-history',
    );
  });

  test('employee and owner listeners remain separate files', () {
    final employeeHost = File(
      'lib/presentation/employee/employee_in_app_banner.dart',
    ).readAsStringSync();
    final employeeUi = File(
      'lib/presentation/employee/employee_ui.dart',
    ).readAsStringSync();
    final ownerShell = File(
      'lib/presentation/owner/owner_shell.dart',
    ).readAsStringSync();
    expect(employeeUi.contains('EmployeeInAppNotificationHost'), isTrue);
    expect(employeeUi.contains('InAppNotificationListener'), isFalse);
    expect(ownerShell.contains('InAppNotificationListener'), isTrue);
    expect(ownerShell.contains('EmployeeInAppNotificationHost'), isFalse);
    expect(employeeHost.contains('SnackBar'), isFalse);
    expect(File('lib/presentation/shared/in_app_notification_listener.dart')
        .readAsStringSync()
        .contains('SnackBar'), isTrue);
  });

  testWidgets('employee banner is top-aligned, white, and auto-hides at 3s',
      (tester) async {
    var fetches = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: EmployeeInAppNotificationHost(
          pollInterval: const Duration(milliseconds: 40),
          displayDuration: const Duration(seconds: 3),
          fetchUnread: () async {
            fetches += 1;
            if (fetches == 1) return [_item('old', title: 'Existing')];
            return [
              _item('old', title: 'Existing'),
              _item('n1', title: 'Overtime Approved', message: 'Shift reviewed'),
            ];
          },
          child: const Scaffold(body: Text('Employee content')),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 10));
    expect(find.byKey(const Key('employee-in-app-banner')), findsNothing);

    await tester.pump(const Duration(milliseconds: 40));
    await tester.pump(const Duration(milliseconds: 10));
    expect(find.byKey(const Key('employee-in-app-banner')), findsOneWidget);
    expect(find.text('Overtime Approved'), findsOneWidget);
    expect(find.text('Shift reviewed'), findsOneWidget);

    final top = tester.getTopLeft(find.byKey(const Key('employee-in-app-banner')));
    final bottom = tester.getBottomLeft(
      find.byKey(const Key('employee-in-app-banner')),
    );
    expect(top.dy, lessThan(80));
    expect(bottom.dy, lessThan(tester.getSize(find.byType(MaterialApp)).height / 2));

    final decorated = tester
        .widgetList<DecoratedBox>(
          find.descendant(
            of: find.byKey(const Key('employee-in-app-banner')),
            matching: find.byType(DecoratedBox),
          ),
        )
        .map((box) => box.decoration)
        .whereType<BoxDecoration>()
        .firstWhere((decoration) => decoration.color == Colors.white);
    expect(decorated.color, Colors.white);
    expect(decorated.border, isNotNull);

    await tester.pump(const Duration(seconds: 2));
    expect(find.byKey(const Key('employee-in-app-banner')), findsOneWidget);
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(milliseconds: 10));
    expect(find.byKey(const Key('employee-in-app-banner')), findsNothing);
  });

  testWidgets('queued banner is not dismissed by the previous timer',
      (tester) async {
    var fetches = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: EmployeeInAppNotificationHost(
          pollInterval: const Duration(milliseconds: 30),
          displayDuration: const Duration(seconds: 3),
          fetchUnread: () async {
            fetches += 1;
            if (fetches == 1) return const <Map<String, dynamic>>[];
            if (fetches == 2) {
              return [_item('first', title: 'First')];
            }
            return [
              _item('first', title: 'First'),
              _item('second', title: 'Second'),
            ];
          },
          child: const Scaffold(body: Text('content')),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 10));
    await tester.pump(const Duration(milliseconds: 30));
    await tester.pump(const Duration(milliseconds: 10));
    expect(find.text('First'), findsOneWidget);
    expect(find.text('Second'), findsNothing);

    await tester.pump(const Duration(milliseconds: 30));
    await tester.pump(const Duration(milliseconds: 10));
    expect(find.text('First'), findsOneWidget);
    expect(find.text('Second'), findsNothing);

    await tester.pump(const Duration(seconds: 3));
    await tester.pump(const Duration(milliseconds: 10));
    expect(find.text('First'), findsNothing);
    expect(find.text('Second'), findsOneWidget);

    await tester.pump(const Duration(seconds: 2));
    expect(find.text('Second'), findsOneWidget);
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(milliseconds: 10));
    expect(find.text('Second'), findsNothing);
  });

  testWidgets('tapping the banner uses the existing destination callback',
      (tester) async {
    var fetches = 0;
    String? opened;
    await tester.pumpWidget(
      MaterialApp(
        home: EmployeeInAppNotificationHost(
          pollInterval: const Duration(milliseconds: 30),
          displayDuration: const Duration(seconds: 3),
          fetchUnread: () async {
            fetches += 1;
            if (fetches == 1) return const <Map<String, dynamic>>[];
            return [_item('tap-me', title: 'Open me')];
          },
          onOpen: (item) async => opened = '${item['id']}',
          child: const Scaffold(body: Text('content')),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 10));
    await tester.pump(const Duration(milliseconds: 30));
    await tester.pump(const Duration(milliseconds: 10));
    await tester.tap(find.byKey(const Key('employee-in-app-banner-tap')));
    await tester.pump();
    expect(opened, 'tap-me');
  });
}
