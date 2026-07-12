import 'package:aroll_mobile/domain/usecase/auth/login_usecase.dart';
import 'package:aroll_mobile/presentation/auth/bloc/login_bloc/login_bloc.dart';
import 'package:get_it/get_it.dart';

void initBloc(GetIt sl) {
  sl.registerFactory<LoginBloc>(
    () => LoginBloc(loginUsecase: sl<LoginUsecase>()),
  );
}
