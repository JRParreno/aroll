import 'package:aroll_mobile/presentation/legal/biometric_consent_view.dart';
import 'package:aroll_mobile/presentation/permissions/permission_rationale.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('biometric consent is shown before continuing', (tester) async {
    var agreed = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BiometricConsentView(
            documentText: 'Aroll+ uses the camera to enroll your face.',
            onAgree: () => agreed = true,
          ),
        ),
      ),
    );

    expect(find.text('Face enrollment'), findsOneWidget);
    expect(
      find.textContaining('The camera will not start until you continue'),
      findsOneWidget,
    );
    expect(
      find.textContaining('saved on the server as your employee legal consent'),
      findsOneWidget,
    );

    await tester.tap(find.text('I understand and continue'));
    expect(agreed, isTrue);
  });

  test('permission explanations match required camera GPS and notification copy',
      () {
    expect(
      AppDevicePermission.camera.explanation,
      contains('face registration'),
    );
    expect(
      AppDevicePermission.location.explanation,
      contains('geofence'),
    );
    expect(
      AppDevicePermission.notifications.explanation,
      contains('notifications'),
    );
  });
}
