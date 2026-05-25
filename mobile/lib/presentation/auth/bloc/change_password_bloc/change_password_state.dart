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
  const SuccessChangePasswordState();
}

class ErrorChangePasswordState extends ChangePasswordState {
  const ErrorChangePasswordState({required this.message});

  final String message;

  @override
  List<Object?> get props => [message];
}
