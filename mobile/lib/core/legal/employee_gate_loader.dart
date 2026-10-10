import 'package:aroll_mobile/core/app_state.dart';
import 'package:aroll_mobile/core/di/injection.dart';
import 'package:aroll_mobile/core/legal/consent_sync.dart';
import 'package:aroll_mobile/core/legal/privacy_preferences.dart';
import 'package:aroll_mobile/domain/entities/user_session.dart';
import 'package:aroll_mobile/domain/repositories/employee_repository.dart';
import 'package:permission_handler/permission_handler.dart';

/// Permissions evaluated for employee OS/device grants (camera, location,
/// notifications). Account onboarding completion is separate from these.
const employeeOnboardingPermissions = <Permission>[
  Permission.camera,
  Permission.locationWhenInUse,
  Permission.notification,
];

Future<bool> anyOnboardingPermissionMissing() async {
  try {
    for (final permission in employeeOnboardingPermissions) {
      final status = await permission.status;
      if (!(status.isGranted || status.isLimited)) {
        return true;
      }
    }
    return false;
  } catch (_) {
    // Plugin missing (unit tests) or unsupported platform → treat as not granted.
    return true;
  }
}

/// Whether the introductory Permission Onboarding route should be shown.
///
/// Controlled only by App Permission completion for this employee account
/// (server flag + account-scoped local cache). Consent, face enrollment, and
/// OS grant status are separate and must not skip this intro.
Future<bool> shouldShowPermissionsOnboarding({
  required UserSession session,
  required PermissionsOnboardingStore preferences,
  required bool accountCompletedFromServer,
}) async {
  if (session.isDemo) return false;

  final userId = session.userId;
  var accountCompleted = accountCompletedFromServer;
  if (!accountCompleted) {
    // Offline soft cache only — never reads another account's key.
    accountCompleted = await preferences.hasAccountOnboardingCompleted(userId);
  }

  // Incomplete → show intro. Completed → never replay intro for this account.
  return !accountCompleted;
}

/// Resolve skip/show before [AppState.setSession] notifies the router.
Future<bool> resolvePermissionsIntroSeen(UserSession session) async {
  if (!session.isEmployee || session.isDemo) return true;
  final show = await shouldShowPermissionsOnboarding(
    session: session,
    preferences: sl<PrivacyPreferences>(),
    accountCompletedFromServer:
        session.permissionsOnboardingCompleted == true,
  );
  return !show;
}

Future<void> loadEmployeePostAuthGates(
  AppState appState,
  UserSession session,
) async {
  if (!session.isEmployee) return;
  final prefs = sl<PrivacyPreferences>();
  await prefs.clearLegacyDeviceFlag();

  final showPermissions = await shouldShowPermissionsOnboarding(
    session: session,
    preferences: prefs,
    accountCompletedFromServer:
        session.permissionsOnboardingCompleted == true,
  );
  // permissionsIntroSeen == true means "skip the /permissions gate".
  appState.setPermissionsIntroSeen(!showPermissions);

  await syncEmployeeConsentGate(appState, sl<EmployeeRepository>());
  if (session.isDemo || appState.mustChangePassword) return;
  try {
    final face = await sl<EmployeeRepository>().getFaceStatus();
    appState.setFaceEnrolled(face.isCompleted);
  } catch (_) {
    appState.setFaceEnrolled(false);
  }
}
