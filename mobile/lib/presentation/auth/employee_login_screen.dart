import 'package:aroll_mobile/core/app_state.dart';
import 'package:aroll_mobile/core/di/injection.dart';
import 'package:aroll_mobile/core/router/app_router.dart';
import 'package:aroll_mobile/domain/repositories/employee_repository.dart';
import 'package:aroll_mobile/presentation/auth/bloc/login_bloc/login_bloc.dart';
import 'package:aroll_mobile/presentation/auth/bloc/login_bloc/login_event.dart';
import 'package:aroll_mobile/presentation/auth/bloc/login_bloc/login_state.dart';
import 'package:aroll_mobile/presentation/auth/owner_auth_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

class EmployeeLoginScreen extends StatefulWidget {
  const EmployeeLoginScreen({super.key});

  @override
  State<EmployeeLoginScreen> createState() => _EmployeeLoginScreenState();
}

class _EmployeeLoginScreenState extends State<EmployeeLoginScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _onLoginSuccess(
    BuildContext context,
    SuccessLoginState state,
  ) async {
    final appState = sl<AppState>();
    appState.setSession(
      state.session,
      mustChange: state.session.mustChangePassword,
    );
    if (!state.session.mustChangePassword) {
      try {
        final face = await sl<EmployeeRepository>().getFaceStatus();
        appState.setFaceEnrolled(face.isCompleted);
      } catch (_) {
        appState.setFaceEnrolled(false);
      }
    }
    if (!context.mounted) return;
    context.go(resolveAuthenticatedRoute(appState));
  }

  void _submit(BuildContext context, bool loading) {
    if (loading) return;
    context.read<LoginBloc>().add(
          SubmitLoginEvent(
            email: _emailController.text.trim(),
            password: _passwordController.text.trim(),
          ),
        );
  }

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => sl<LoginBloc>(),
      child: BlocConsumer<LoginBloc, LoginState>(
        listener: (context, state) {
          if (state is SuccessLoginState) {
            _onLoginSuccess(context, state);
          }
          if (state is ErrorLoginState) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(state.message)),
            );
          }
        },
        builder: (context, state) {
          final loading = state is LoadingLoginState;

          return OwnerAuthScaffold(
            badgeLabel: 'Employee portal',
            title: 'Welcome back',
            subtitle:
                'Sign in with the username and password provided by your employer.',
            onBack: () => context.go('/login'),
            child: OwnerAuthCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  OwnerAuthField(
                    controller: _emailController,
                    label: 'Username',
                    hintText: 'Enter your username',
                    prefixIcon: Icons.person_outline_rounded,
                    textInputAction: TextInputAction.next,
                  ),
                  OwnerAuthField(
                    controller: _passwordController,
                    label: 'Password',
                    hintText: 'Enter your password',
                    prefixIcon: Icons.lock_outline_rounded,
                    obscureText: true,
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) => _submit(context, loading),
                  ),
                  const SizedBox(height: 4),
                  OwnerAuthPrimaryButton(
                    label: loading ? 'Signing in...' : 'Sign In',
                    loading: loading,
                    icon: Icons.arrow_forward_rounded,
                    onPressed: loading ? null : () => _submit(context, false),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
