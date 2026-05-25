import 'package:equatable/equatable.dart';

enum AttendanceType { clockIn, clockOut }

class AttendanceRecord extends Equatable {
  const AttendanceRecord({
    required this.id,
    required this.employeeName,
    required this.type,
    required this.recordedAt,
    required this.locationLabel,
  });

  final String id;
  final String employeeName;
  final AttendanceType type;
  final DateTime recordedAt;
  final String locationLabel;

  @override
  List<Object?> get props => [id, employeeName, type, recordedAt, locationLabel];
}
