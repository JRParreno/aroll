import 'package:dio/dio.dart';

/// Reads FastAPI `{ "detail": { "code": "..." } }` from a Dio error.
///
/// Returns null for non-Dio errors, missing bodies, string `detail`, or
/// validation-error lists. Does not match against [DioException.toString].
String? apiErrorCode(Object? error) {
  if (error is! DioException) return null;
  final data = error.response?.data;
  if (data is! Map) return null;
  final detail = data['detail'];
  if (detail is! Map) return null;
  final code = detail['code']?.toString().trim();
  if (code == null || code.isEmpty) return null;
  return code;
}

bool isPayslipSnapshotUnavailable(Object? error) {
  return apiErrorCode(error) == 'payslip_snapshot_unavailable';
}
