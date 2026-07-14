import 'package:aroll_mobile/core/error/failures.dart';
import 'package:aroll_mobile/core/network/api_client.dart';
import 'package:aroll_mobile/domain/entities/user_session.dart';
import 'package:aroll_mobile/domain/repositories/auth_repository.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

class AuthRepositoryImpl implements AuthRepository {
  AuthRepositoryImpl(this._api);

  final ApiClient _api;

  BusinessBrandingSettings? _brandingFromJson(Map<String, dynamic> data) {
    final branding = data['branding'];
    if (branding is! Map<String, dynamic>) return null;
    final theme = branding['theme'];
    final themeMap =
        theme is Map<String, dynamic> ? theme : <String, dynamic>{};
    return BusinessBrandingSettings(
      logoUrl: branding['logo_url'] as String?,
      ownerProfileImageUrl: branding['owner_profile_image_url'] as String?,
      displayImageUrl: branding['display_image_url'] as String?,
      theme: BusinessThemeSettings(
        primaryColor: (themeMap['primary_color'] as String?) ?? '#1E3A5F',
        secondaryColor: (themeMap['secondary_color'] as String?) ?? '#284B73',
        sidebarColor: (themeMap['sidebar_color'] as String?) ?? '#1E3A5F',
        accentColor: (themeMap['accent_color'] as String?) ?? '#3B82F6',
        buttonColor: (themeMap['button_color'] as String?) ?? '#1E3A5F',
        cardStyle: (themeMap['card_style'] as String?) ?? 'soft',
        fontSize: (themeMap['font_size'] as String?) ?? 'comfortable',
        colorMode: (themeMap['color_mode'] as String?) ?? 'light',
        layoutDensity: (themeMap['layout_density'] as String?) ?? 'rounded',
      ),
    );
  }

  UserSession _sessionFromMe(
    Map<String, dynamic> m, {
    required String role,
    required bool mustChangePassword,
    String? businessCode,
    String? fallbackName,
  }) {
    return UserSession(
      userId: m['id'] as String,
      employeeId: m['employee_id'] as String?,
      businessId: m['business_id'] as String?,
      fullName: (m['full_name'] as String?) ?? fallbackName ?? '',
      position: m['position'] as String?,
      role: role,
      businessName: (m['business_name'] as String?) ?? 'Aroll+',
      email: m['email'] as String?,
      businessCode: businessCode ?? m['business_code'] as String?,
      setupCompletedAt: _parseDateTime(m['setup_completed_at'] as String?),
      mustChangePassword: mustChangePassword,
      branding: _brandingFromJson(m),
      profileImageUrl: m['profile_image_url'] as String?,
    );
  }

  @override
  Future<AuthResult<UserSession>> login({
    required String email,
    required String password,
  }) async {
    try {
      final loginId = email.trim().toLowerCase();
      final res = await _api.dio.post<Map<String, dynamic>>(
        '/auth/login',
        data: {'email': loginId, 'password': password},
      );
      final data = res.data!;
      final token = data['access_token'] as String;
      final mustChange = data['must_change_password'] as bool? ?? false;
      await _api.saveToken(token);

      final me = await _fetchMe(token);
      final role = (data['role'] as String?) ?? (me['role'] as String);
      if (role != 'employee') {
        await _api.clearToken();
        return (
          data: null,
          failure: const AuthFailure('Use an enrolled employee account.'),
        );
      }

      return (
        data: _sessionFromMe(
          me,
          role: role,
          mustChangePassword: mustChange,
          fallbackName: email,
        ),
        failure: null,
      );
    } on DioException catch (e) {
      return _loginFailure(e, employee: true);
    }
  }

