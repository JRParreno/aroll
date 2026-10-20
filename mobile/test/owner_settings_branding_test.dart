import 'package:aroll_mobile/presentation/owner/owner_settings_screen.dart';
import 'package:aroll_mobile/presentation/owner/setup/owner_branding_onboarding_screen.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Settings keeps a permanent Business Branding entry', () {
    final labels = ownerSettingsEntries.map((entry) => entry.label).toList();
    expect(labels, contains('Business Branding'));
    expect(labels, contains('Business Setup Settings'));
    expect(labels, contains('Leave Policy'));
    expect(labels, contains('Consent Configuration'));
    expect(labels, contains('Audit History'));
    expect(labels, contains('Account Information'));
    expect(labels, contains('Business Information Setup Summary'));

    final branding = ownerSettingsEntries.firstWhere(
      (entry) => entry.label == 'Business Branding',
    );
    expect(branding.route, ownerSettingsBrandingRoute);
    expect(branding.subtitle, contains('logo'));
    expect(branding.subtitle, contains('brand colors'));
  });

  test('Settings branding reuses the existing screen without skip', () {
    expect(brandingScreenShowsSkip(false), isTrue);
    expect(brandingScreenShowsSkip(true), isFalse);
    expect(
      brandingScreenSaveLabel(asSettings: false, busy: false),
      'Save and continue',
    );
    expect(
      brandingScreenSaveLabel(asSettings: true, busy: false),
      'Save Branding',
    );
    expect(
      brandingScreenSaveLabel(asSettings: true, busy: true),
      'Saving…',
    );
    expect(
      brandingScreenHelpText(asSettings: false),
      contains('Skip for now'),
    );
    expect(
      brandingScreenHelpText(asSettings: true),
      contains('web owner portal'),
    );
    expect(
      brandingScreenHelpText(asSettings: true),
      isNot(contains('Skip')),
    );
  });
}
