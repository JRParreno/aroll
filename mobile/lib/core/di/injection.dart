import 'package:aroll_mobile/core/app_state.dart';
import 'package:aroll_mobile/core/di/bloc_service_locator.dart';
import 'package:aroll_mobile/core/network/api_client.dart';
import 'package:aroll_mobile/data/repositories/attendance_repository_impl.dart';
import 'package:aroll_mobile/data/repositories/auth_repository_impl.dart';
import 'package:aroll_mobile/domain/repositories/attendance_repository.dart';
import 'package:aroll_mobile/domain/repositories/auth_repository.dart';
import 'package:aroll_mobile/domain/usecase/attendance/get_attendance_history_usecase.dart';
import 'package:aroll_mobile/domain/usecase/auth/change_password_usecase.dart';
import 'package:aroll_mobile/domain/usecase/auth/login_usecase.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:get_it/get_it.dart';

final GetIt sl = GetIt.instance;

Future<void> initDependencies() async {
  sl.registerLazySingleton(() => const FlutterSecureStorage());
  sl.registerLazySingleton(() => ApiClient(sl()));
  sl.registerLazySingleton<AuthRepository>(
    () => AuthRepositoryImpl(sl<ApiClient>()),
  );
  sl.registerLazySingleton<AttendanceRepository>(
    AttendanceRepositoryImpl.new,
  );

  sl.registerLazySingleton(() => LoginUsecase(sl<AuthRepository>()));
  sl.registerLazySingleton(() => ChangePasswordUsecase(sl<AuthRepository>()));
  sl.registerLazySingleton(() => GetAttendanceHistoryUsecase(sl<AttendanceRepository>()));

  sl.registerLazySingleton(AppState.new);

  initBloc(sl);
}
