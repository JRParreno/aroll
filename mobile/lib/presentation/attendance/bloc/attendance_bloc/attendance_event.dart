import 'package:equatable/equatable.dart';

abstract class AttendanceEvent extends Equatable {
  const AttendanceEvent();

  @override
  List<Object?> get props => [];
}

class FetchAttendanceEvent extends AttendanceEvent {
  const FetchAttendanceEvent({this.search});

  final String? search;

  @override
  List<Object?> get props => [search];
}

class NextPageAttendanceEvent extends AttendanceEvent {
  const NextPageAttendanceEvent({
    this.page = 1,
    this.size = 10,
    this.search,
  });

  final int page;
  final int size;
  final String? search;

  @override
  List<Object?> get props => [page, size, search];
}

class ResetAttendanceEvent extends AttendanceEvent {
  const ResetAttendanceEvent();
}
