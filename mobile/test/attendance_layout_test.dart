import 'package:aroll_mobile/presentation/home/scan_attendance_screen.dart';
import 'package:aroll_mobile/presentation/owner/owner_attendance_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('employee attendance padding keeps the system inset on the list once', () {
    const media = MediaQueryData(
      padding: EdgeInsets.only(bottom: 48),
      viewPadding: EdgeInsets.only(bottom: 48),
    );

    final padding = employeeAttendanceScrollPadding(media);

    expect(padding.left, 16);
    expect(padding.top, 4);
    expect(padding.right, 16);
    expect(padding.bottom, 64);
  });

  test('employee attendance padding uses the larger system inset', () {
    const media = MediaQueryData(
      padding: EdgeInsets.zero,
      viewPadding: EdgeInsets.only(bottom: 48),
    );

    expect(employeeAttendanceScrollPadding(media).bottom, 64);
  });

  test('pending corrections card stays inside a narrow screen', () {
    const screen = Size(360, 800);
    const button = Rect.fromLTWH(256, 72, 40, 40);

    final frame = pendingCorrectionsPopupFrame(
      screenSize: screen,
      screenPadding: EdgeInsets.zero,
      buttonRect: button,
    );

    expect(frame.left, greaterThanOrEqualTo(16));
    expect(frame.right, lessThanOrEqualTo(screen.width - 16));
    expect(frame.top, button.bottom + 10);
    expect(frame.width, lessThanOrEqualTo(360));
  });

  test('pending corrections card respects system insets and stays near the button', () {
    const screen = Size(800, 800);
    const button = Rect.fromLTWH(720, 80, 40, 40);

    final frame = pendingCorrectionsPopupFrame(
      screenSize: screen,
      screenPadding: const EdgeInsets.only(left: 8, right: 8),
      buttonRect: button,
    );

    expect(frame.left, greaterThanOrEqualTo(24));
    expect(frame.right, lessThanOrEqualTo(screen.width - 24));
    expect(frame.right, button.right);
    expect(frame.width, 360);
  });

  testWidgets('pending corrections popup is fully on screen', (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final notes = TextEditingController();
    addTearDown(notes.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Padding(
            padding: const EdgeInsets.fromLTRB(16, 48, 16, 0),
            child: Row(
              children: [
                const Spacer(),
                PendingCorrectionsButton(
                  items: const [],
                  busyId: null,
                  rejectingId: null,
                  rejectNoteController: notes,
                  onApprove: (_) async {},
                  onOpenReject: (_) {},
                  onCancelReject: () {},
                  onConfirmReject: (_) async {},
                ),
                const SizedBox(width: 8),
                const SizedBox(width: 40, height: 40),
              ],
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byTooltip('Pending corrections'));
    await tester.pumpAndSettle();

    final popup = tester.getRect(find.byKey(const Key('pending-corrections-popup')));
    expect(popup.left, greaterThanOrEqualTo(16));
    expect(popup.right, lessThanOrEqualTo(360 - 16));
    expect(find.text('Pending corrections'), findsOneWidget);
    expect(find.text('No requests right now'), findsOneWidget);
    expect(find.text('No pending correction requests right now.'), findsOneWidget);

    final title = tester.getRect(find.text('Pending corrections'));
    final message = tester.getRect(
      find.text('No pending correction requests right now.'),
    );
    expect(title.left, greaterThanOrEqualTo(popup.left));
    expect(message.left, greaterThanOrEqualTo(popup.left));
    expect(message.right, lessThanOrEqualTo(popup.right));
  });
}
