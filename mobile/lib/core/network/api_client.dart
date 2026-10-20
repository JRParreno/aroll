import 'dart:io' show Platform;

import 'package:aroll_mobile/core/app_state.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

const _tokenKey = 'aroll_token';
const _businessCodeKey = 'aroll_business_code';
const _triedBasesKey = 'aroll_tried_bases';

class ApiClient {
  ApiClient(this._storage, this._appState) {
    final bases = _apiBaseCandidates();
    _dio = Dio(
      BaseOptions(
        baseUrl: bases.first,
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
          if (_isUnreachable(error)) {
            final retried = await _retryWithNextBase(error);
            if (retried != null) {
              handler.resolve(retried);
              return;
            }
          }
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

  String get apiOrigin {
    final uri = Uri.parse(_dio.options.baseUrl);
    if (uri.hasScheme && uri.host.isNotEmpty) {
      return uri.origin;
    }
    return 'http://127.0.0.1:8000';
  }

  String resolvePublicUrl(String path) {
    if (path.startsWith('http://') || path.startsWith('https://')) {
      return path;
    }
    if (path.startsWith('/')) {
      return '$apiOrigin$path';
    }
    return '$apiOrigin/$path';
  }

  Future<Response<dynamic>?> _retryWithNextBase(DioException error) async {
    final tried = List<String>.from(
      error.requestOptions.extra[_triedBasesKey] as List<dynamic>? ??
          [_dio.options.baseUrl],
    );
    for (final candidate in _apiBaseCandidates()) {
      if (tried.contains(candidate)) continue;
      debugPrint(
        '[ApiClient] ${error.requestOptions.path} unreachable at '
        '${_dio.options.baseUrl}; retrying $candidate',
      );
      _dio.options.baseUrl = candidate;
      final opts = error.requestOptions;
      opts.baseUrl = candidate;
      opts.extra[_triedBasesKey] = [...tried, candidate];
      try {
        return await _dio.fetch(opts);
      } on DioException catch (retryError) {
        if (!_isUnreachable(retryError)) rethrow;
      }
    }
    return null;
  }

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

bool _isUnreachable(DioException error) {
  return error.type == DioExceptionType.connectionError ||
      error.type == DioExceptionType.connectionTimeout;
}

String _defaultApiBaseUrl() {
  if (Platform.isAndroid) {
    return 'http://10.0.2.2:8000/api/v1';
  }
  return 'http://127.0.0.1:8000/api/v1';
}

List<String> _apiBaseCandidates() {
  final configured = dotenv.env['API_BASE_URL']?.trim();
  final seen = <String>{};
  final ordered = <String>[];
  for (final candidate in [
    if (configured != null && configured.isNotEmpty) configured,
    _defaultApiBaseUrl(),
    'http://127.0.0.1:8000/api/v1',
    'http://10.0.2.2:8000/api/v1',
  ]) {
    if (seen.add(candidate)) ordered.add(candidate);
  }
  return ordered;
}
