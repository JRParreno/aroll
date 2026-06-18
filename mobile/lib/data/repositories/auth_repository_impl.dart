import 'package:aroll_mobile/core/error/failures.dart';
import 'package:aroll_mobile/core/network/api_client.dart';
import 'package:aroll_mobile/core/router/navigation_debug.dart';
import 'package:aroll_mobile/domain/entities/user_session.dart';
import 'package:aroll_mobile/domain/repositories/auth_repository.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

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
          employeeId: (data['employee_id'] as String?) ??
              (m['employee_id'] as String?),
          businessId: (data['business_id'] as String?) ??
              (m['business_id'] as String?),
          fullName: (data['full_name'] as String?) ??
              (m['full_name'] as String?) ??
              email,
          position: (data['position'] as String?) ?? (m['position'] as String?),
          role: (data['role'] as String?) ?? (m['role'] as String),
          businessName: (data['business_name'] as String?) ??
              (m['business_name'] as String?) ??
              'Aroll+',
          mustChangePassword: mustChange,
        ),
        failure: null,
      );
    } on DioException {
      return (data: null, failure: const AuthFailure());
    }
  }

  @override
  Future<AuthResult<UserSession>> changePassword({
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
      final data = res.data!;
      debugPrint('[auth] change-password response: $data');
      final token = data['access_token'] as String;
      final mustChangeFromToken =
          parseApiBool(data['must_change_password'], fallback: false);
      await _api.saveToken(token);

      final me = await _api.dio.get<Map<String, dynamic>>('/auth/me');
      final m = me.data!;
      debugPrint('[auth] /auth/me after change-password: $m');
      final mustChangeFromMe =
          parseApiBool(m['must_change_password'], fallback: false);

      debugPrint(
        '[auth] must_change_password token=$mustChangeFromToken '
        'me=$mustChangeFromMe',
      );

      return (
        data: UserSession(
          userId: m['id'] as String,
          employeeId: m['employee_id'] as String?,
          businessId: m['business_id'] as String?,
          fullName: (m['full_name'] as String?) ?? '',
          position: m['position'] as String?,
          role: m['role'] as String,
          businessName: (m['business_name'] as String?) ?? 'Aroll+',
          // Successful change-password always clears the gate.
          mustChangePassword: false,
        ),
        failure: null,
      );
    } on DioException catch (e) {
      debugPrint('[auth] change-password DioException: ${e.response?.data}');
      return (data: null, failure: const AuthFailure('Password change failed'));
    } catch (e, st) {
      debugPrint('[auth] change-password unexpected error: $e\n$st');
      return (data: null, failure: const AuthFailure('Password change failed'));
    }
  }

  @override
  Future<void> logout() => _api.clearToken();
}
