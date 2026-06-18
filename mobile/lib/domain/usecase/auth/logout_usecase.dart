import 'package:aroll_mobile/domain/repositories/auth_repository.dart';

class LogoutUsecase {
  const LogoutUsecase(this._repository);

  final AuthRepository _repository;

  Future<void> call() => _repository.logout();
}
