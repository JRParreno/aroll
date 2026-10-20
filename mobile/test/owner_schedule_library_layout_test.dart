import 'package:aroll_mobile/presentation/owner/owner_schedule_reuse.dart';
import 'package:aroll_mobile/presentation/owner/owner_schedule_utils.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Schedule Library scrolls on a short phone instead of overflowing', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final maxHeight = ownerScheduleLibraryMaxHeight(
      screenHeight: 640,
      paddingTop: 0,
      paddingBottom: 0,
      viewInsetBottom: 0,
    );
    final templates = [
      for (var index = 1; index <= 8; index++)
        {
          'id': 'tpl-$index',
          'name': 'Template $index',
          'entry_count': 4,
          'employee_count': 3,
        },
    ];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topRight,
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: 320, maxHeight: maxHeight),
              child: ownerScheduleLibraryCardForTest(
                startDate: DateTime(2026, 11, 2),
                endDate: DateTime(2026, 11, 6),
                templates: templates,
                suggestions: const {
                  'previous_week_start': '2026-10-26',
                  'previous_week_assignment_count': 4,
                  'last_schedule_week_start': '2026-10-26',
                },
              ),
            ),
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.text('Schedule Library'), findsOneWidget);
    expect(find.text('Start date'), findsOneWidget);
    expect(find.text('End date'), findsOneWidget);
    expect(find.text('Copy previous week'), findsOneWidget);
    expect(find.byType(Scrollable), findsWidgets);

    await tester.scrollUntilVisible(find.text('Template 8'), 200);
    expect(find.text('Template 8'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Schedule Library still fits when the keyboard is open', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final maxHeight = ownerScheduleLibraryMaxHeight(
      screenHeight: 640,
      paddingTop: 24,
      paddingBottom: 16,
      viewInsetBottom: 280,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(
            size: Size(360, 640),
            viewInsets: EdgeInsets.only(bottom: 280),
            padding: EdgeInsets.only(top: 24, bottom: 16),
          ),
          child: Scaffold(
            body: Align(
              alignment: Alignment.topRight,
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: 320,
                  maxHeight: maxHeight,
                ),
                child: ownerScheduleLibraryCardForTest(
                  startDate: DateTime(2026, 11, 2),
                  endDate: DateTime(2026, 11, 6),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.text('Start date'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Save this week to the library'),
      120,
    );
    expect(find.text('Save this week to the library'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
