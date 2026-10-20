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

  Future<AuthResult<PasswordResetTicket>> requestEmployeeResetCode({
    required String username,
    required String email,
  });

  Future<AuthResult<PasswordResetTicket>> employeeResetStatus({
    required String username,
    required String email,
  });

  Future<AuthResult<String>> verifyEmployeeResetCode({
    required String username,
    required String email,
    required String code,
  });

  Future<Failure?> completeEmployeePasswordReset({
    required String resetToken,
    required String newPassword,
  });

  Future<AuthResult<PasswordResetTicket>> requestOwnerResetCode({
    required String email,
    required String businessCode,
  });

  Future<AuthResult<PasswordResetTicket>> ownerResetStatus({
    required String email,
    required String businessCode,
  });

  Future<AuthResult<String>> verifyOwnerResetCode({
    required String email,
    required String businessCode,
    required String code,
  });

  Future<Failure?> completeOwnerPasswordReset({
    required String resetToken,
    required String newPassword,
  });
}

class PasswordResetTicket {
  const PasswordResetTicket({
    required this.accepted,
    required this.message,
    required this.retryAfterSeconds,
    required this.resendAvailableAt,
  });

  final bool accepted;
  final String message;
  final int retryAfterSeconds;
  final DateTime? resendAvailableAt;
}
