import 'dart:io' show Platform;

import 'package:aroll_mobile/core/app_state.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

const _tokenKey = 'aroll_token';
const _businessCodeKey = 'aroll_business_code';

class ApiClient {
  ApiClient(this._storage, this._appState) {
    final base = dotenv.env['API_BASE_URL'] ?? _defaultApiBaseUrl();
    _dio = Dio(
      BaseOptions(
        baseUrl: base,
        connectTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(seconds: 15),
        headers: {'Content-Type': 'application/json'},
      ),
    );
    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          if (options.data is FormData) {
            options.headers.remove(Headers.contentTypeHeader);
          }

          final path = options.path;
          if (path.startsWith('/registrations')) {
            options.headers.remove('Authorization');
            handler.next(options);
            return;
          }

          final token = await _storage.read(key: _tokenKey);
          if (token != null) {
            options.headers['Authorization'] = 'Bearer $token';
          }
          handler.next(options);
        },
        onError: (error, handler) async {
          if (error.response?.statusCode == 401 &&
              !_skipUnauthorizedHandling(error.requestOptions.path)) {
            // Deduplicate: concurrent expired requests all return 401 at once.
            // Only the first one performs the logout; the rest propagate the
            // error while GoRouter's refreshListenable redirect is already
            // in flight.
            if (!_handlingUnauthorized) {
              _handlingUnauthorized = true;
              debugPrint(
                '[ApiClient] 401 on ${error.requestOptions.path} — '
                'clearing session and redirecting to /login',
              );
              await clearToken();
              await clearBusinessCode();
              _appState.clearSession();
            }
          }
          handler.next(error);
        },
      ),
    );
  }

  final FlutterSecureStorage _storage;
  final AppState _appState;
  late final Dio _dio;
  // Prevents multiple concurrent 401 responses from each triggering a full
  // logout cycle. Reset whenever a new session is established.
  bool _handlingUnauthorized = false;

  Dio get dio => _dio;

  Future<void> saveToken(String token) {
    _handlingUnauthorized = false;
    return _storage.write(key: _tokenKey, value: token);
  }

  Future<void> clearToken() => _storage.delete(key: _tokenKey);

  Future<String?> readToken() => _storage.read(key: _tokenKey);

  Future<void> saveBusinessCode(String code) =>
      _storage.write(key: _businessCodeKey, value: code);

  Future<void> clearBusinessCode() => _storage.delete(key: _businessCodeKey);

  Future<String?> readBusinessCode() => _storage.read(key: _businessCodeKey);
}

/// Paths that must NOT trigger the global 401 auto-logout:
///
/// * `/registrations/*`  — unauthenticated business-owner sign-up flow;
///                         any 401 here is an API-level error, not a session issue.
/// * `/auth/login`       — employee login; wrong credentials return 401 by design.
/// * `/auth/business-owner-login` — owner login; same as above.
/// * `/auth/me`          — session restore; `restoreSession()` owns its own error
///                         handling and decides whether to clear storage.
bool _skipUnauthorizedHandling(String path) {
  return path.startsWith('/registrations') ||
      path == '/auth/login' ||
      path == '/auth/business-owner-login' ||
      path == '/auth/me';
}

String _defaultApiBaseUrl() {
  if (Platform.isAndroid) {
    return 'http://10.0.2.2:8000/api/v1';
  }
  return 'http://127.0.0.1:8000/api/v1';
}
