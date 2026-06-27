import 'dart:io' show Platform;

import 'package:dio/dio.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

const _tokenKey = 'aroll_token';
const _businessCodeKey = 'aroll_business_code';

class ApiClient {
  ApiClient(this._storage) {
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
      ),
    );
  }

  final FlutterSecureStorage _storage;
  late final Dio _dio;

  Dio get dio => _dio;

  Future<void> saveToken(String token) => _storage.write(key: _tokenKey, value: token);

  Future<void> clearToken() => _storage.delete(key: _tokenKey);

  Future<String?> readToken() => _storage.read(key: _tokenKey);

  Future<void> saveBusinessCode(String code) =>
      _storage.write(key: _businessCodeKey, value: code);

  Future<void> clearBusinessCode() => _storage.delete(key: _businessCodeKey);

  Future<String?> readBusinessCode() => _storage.read(key: _businessCodeKey);
}

String _defaultApiBaseUrl() {
  if (Platform.isAndroid) {
    return 'http://10.0.2.2:8000/api/v1';
  }
  return 'http://127.0.0.1:8000/api/v1';
}
