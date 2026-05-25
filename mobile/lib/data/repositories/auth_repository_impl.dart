import 'package:aroll_mobile/core/error/failures.dart';
import 'package:aroll_mobile/core/network/api_client.dart';
import 'package:aroll_mobile/domain/entities/user_session.dart';
import 'package:aroll_mobile/domain/repositories/auth_repository.dart';
import 'package:dio/dio.dart';

class AuthRepositoryImpl implements AuthRepository {
  AuthRepositoryImpl(this._api);

  final ApiClient _api;

  @override
  Future<AuthResult<UserSession>> login({
    required String email,
    required String password,
  }) async {
    try {
      final res = await _api.dio.post<Map<String, dynamic>>(
        '/auth/login',
        data: {'email': email.trim(), 'password': password},
      );
      final data = res.data!;
      final token = data['access_token'] as String;
      final mustChange = data['must_change_password'] as bool? ?? false;
      await _api.saveToken(token);

      final me = await _api.dio.get<Map<String, dynamic>>('/auth/me');
      final m = me.data!;
      return (
        data: UserSession(
          userId: m['id'] as String,
          fullName: (m['full_name'] as String?) ?? email,
          role: m['role'] as String,
          businessName: (m['business_name'] as String?) ?? 'Aroll+',
          mustChangePassword: mustChange,
        ),
        failure: null,
      );
    } on DioException {
      return (data: null, failure: const AuthFailure());
    }
  }

  @override
  Future<AuthResult<void>> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    try {
      final res = await _api.dio.post<Map<String, dynamic>>(
        '/auth/change-password',
        data: {
          'current_password': currentPassword,
          'new_password': newPassword,
        },
      );
      final token = res.data!['access_token'] as String;
      await _api.saveToken(token);
      return (data: null, failure: null);
    } on DioException {
      return (data: null, failure: const AuthFailure('Password change failed'));
    }
  }
}
