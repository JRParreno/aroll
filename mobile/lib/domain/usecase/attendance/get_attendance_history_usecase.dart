import 'package:aroll_mobile/core/models/page_data.dart';
import 'package:aroll_mobile/domain/entities/attendance_record.dart';
import 'package:aroll_mobile/domain/repositories/attendance_repository.dart';

class GetAttendanceHistoryUsecase {
  const GetAttendanceHistoryUsecase(this._repository);

  final AttendanceRepository _repository;

  Future<AttendanceResult<PageData<AttendanceRecord>>> call({
    required int page,
    required int size,
    String? search,
  }) {
    return _repository.getHistory(page: page, size: size, search: search);
  }
}
