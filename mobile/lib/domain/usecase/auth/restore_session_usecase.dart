import 'package:aroll_mobile/core/app_state.dart';
import 'package:aroll_mobile/domain/repositories/auth_repository.dart';

class RestoreSessionUsecase {
  const RestoreSessionUsecase(this._authRepository, this._appState);

  final AuthRepository _authRepository;
  final AppState _appState;

  Future<void> call() async {
    final session = await _authRepository.restoreSession();
    if (session != null) {
      _appState.setSession(session, mustChange: session.mustChangePassword);
      return;
    }
    _appState.clearSession();
  }
}
