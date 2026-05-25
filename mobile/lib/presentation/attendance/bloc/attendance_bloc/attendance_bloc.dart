import 'package:aroll_mobile/core/enum/state_enum.dart';
import 'package:aroll_mobile/domain/usecase/attendance/get_attendance_history_usecase.dart';
import 'package:aroll_mobile/presentation/attendance/bloc/attendance_bloc/attendance_event.dart';
import 'package:aroll_mobile/presentation/attendance/bloc/attendance_bloc/attendance_state.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

class AttendanceBloc extends Bloc<AttendanceEvent, AttendanceState> {
  AttendanceBloc({
    required GetAttendanceHistoryUsecase getAttendanceHistoryUsecase,
  })  : _getAttendanceHistoryUsecase = getAttendanceHistoryUsecase,
        super(const InitialAttendanceState()) {
    on<FetchAttendanceEvent>(_onFetch);
    on<NextPageAttendanceEvent>(_onNextPage);
    on<ResetAttendanceEvent>(_onReset);
  }

  final GetAttendanceHistoryUsecase _getAttendanceHistoryUsecase;
  static const _pageSize = 10;

  Future<void> _onFetch(
    FetchAttendanceEvent event,
    Emitter<AttendanceState> emit,
  ) async {
    emit(const LoadingAttendanceState());

    final result = await _getAttendanceHistoryUsecase(
      page: 1,
      size: _pageSize,
      search: event.search,
    );

    if (result.failure != null) {
      emit(ErrorAttendanceState(message: result.failure!.message));
      return;
    }

    final page = result.data!;
    emit(
      SuccessAttendanceState(
        data: page,
        status: page.hasMore ? StateEnum.initial : StateEnum.noMoreData,
        search: event.search,
      ),
    );
  }

  Future<void> _onNextPage(
    NextPageAttendanceEvent event,
    Emitter<AttendanceState> emit,
  ) async {
    final current = state;
    if (current is! SuccessAttendanceState) return;
    if (current.status == StateEnum.loadingMore ||
        current.status == StateEnum.noMoreData) {
      return;
    }

    emit(current.copyWith(status: StateEnum.loadingMore));

    final nextPage = current.data.page + 1;
    final result = await _getAttendanceHistoryUsecase(
      page: nextPage,
      size: _pageSize,
      search: current.search,
    );

    if (result.failure != null) {
      emit(current.copyWith(status: StateEnum.initial));
      return;
    }

    final next = result.data!;
    final merged = current.data.append(next);

    emit(
      SuccessAttendanceState(
        data: merged,
        status: next.hasMore ? StateEnum.initial : StateEnum.noMoreData,
        search: current.search,
      ),
    );
  }

  void _onReset(
    ResetAttendanceEvent event,
    Emitter<AttendanceState> emit,
  ) {
    emit(const InitialAttendanceState());
  }
}
