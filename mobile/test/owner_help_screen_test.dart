import 'package:aroll_mobile/data/owner_support_email.dart';
import 'package:aroll_mobile/presentation/owner/owner_help_screen.dart';
import 'package:aroll_mobile/presentation/owner/owner_settings_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Help is listed for signed-in owners', () {
    final help = ownerSettingsEntries.last;
    expect(help.label, 'Help');
    expect(help.route, '/owner/settings/help');
  });

  test('failure text hides provider secrets', () {
    expect(
      ownerHelpFailureMessage(
        _FakeError({'detail': 'SMTP password rejected: Traceback'}),
      ),
      'The support message could not be sent. Try again in a moment.',
    );
    expect(
      ownerHelpFailureMessage(
        _FakeError({'detail': 'Email delivery is not configured. Set SMTP_HOST, SMTP_FROM_EMAIL, and SMTP credentials.'}),
      ),
      contains('not configured'),
    );
  });

  testWidgets('empty help form explains what to enter and does not send', (tester) async {
    var calls = 0;
    await tester.pumpWidget(_form((_) async {
      calls += 1;
      return {'status': 'accepted', 'detail': 'sent'};
    }));

    await tester.tap(find.byKey(const Key('owner-help-send')));
    await tester.pump();

    expect(find.text('Enter a subject.'), findsOneWidget);
    expect(calls, 0);
  });

  testWidgets('a valid message sends subject and message once', (tester) async {
    final sent = <Map<String, String>>[];
    await tester.pumpWidget(_form((body) async {
      sent.add(body);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      return {
        'status': 'accepted',
        'detail': 'The email provider accepted the message.',
      };
    }));

    await tester.enterText(find.byKey(const Key('owner-help-subject')), 'Scanner');
    await tester.enterText(find.byKey(const Key('owner-help-message')), 'The page is blank.');
    await tester.tap(find.byKey(const Key('owner-help-send')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('owner-help-send')));
    await tester.pump(const Duration(milliseconds: 80));

    expect(sent, [
      {'subject': 'Scanner', 'message': 'The page is blank.'},
    ]);
    expect(sent.single.keys, ['subject', 'message']);
    expect(find.text('The email provider accepted the message.'), findsOneWidget);
    expect(find.text('Scanner'), findsNothing);
  });

  testWidgets('a failed request stays on the form as an error', (tester) async {
    await tester.pumpWidget(_form((_) async {
      throw _FakeError({'detail': 'SMTP password rejected'});
    }));

    await tester.enterText(find.byKey(const Key('owner-help-subject')), 'Scanner');
    await tester.enterText(find.byKey(const Key('owner-help-message')), 'The page is blank.');
    await tester.tap(find.byKey(const Key('owner-help-send')));
    await tester.pump();

    expect(find.text('The support message could not be sent. Try again in a moment.'), findsOneWidget);
    expect(find.text('SMTP password rejected'), findsNothing);
    expect(find.text('The page is blank.'), findsOneWidget);
  });
}

Widget _form(
  Future<Map<String, dynamic>> Function(Map<String, String> body) send,
) {
  return MaterialApp(
    home: Scaffold(
      body: OwnerHelpForm(
        send: ({required subject, required message}) => send({
          'subject': subject,
          'message': message,
        }),
      ),
    ),
  );
}

class _FakeError {
  _FakeError(this.data);

  final Map<String, dynamic> data;

  _FakeResponse get response => _FakeResponse(data);
}

class _FakeResponse {
  _FakeResponse(this.data);

  final Map<String, dynamic> data;
}
