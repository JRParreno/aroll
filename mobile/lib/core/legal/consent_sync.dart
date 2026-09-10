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
    );
    return;
  }
  try {
    final status = await repository.getConsentStatus();
    appState.setConsentStatus(
      legalSatisfied: status.legalSatisfied,
      biometricSatisfied: status.biometricSatisfied,
    );
  } catch (_) {
    appState.setConsentStatus(
      legalSatisfied: false,
      biometricSatisfied: false,
    );
  }
}
