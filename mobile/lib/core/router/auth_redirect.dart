import 'package:aroll_mobile/core/app_state.dart';

/// Resolves the landing route after auth (login, restore, or password change).
String resolveAuthenticatedRoute(AppState appState) {
  if (!appState.isLoggedIn || appState.session == null) {
    return '/login';
  }
  final session = appState.session!;
  if (appState.mustChangePassword) {
    return '/change-password';
  }
  if (session.isOwner) {
    return session.setupCompletedAt == null
        ? '/owner/setup-wizard'
        : '/owner/home';
  }
  if (session.isEmployee && !appState.legalConsentAccepted) {
    return '/legal-consent';
  }
  if (session.isEmployee && !appState.permissionsIntroSeen) {
    return '/permissions-onboarding';
  }
  if (session.isDemo) {
    return '/home';
  }
  if (appState.faceEnrolled != true) {
    return '/face-registration';
  }
  return '/home';
}
