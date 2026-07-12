import 'package:aroll_mobile/core/app_state.dart';
import 'package:aroll_mobile/core/di/bloc_service_locator.dart';
import 'package:aroll_mobile/core/network/api_client.dart';
import 'package:aroll_mobile/data/repositories/auth_repository_impl.dart';
import 'package:aroll_mobile/data/repositories/employee_repository_impl.dart';
import 'package:aroll_mobile/data/repositories/owner_repository.dart';
import 'package:aroll_mobile/domain/repositories/auth_repository.dart';
import 'package:aroll_mobile/domain/repositories/employee_repository.dart';
import 'package:aroll_mobile/domain/usecase/auth/change_password_usecase.dart';
import 'package:aroll_mobile/domain/usecase/auth/login_usecase.dart';
import 'package:aroll_mobile/domain/usecase/auth/logout_usecase.dart';
import 'package:aroll_mobile/domain/usecase/auth/restore_session_usecase.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:get_it/get_it.dart';

final GetIt sl = GetIt.instance;

Future<void> initDependencies() async {
  sl.registerLazySingleton(
    () => const FlutterSecureStorage(
      aOptions: AndroidOptions(encryptedSharedPreferences: true),
    ),
  );
  sl.registerLazySingleton(AppState.new);
  sl.registerLazySingleton(
    () => ApiClient(sl<FlutterSecureStorage>(), sl<AppState>()),
  );
  sl.registerLazySingleton<AuthRepository>(
    () => AuthRepositoryImpl(sl<ApiClient>()),
  );
  sl.registerLazySingleton<EmployeeRepository>(
    () => EmployeeRepositoryImpl(sl<ApiClient>()),
  );
  sl.registerLazySingleton(() => OwnerRepository(sl<ApiClient>()));

  sl.registerLazySingleton(() => LoginUsecase(sl<AuthRepository>()));
  sl.registerLazySingleton(() => ChangePasswordUsecase(sl<AuthRepository>()));
  sl.registerLazySingleton(() => LogoutUsecase(sl<AuthRepository>()));
  sl.registerLazySingleton(
    () => RestoreSessionUsecase(sl<AuthRepository>(), sl<AppState>()),
  );

  initBloc(sl);
}
