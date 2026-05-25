import 'package:aroll_mobile/core/enum/state_enum.dart';
import 'package:aroll_mobile/core/models/page_data.dart';
import 'package:aroll_mobile/domain/entities/attendance_record.dart';
import 'package:equatable/equatable.dart';

abstract class AttendanceState extends Equatable {
  const AttendanceState();

  @override
  List<Object?> get props => [];
}

class InitialAttendanceState extends AttendanceState {
  const InitialAttendanceState();
}

class LoadingAttendanceState extends AttendanceState {
  const LoadingAttendanceState();
}

class ErrorAttendanceState extends AttendanceState {
  const ErrorAttendanceState({required this.message});

  final String message;

  @override
  List<Object?> get props => [message];
}

class SuccessAttendanceState extends AttendanceState {
  const SuccessAttendanceState({
    required this.data,
    this.status = StateEnum.initial,
    this.search,
  });

  final PageData<AttendanceRecord> data;
  final StateEnum status;
  final String? search;

  SuccessAttendanceState copyWith({
    PageData<AttendanceRecord>? data,
    StateEnum? status,
    String? search,
  }) {
    return SuccessAttendanceState(
      data: data ?? this.data,
      status: status ?? this.status,
      search: search ?? this.search,
    );
  }

  @override
  List<Object?> get props => [data, status, search];
}
