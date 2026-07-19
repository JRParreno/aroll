import 'package:aroll_mobile/core/app_state.dart';
import 'package:aroll_mobile/domain/repositories/auth_repository.dart';
import 'package:aroll_mobile/domain/repositories/employee_repository.dart';

class RestoreSessionUsecase {
  const RestoreSessionUsecase(
    this._authRepository,
    this._appState,
    this._employeeRepository,
  );

  final AuthRepository _authRepository;
  final AppState _appState;
  final EmployeeRepository _employeeRepository;

  Future<void> call() async {
    final session = await _authRepository.restoreSession();
    if (session != null) {
      _appState.setSession(session, mustChange: session.mustChangePassword);
      if (session.isEmployee && !session.mustChangePassword) {
        try {
          final face = await _employeeRepository.getFaceStatus();
          _appState.setFaceEnrolled(face.isCompleted);
        } catch (_) {
          _appState.setFaceEnrolled(false);
        }
      }
      return;
    }
    _appState.clearSession();
  }
}
