import 'package:aroll_mobile/domain/entities/user_session.dart';
import 'package:equatable/equatable.dart';

abstract class LoginState extends Equatable {
  const LoginState();

  @override
  List<Object?> get props => [];
}

class InitialLoginState extends LoginState {
  const InitialLoginState();
}

class LoadingLoginState extends LoginState {
  const LoadingLoginState();
}

class ErrorLoginState extends LoginState {
  const ErrorLoginState({required this.message});

  final String message;

  @override
  List<Object?> get props => [message];
}

class SuccessLoginState extends LoginState {
  const SuccessLoginState({required this.session});

  final UserSession session;

  @override
  List<Object?> get props => [session];
}
