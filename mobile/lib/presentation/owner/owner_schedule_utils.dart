import 'package:intl/intl.dart';

const ownerWeekdayLabels = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

DateTime ownerWeekStart(DateTime date) {
  final normalized = DateTime(date.year, date.month, date.day);
  return normalized.subtract(Duration(days: normalized.weekday - 1));
}

String ownerDateKey(DateTime date) => DateFormat('yyyy-MM-dd').format(date);

List<DateTime> ownerWeekDays(DateTime weekStart) =>
    List.generate(7, (index) => weekStart.add(Duration(days: index)));

String formatOwnerShiftTime(String value) {
  final parts = value.split(':');
  if (parts.isEmpty) return value;
  final hour = int.tryParse(parts[0]) ?? 0;
  final minute = parts.length > 1 ? parts[1] : '00';
  final period = hour >= 12 ? 'PM' : 'AM';
  final hour12 = hour % 12 == 0 ? 12 : hour % 12;
  return '$hour12:${minute.padLeft(2, '0')} $period';
}

String formatOwnerWeekRange(DateTime weekStart) {
  final weekEnd = weekStart.add(const Duration(days: 6));
  return '${DateFormat.MMMd().format(weekStart)} – '
      '${DateFormat.MMMd().format(weekEnd)}';
}

bool ownerShiftsOverlap(Map<String, dynamic> first, Map<String, dynamic> second) {
  final aStart = '${first['start_time']}';
  final aEnd = '${first['end_time']}';
  final bStart = '${second['start_time']}';
  final bEnd = '${second['end_time']}';
  return aStart.compareTo(bEnd) < 0 && bStart.compareTo(aEnd) < 0;
}

enum OwnerEmployeeAvailability { available, assigned, conflict }

OwnerEmployeeAvailability ownerAvailabilityFor({
  required Map<String, dynamic> employee,
  required Map<String, dynamic>? selectedShift,
  required List<Map<String, dynamic>> assignmentsForDate,
  required List<Map<String, dynamic>> shifts,
  String? editingAssignmentId,
}) {
  if (selectedShift == null) return OwnerEmployeeAvailability.available;

  final employeeId = '${employee['id']}';
  final selectedShiftId = '${selectedShift['id']}';
  final employeeAssignments = assignmentsForDate.where((assignment) {
    return assignment['employee_id'] == employeeId &&
        assignment['id'] != editingAssignmentId;
  });

  if (employeeAssignments.any((a) => a['shift_id'] == selectedShiftId)) {
    return OwnerEmployeeAvailability.assigned;
  }

  final hasConflict = employeeAssignments.any((assignment) {
    Map<String, dynamic>? assignedShift;
    for (final shift in shifts) {
      if (shift['id'] == assignment['shift_id']) {
        assignedShift = shift;
        break;
      }
    }
    if (assignedShift == null) return true;
    return ownerShiftsOverlap(assignedShift, selectedShift);
  });

  return hasConflict
      ? OwnerEmployeeAvailability.conflict
      : OwnerEmployeeAvailability.available;
}

List<Map<String, dynamic>> ownerBuildScheduleMatrix({
  required List<Map<String, dynamic>> employees,
  required List<Map<String, dynamic>> assignments,
  required DateTime weekStart,
}) {
  final dateKeys = ownerWeekDays(weekStart).map(ownerDateKey).toList();
  return employees.map((employee) {
    final employeeId = '${employee['id']}';
    final cells = dateKeys.map((dateKey) {
      return assignments
          .where(
            (assignment) =>
                assignment['employee_id'] == employeeId &&
                assignment['work_date'] == dateKey,
          )
          .toList(growable: false);
    }).toList(growable: false);
    return {'employee': employee, 'cells': cells};
  }).toList(growable: false);
}

String ownerInitials(String name) {
  final parts = name.trim().split(RegExp(r'\s+'));
  if (parts.isEmpty || parts.first.isEmpty) return '?';
  return parts.take(2).map((part) => part[0].toUpperCase()).join();
}
