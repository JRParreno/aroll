import 'package:aroll_mobile/core/app_state.dart';
import 'package:aroll_mobile/core/di/injection.dart';
import 'package:aroll_mobile/domain/usecase/auth/change_password_usecase.dart';
import 'package:aroll_mobile/presentation/auth/bloc/change_password_bloc/change_password_bloc.dart';
import 'package:aroll_mobile/presentation/auth/bloc/change_password_bloc/change_password_event.dart';
import 'package:aroll_mobile/presentation/auth/bloc/change_password_bloc/change_password_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

class ChangePasswordScreen extends StatefulWidget {
  const ChangePasswordScreen({super.key});

  @override
  State<ChangePasswordScreen> createState() => _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends State<ChangePasswordScreen> {
  final _current = TextEditingController();
  final _newPass = TextEditingController();
  final _confirm = TextEditingController();
  late final ChangePasswordBloc _bloc =
      ChangePasswordBloc(usecase: sl<ChangePasswordUsecase>());

  @override
  void dispose() {
    _bloc.close();
    _current.dispose();
    _newPass.dispose();
    _confirm.dispose();
    super.dispose();
  }

  void _onSuccess(SuccessChangePasswordState state) {
    final appState = sl<AppState>();
    final clearedSession = state.session.copyWith(mustChangePassword: false);
    appState.setSession(clearedSession, mustChange: false);
    context.go(clearedSession.isOwner ? '/owner/home' : '/face-registration');
  }

  @override
  Widget build(BuildContext context) {
    return BlocProvider.value(
      value: _bloc,
      child: BlocConsumer<ChangePasswordBloc, ChangePasswordState>(
        listener: (context, state) {
          if (state is SuccessChangePasswordState) {
            _onSuccess(state);
          }
          if (state is ErrorChangePasswordState) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(state.message)),
            );
          }
        },
        builder: (context, state) {
          final loading = state is LoadingChangePasswordState;

          return Scaffold(
            body: SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Change your password',
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'You must set a new password before continuing.',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 24),
                    ShadInput(
                      controller: _current,
                      placeholder: const Text('Current (temporary) password'),
                      obscureText: true,
                    ),
                    const SizedBox(height: 12),
                    ShadInput(
                      controller: _newPass,
                      placeholder: const Text('New password (min 8 chars)'),
                      obscureText: true,
                    ),
                    const SizedBox(height: 12),
                    ShadInput(
                      controller: _confirm,
                      placeholder: const Text('Confirm new password'),
                      obscureText: true,
                    ),
                    const SizedBox(height: 24),
                    ShadButton(
                      onPressed: loading
                          ? null
                          : () {
                              final currentPassword = _current.text.trim();
                              final newPassword = _newPass.text.trim();
                              final confirmPassword = _confirm.text.trim();

                              if (currentPassword.isEmpty) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                      'Enter your temporary password first',
                                    ),
                                  ),
                                );
                                return;
                              }

                              if (newPassword.length < 8) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                      'Password must be at least 8 characters',
                                    ),
                                  ),
                                );
                                return;
                              }

                              if (newPassword != confirmPassword) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('Passwords do not match'),
                                  ),
                                );
                                return;
                              }

                              _bloc.add(
                                SubmitChangePasswordEvent(
                                  currentPassword: currentPassword,
                                  newPassword: newPassword,
                                ),
                              );
                            },
                      child: Text(loading ? 'Saving...' : 'Save password'),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
