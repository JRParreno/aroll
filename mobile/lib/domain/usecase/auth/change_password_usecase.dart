import 'package:aroll_mobile/domain/entities/user_session.dart';
import 'package:aroll_mobile/domain/repositories/auth_repository.dart';

class ChangePasswordUsecase {
  ChangePasswordUsecase(this._repository);

  final AuthRepository _repository;

  Future<AuthResult<UserSession>> call({
    required String currentPassword,
    required String newPassword,
  }) {
    return _repository.changePassword(
      currentPassword: currentPassword,
      newPassword: newPassword,
    );
  }
}
