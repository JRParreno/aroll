import 'package:aroll_mobile/core/error/failures.dart';
import 'package:aroll_mobile/core/models/page_data.dart';
import 'package:aroll_mobile/domain/entities/attendance_record.dart';

typedef AttendanceResult<T> = ({T? data, Failure? failure});

abstract class AttendanceRepository {
  Future<AttendanceResult<PageData<AttendanceRecord>>> getHistory({
    required int page,
    required int size,
    String? search,
  });
}
