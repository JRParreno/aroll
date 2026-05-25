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

  @override
  void dispose() {
    _current.dispose();
    _newPass.dispose();
    _confirm.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => ChangePasswordBloc(usecase: sl<ChangePasswordUsecase>()),
      child: BlocConsumer<ChangePasswordBloc, ChangePasswordState>(
        listener: (context, state) {
          if (state is SuccessChangePasswordState) {
            sl<AppState>().passwordChanged();
            context.go('/home');
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
                              if (_newPass.text.length < 8) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('Password must be at least 8 characters'),
                                  ),
                                );
                                return;
                              }
                              if (_newPass.text != _confirm.text) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('Passwords do not match')),
                                );
                                return;
                              }
                              context.read<ChangePasswordBloc>().add(
                                    SubmitChangePasswordEvent(
                                      currentPassword: _current.text,
                                      newPassword: _newPass.text,
                                    ),
                                  );
                            },
                      child: Text(loading ? 'Saving…' : 'Save password'),
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
