import 'package:aroll_mobile/core/app_state.dart';
import 'package:aroll_mobile/core/di/injection.dart';
import 'package:aroll_mobile/core/legal/consent_sync.dart';
import 'package:aroll_mobile/core/legal/privacy_preferences.dart';
import 'package:aroll_mobile/domain/entities/user_session.dart';
import 'package:aroll_mobile/domain/repositories/employee_repository.dart';

Future<void> loadEmployeePostAuthGates(
  AppState appState,
  UserSession session,
) async {
  if (!session.isEmployee) return;
  final seen = await sl<PrivacyPreferences>().hasSeenPermissionsIntro();
  appState.setPermissionsIntroSeen(session.isDemo ? true : seen);
  await syncEmployeeConsentGate(appState, sl<EmployeeRepository>());
  if (session.isDemo || appState.mustChangePassword) return;
  try {
    final face = await sl<EmployeeRepository>().getFaceStatus();
    appState.setFaceEnrolled(face.isCompleted);
  } catch (_) {
    appState.setFaceEnrolled(false);
  }
}
