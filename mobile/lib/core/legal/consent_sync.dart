import 'package:aroll_mobile/core/app_state.dart';
import 'package:aroll_mobile/domain/repositories/employee_repository.dart';

Future<void> syncEmployeeConsentGate(
  AppState appState,
  EmployeeRepository repository,
) async {
  final session = appState.session;
  if (session == null || !session.isEmployee) return;
  if (session.isDemo) {
    appState.setConsentStatus(
      legalSatisfied: true,
      biometricSatisfied: true,
      consentsCompleted: true,
    );
    return;
  }
  try {
    final status = await repository.getConsents();
    appState.setConsentStatus(
      legalSatisfied: status.consentsCompleted,
      biometricSatisfied: status.consentsCompleted,
      consentsCompleted: status.consentsCompleted,
    );
  } catch (_) {
    // Soft-fail: a transient GET /consents error must not wipe a known-good
    // completed gate and force Terms again. Prefer /auth/me session flag or
    // the last successful AppState value. If neither is known-good, leave
    // incomplete so the employee is still prompted when needed.
    final knownGood = appState.consentsCompleted == true ||
        session.consentsCompleted == true;
    if (knownGood) {
      appState.setConsentStatus(
        legalSatisfied: true,
        biometricSatisfied: true,
        consentsCompleted: true,
      );
      return;
    }
    appState.setConsentStatus(
      legalSatisfied: false,
      biometricSatisfied: false,
      consentsCompleted: false,
    );
  }
}
