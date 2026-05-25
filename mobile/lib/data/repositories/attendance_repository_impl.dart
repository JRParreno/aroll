import 'package:aroll_mobile/core/models/page_data.dart';
import 'package:aroll_mobile/domain/entities/attendance_record.dart';
import 'package:aroll_mobile/domain/repositories/attendance_repository.dart';

class AttendanceRepositoryImpl implements AttendanceRepository {
  static final List<AttendanceRecord> _mockRecords = List.generate(
    28,
    (index) {
      final day = 24 - (index % 14);
      return AttendanceRecord(
        id: 'att-${index + 1}',
        employeeName: _employees[index % _employees.length],
        type: index.isEven ? AttendanceType.clockIn : AttendanceType.clockOut,
        recordedAt: DateTime(2026, 5, day, 8 + (index % 10), (index * 7) % 60),
        locationLabel: 'Mr. Bean Cafe — Main',
      );
    },
  );

  static const _employees = [
    'Maria Santos',
    'Juan Dela Cruz',
    'Ana Reyes',
    'Carlo Bicol',
  ];

  @override
  Future<AttendanceResult<PageData<AttendanceRecord>>> getHistory({
    required int page,
    required int size,
    String? search,
  }) async {
    await Future<void>.delayed(const Duration(milliseconds: 600));

    var filtered = _mockRecords;
    if (search != null && search.trim().isNotEmpty) {
      final query = search.trim().toLowerCase();
      filtered = _mockRecords
          .where((r) => r.employeeName.toLowerCase().contains(query))
          .toList();
    }

    final totalItems = filtered.length;
    final totalPages = totalItems == 0 ? 1 : (totalItems / size).ceil();
    final start = (page - 1) * size;

    if (start >= totalItems) {
      return (
        data: PageData<AttendanceRecord>(
          items: const [],
          page: page,
          size: size,
          totalPages: totalPages,
          totalItems: totalItems,
        ),
        failure: null,
      );
    }

    final end = (start + size).clamp(0, totalItems);
    final slice = filtered.sublist(start, end);

    return (
      data: PageData<AttendanceRecord>(
        items: slice,
        page: page,
        size: size,
        totalPages: totalPages,
        totalItems: totalItems,
      ),
      failure: null,
    );
  }
}
