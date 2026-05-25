import 'package:aroll_mobile/domain/usecase/auth/change_password_usecase.dart';
import 'package:aroll_mobile/presentation/auth/bloc/change_password_bloc/change_password_event.dart';
import 'package:aroll_mobile/presentation/auth/bloc/change_password_bloc/change_password_state.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

class ChangePasswordBloc extends Bloc<ChangePasswordEvent, ChangePasswordState> {
  ChangePasswordBloc({required ChangePasswordUsecase usecase})
      : _usecase = usecase,
        super(const InitialChangePasswordState()) {
    on<SubmitChangePasswordEvent>(_onSubmit);
  }

  final ChangePasswordUsecase _usecase;

  Future<void> _onSubmit(
    SubmitChangePasswordEvent event,
    Emitter<ChangePasswordState> emit,
  ) async {
    emit(const LoadingChangePasswordState());
    final result = await _usecase(
      currentPassword: event.currentPassword,
      newPassword: event.newPassword,
    );
    if (result.failure != null) {
      emit(ErrorChangePasswordState(message: result.failure!.message));
      return;
    }
    emit(const SuccessChangePasswordState());
  }
}