  @override
  Future<AuthResult<UserSession>> ownerLogin({
    required String businessCode,
    required String email,
    required String password,
  }) async {
    try {
      final res = await _api.dio.post<Map<String, dynamic>>(
        '/auth/business-owner-login',
        data: {
          'business_code': businessCode.trim().toUpperCase().replaceAll(' ', ''),
          'email': email.trim().toLowerCase(),
          'password': password,
        },
      );
      final data = res.data!;
      final token = data['access_token'] as String;
      await _api.saveToken(token);
      await _api.saveBusinessCode(businessCode.trim());

      final me = await _fetchMe(token);
      final role = (data['role'] as String?) ?? (me['role'] as String);
      if (role != 'owner' && role != 'manager') {
        await _api.clearToken();
        return (
          data: null,
          failure: const AuthFailure('This account is not a business owner.'),
        );
      }

      final mustChange = (data['must_change_password'] as bool?) ??
          (me['must_change_password'] as bool?) ??
          false;

      return (
        data: _sessionFromMe(
          me,
          role: role,
          mustChangePassword: mustChange,
          businessCode: businessCode.trim(),
          fallbackName: email,
        ),
        failure: null,
      );
    } on DioException catch (e) {
      return _loginFailure(e, employee: false);
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
      final token = data['access_token'] as String;
      await _api.saveToken(token);

      final me = await _fetchMe(token);
      final role = me['role'] as String;

      return (
        data: _sessionFromMe(
          me,
          role: role,
          mustChangePassword: false,
        ),
        failure: null,
      );
    } on DioException catch (e) {
      debugPrint('[auth] change-password DioException: ${e.response?.data}');
      final detail = _errorDetail(e.response?.data);
      return (
        data: null,
        failure: AuthFailure(detail ?? 'Password change failed'),
      );
    } catch (e, st) {
      debugPrint('[auth] change-password unexpected error: $e\n$st');
      return (data: null, failure: const AuthFailure('Password change failed'));
    }
  }

  @override
  Future<void> logout() async {
    await _api.clearToken();
    await _api.clearBusinessCode();
  }

  @override
  Future<UserSession?> restoreSession() async {
    final token = await _api.readToken();
    if (token == null || token.isEmpty) {
      return null;
    }

    try {
      final me = await _fetchMe(token);
      final role = me['role'] as String;
      final mustChange = me['must_change_password'] as bool? ?? false;
      final businessCode = await _api.readBusinessCode();
      return _sessionFromMe(
        me,
        role: role,
        mustChangePassword: mustChange,
        businessCode: businessCode,
      );
    } on DioException catch (e) {
      debugPrint(
        '[auth] restoreSession failed status=${e.response?.statusCode} '
        'type=${e.type}',
      );
      if (_isInvalidTokenError(e)) {
        await _api.clearToken();
        await _api.clearBusinessCode();
      }
      return null;
    } catch (e, st) {
      debugPrint('[auth] restoreSession unexpected error: $e\n$st');
      return null;
    }
  }

  Future<Map<String, dynamic>> _fetchMe(String token) async {
    final me = await _api.dio.get<Map<String, dynamic>>(
      '/auth/me',
      options: Options(headers: {'Authorization': 'Bearer $token'}),
    );
    return me.data!;
  }

  bool _isInvalidTokenError(DioException e) {
    final status = e.response?.statusCode;
    return status == 401 || status == 403;
  }

  AuthResult<UserSession> _loginFailure(DioException e,
      {required bool employee}) {
    debugPrint(
      '[auth] login DioException status=${e.response?.statusCode} '
      'type=${e.type} data=${e.response?.data}',
    );
    final statusCode = e.response?.statusCode;
    if (statusCode == 401) {
      return (
        data: null,
        failure: AuthFailure(
          employee
              ? 'Invalid username or password'
              : 'Invalid business code, email, or password',
        ),
      );
    }
    if (statusCode == 403) {
      return (
        data: null,
        failure: AuthFailure(
          employee
              ? 'Use an enrolled employee account.'
              : 'This account is not a business owner.',
        ),
      );
    }
    if (e.type == DioExceptionType.connectionTimeout ||
        e.type == DioExceptionType.sendTimeout ||
        e.type == DioExceptionType.receiveTimeout ||
        e.type == DioExceptionType.connectionError) {
      return (
        data: null,
        failure: const NetworkFailure(
          'Cannot reach the backend server. Please make sure it is running.',
        ),
      );
    }
    return (
      data: null,
      failure: const ServerFailure(
        'Login server error. Please try again after the backend/database is ready.',
      ),
    );
  }
}

String? _errorDetail(Object? data) {
  if (data is Map<String, dynamic>) {
    final detail = data['detail'];
    if (detail is String && detail.trim().isNotEmpty) {
      return detail;
    }
  }
  return null;
}

DateTime? _parseDateTime(String? value) {
  if (value == null || value.isEmpty) return null;
  return DateTime.tryParse(value);
}
