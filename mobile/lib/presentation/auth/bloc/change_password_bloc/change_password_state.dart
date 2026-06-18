import 'package:aroll_mobile/domain/entities/user_session.dart';
import 'package:equatable/equatable.dart';

abstract class ChangePasswordState extends Equatable {
  const ChangePasswordState();

  @override
  List<Object?> get props => [];
}

class InitialChangePasswordState extends ChangePasswordState {
  const InitialChangePasswordState();
}

class LoadingChangePasswordState extends ChangePasswordState {
  const LoadingChangePasswordState();
}

class SuccessChangePasswordState extends ChangePasswordState {
  const SuccessChangePasswordState({required this.session});

  final UserSession session;

  @override
  List<Object?> get props => [session];
}

class ErrorChangePasswordState extends ChangePasswordState {
  const ErrorChangePasswordState({required this.message});

  final String message;

  @override
  List<Object?> get props => [message];
}
