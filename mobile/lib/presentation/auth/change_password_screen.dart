import 'package:aroll_mobile/core/app_state.dart';
import 'package:aroll_mobile/core/di/injection.dart';
import 'package:aroll_mobile/core/utils/password_validation.dart';
import 'package:aroll_mobile/domain/usecase/auth/change_password_usecase.dart';
import 'package:aroll_mobile/presentation/auth/bloc/change_password_bloc/change_password_bloc.dart';
import 'package:aroll_mobile/presentation/auth/bloc/change_password_bloc/change_password_event.dart';
import 'package:aroll_mobile/presentation/auth/bloc/change_password_bloc/change_password_state.dart';
import 'package:aroll_mobile/presentation/auth/password_visibility.dart';
import 'package:aroll_mobile/presentation/employee/employee_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

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

  bool _showCurrent = false;
  bool _showNew = false;
  bool _showConfirm = false;

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

  InputDecoration _passwordDecoration({
    required String label,
    required bool visible,
    required VoidCallback onToggle,
  }) {
    return employeeInputDecoration(labelText: label).copyWith(
      suffixIcon: PasswordVisibilityToggle(
        visible: visible,
        onToggle: onToggle,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final validation = validatePassword(_newPass.text);

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
            backgroundColor: EmployeeColors.scaffold,
            appBar: AppBar(
              backgroundColor: EmployeeColors.scaffold,
              elevation: 0,
              scrolledUnderElevation: 0,
              title: const Text(
                'Change Password',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
            body: SafeArea(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Change your password',
                      style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'You must set a new password before continuing.',
                      style: TextStyle(color: EmployeeColors.textMuted),
                    ),
                    const SizedBox(height: 24),
                    TextField(
                      controller: _current,
                      obscureText: !_showCurrent,
                      decoration: _passwordDecoration(
                        label: 'Current (temporary) password',
                        visible: _showCurrent,
                        onToggle: () =>
                            setState(() => _showCurrent = !_showCurrent),
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _newPass,
                      obscureText: !_showNew,
                      decoration: _passwordDecoration(
                        label: 'New password',
                        visible: _showNew,
                        onToggle: () => setState(() => _showNew = !_showNew),
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                    if (_newPass.text.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      ...validation.errors.map(
                        (error) => Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: Text(
                            '• $error',
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.error,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 12),
                    TextField(
                      controller: _confirm,
                      obscureText: !_showConfirm,
                      decoration: _passwordDecoration(
                        label: 'Confirm new password',
                        visible: _showConfirm,
                        onToggle: () =>
                            setState(() => _showConfirm = !_showConfirm),
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                    const SizedBox(height: 24),
                    EmployeePrimaryButton(
                      label: loading ? 'Saving...' : 'Save password',
                      loading: loading,
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

                              if (!validation.valid) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(validation.errors.join('\n')),
                                  ),
                                );
                                return;
                              }

                              if (!passwordsMatch(newPassword, confirmPassword)) {
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
