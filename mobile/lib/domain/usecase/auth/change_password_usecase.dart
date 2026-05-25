import 'package:aroll_mobile/core/error/failures.dart';
import 'package:aroll_mobile/domain/repositories/auth_repository.dart';

class ChangePasswordUsecase {
  ChangePasswordUsecase(this._repository);

  final AuthRepository _repository;

  Future<({Failure? failure})> call({
    required String currentPassword,
    required String newPassword,
  }) async {
    final result = await _repository.changePassword(
      currentPassword: currentPassword,
      newPassword: newPassword,
    );
    return (failure: result.failure);
  }
}
