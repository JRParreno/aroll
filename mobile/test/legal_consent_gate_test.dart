import 'package:aroll_mobile/core/app_state.dart';
import 'package:aroll_mobile/core/router/app_router.dart';
import 'package:aroll_mobile/domain/entities/user_session.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  UserSession employee({
    bool demo = false,
    bool mustChange = false,
  }) {
    return UserSession(
      userId: 'u1',
      employeeId: 'e1',
      businessId: 'b1',
      fullName: 'Casey',
      position: 'Staff',
      role: 'employee',
      businessName: 'Test Biz',
      businessCode: 'LC-TEST',
      mustChangePassword: mustChange,
      isDemo: demo,
    );
  }

  test('employee route order is password, legal, permissions, biometric, face', () {
    final appState = AppState()
      ..setSession(employee(), mustChange: true);
    expect(resolveAuthenticatedRoute(appState), '/change-password');

    appState.passwordChanged();
    appState.setConsentStatus(legalSatisfied: false, biometricSatisfied: false);
    expect(resolveAuthenticatedRoute(appState), '/legal-consent');

    appState.setConsentStatus(legalSatisfied: true, biometricSatisfied: false);
    appState.setPermissionsIntroSeen(false);
    expect(resolveAuthenticatedRoute(appState), '/permissions');

    appState.setPermissionsIntroSeen(true);
    expect(resolveAuthenticatedRoute(appState), '/biometric-consent');

    appState.setConsentStatus(legalSatisfied: true, biometricSatisfied: true);
    appState.setFaceEnrolled(false);
    expect(resolveAuthenticatedRoute(appState), '/face-registration');

    appState.setFaceEnrolled(true);
    expect(resolveAuthenticatedRoute(appState), '/home');
  });

  test('demo employees skip legal, permissions, biometric, and face gates', () {
    final appState = AppState()..setSession(employee(demo: true), mustChange: false);
    expect(resolveAuthenticatedRoute(appState), '/home');
  });
}
