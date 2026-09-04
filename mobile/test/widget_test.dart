import 'package:aroll_mobile/presentation/auth/role_landing_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('shows role choice landing screen', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: RoleLandingScreen()));
    await tester.pump();

    expect(find.text('Welcome to Aroll+'), findsOneWidget);
    expect(find.text('Login as Employee'), findsOneWidget);
    expect(find.text('Login as Business Owner'), findsOneWidget);
    expect(find.text('DEMO MODE'), findsNothing);
    expect(find.text('DEVELOPER TEST MODE'), findsNothing);
  });
}
