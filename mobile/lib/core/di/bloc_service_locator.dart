import 'package:aroll_mobile/domain/usecase/attendance/get_attendance_history_usecase.dart';
import 'package:aroll_mobile/domain/usecase/auth/login_usecase.dart';
import 'package:aroll_mobile/presentation/attendance/bloc/attendance_bloc/attendance_bloc.dart';
import 'package:aroll_mobile/presentation/auth/bloc/login_bloc/login_bloc.dart';
import 'package:get_it/get_it.dart';

void initBloc(GetIt sl) {
  sl.registerFactory<LoginBloc>(
    () => LoginBloc(loginUsecase: sl<LoginUsecase>()),
  );
  sl.registerFactory<AttendanceBloc>(
    () => AttendanceBloc(
      getAttendanceHistoryUsecase: sl<GetAttendanceHistoryUsecase>(),
    ),
  );
}
