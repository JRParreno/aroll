import 'package:aroll_mobile/domain/entities/user_session.dart';
import 'package:aroll_mobile/domain/repositories/auth_repository.dart';

class LoginUsecase {
  const LoginUsecase(this._repository);

  final AuthRepository _repository;

  Future<AuthResult<UserSession>> call({
    required String email,
    required String password,
  }) {
    return _repository.login(email: email, password: password);
  }
}
