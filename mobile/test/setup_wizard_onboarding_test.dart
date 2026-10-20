import 'package:aroll_mobile/presentation/owner/setup/setup_ui.dart';
import 'package:aroll_mobile/presentation/owner/setup/setup_wizard_constants.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Leave Policy sits immediately after Holiday Management', () {
    expect(setupWizardStepLabels[4], 'Holiday Management');
    expect(setupWizardStepLabels[setupWizardLeavePolicyStep], 'Leave Policy');
    expect(setupWizardStepLabels[setupWizardLocationStep], 'Work Location');
    expect(setupWizardStepLabels[setupWizardReviewStep], 'Review Your Setup');
  });

  test('first incomplete location maps to the shifted location step', () {
    final status = {
      'steps': [
        {'key': 'shifts', 'complete': true},
        {'key': 'positions', 'complete': true},
        {'key': 'payroll', 'complete': true},
        {'key': 'attendance_policy', 'complete': true},
        {'key': 'holidays', 'complete': true},
        {'key': 'location', 'complete': false},
        {'key': 'review', 'complete': false},
      ],
    };
    expect(firstIncompleteSetupStepIndex(status), setupWizardLocationStep);
  });

  test('review menu index is not business information', () {
    expect(setupWizardReviewStep, isNot(setupWizardBusinessInfoStep));
    expect(setupWizardScreenTitle(setupWizardReviewStep), 'Review Your Setup');
  });

  test('new owners land on branding before setup', () {
    expect(
      ownerLandingRoute(
        setupCompleted: false,
        needsBrandingOnboarding: true,
      ),
      '/owner/branding-setup',
    );
    expect(
      ownerLandingRoute(
        setupCompleted: false,
        needsBrandingOnboarding: false,
      ),
      '/owner/setup-wizard',
    );
    expect(
      ownerLandingRoute(
        setupCompleted: true,
        needsBrandingOnboarding: true,
      ),
      '/owner/home',
    );
  });

  test('every setup step keeps explanatory text after the header banner is removed',
      () {
    for (var step = 0; step < setupWizardStepLabels.length; step++) {
      expect(
        setupWizardStepHelp(step),
        isNotEmpty,
        reason: 'Step ${setupWizardStepLabels[step]} must keep its help text',
      );
    }
  });

  testWidgets('setup step intro is plain text, not a banner', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SetupWizardStepIntro(
            'Add the times your team usually works.',
          ),
        ),
      ),
    );

    expect(find.text('Add the times your team usually works.'), findsOneWidget);
    expect(find.byType(SetupInfoBanner), findsNothing);
    expect(find.byIcon(Icons.info_outline_rounded), findsNothing);
  });

  testWidgets('overtime method dropdown wraps on a narrow phone', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Padding(
            padding: const EdgeInsets.all(16),
            child: OvertimeCalculationMethodField(
              value: 'hourly_statutory',
              enabled: true,
              decoration: const InputDecoration(
                labelText: 'How overtime is calculated',
              ),
              onChanged: (_) {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Hourly-based overtime calculation'), findsOneWidget);
  });
}
