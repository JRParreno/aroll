import 'package:aroll_mobile/core/error/failures.dart';
import 'package:aroll_mobile/domain/entities/user_session.dart';

typedef AuthResult<T> = ({T? data, Failure? failure});

abstract class AuthRepository {
  Future<AuthResult<UserSession>> login({
    required String email,
    required String password,
  });

  Future<AuthResult<UserSession>> ownerLogin({
    required String businessCode,
    required String email,
    required String password,
  });

  Future<AuthResult<UserSession>> changePassword({
    required String currentPassword,
    required String newPassword,
  });

  Future<void> logout();

  /// Returns a session when a stored token is valid; otherwise null.
  Future<UserSession?> restoreSession();
}
