import 'package:aroll_mobile/domain/usecase/auth/login_usecase.dart';
import 'package:aroll_mobile/presentation/auth/bloc/login_bloc/login_event.dart';
import 'package:aroll_mobile/presentation/auth/bloc/login_bloc/login_state.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

class LoginBloc extends Bloc<LoginEvent, LoginState> {
  LoginBloc({required LoginUsecase loginUsecase})
      : _loginUsecase = loginUsecase,
        super(const InitialLoginState()) {
    on<SubmitLoginEvent>(_onSubmit);
  }

  final LoginUsecase _loginUsecase;

  Future<void> _onSubmit(
    SubmitLoginEvent event,
    Emitter<LoginState> emit,
  ) async {
    emit(const LoadingLoginState());

    final result = await _loginUsecase(
      email: event.email,
      password: event.password,
    );

    if (result.failure != null) {
      emit(ErrorLoginState(message: result.failure!.message));
      return;
    }

    emit(SuccessLoginState(session: result.data!));
  }
}
