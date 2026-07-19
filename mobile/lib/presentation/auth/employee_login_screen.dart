import 'package:aroll_mobile/core/app_state.dart';
import 'package:aroll_mobile/core/di/injection.dart';
import 'package:aroll_mobile/core/router/app_router.dart';
import 'package:aroll_mobile/domain/repositories/employee_repository.dart';
import 'package:aroll_mobile/presentation/auth/bloc/login_bloc/login_bloc.dart';
import 'package:aroll_mobile/presentation/auth/bloc/login_bloc/login_event.dart';
import 'package:aroll_mobile/presentation/auth/bloc/login_bloc/login_state.dart';
import 'package:aroll_mobile/presentation/auth/auth_form_field.dart';
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

          return Scaffold(
            resizeToAvoidBottomInset: true,
            backgroundColor: const Color(0xFF1E466E),
            appBar: AppBar(
              backgroundColor: Colors.transparent,
              elevation: 0,
              foregroundColor: Colors.white,
              title: const Text('Employee Sign In'),
            ),
            body: SafeArea(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Image.asset(
                      'assets/branding/logo.png',
                      height: 140,
                      fit: BoxFit.contain,
                    ),
                    const SizedBox(height: 32),
                    AuthFormField(
                      controller: _emailController,
                      hintText: 'Username',
                      textInputAction: TextInputAction.next,
                    ),
                    const SizedBox(height: 12),
                    AuthFormField(
                      controller: _passwordController,
                      hintText: 'Password',
                      obscureText: true,
                      textInputAction: TextInputAction.done,
                      onSubmitted: (_) => _submit(context, loading),
                    ),
                    const SizedBox(height: 18),
                    AuthPrimaryButton(
                      label: 'Sign In',
                      loading: loading,
                      onPressed:
                          loading ? null : () => _submit(context, false),
                    ),
                    const SizedBox(height: 14),
                    const Text(
                      'Use the username and password provided by your employer.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Color(0xFFC8D8E7),
                        fontSize: 12,
                        height: 1.4,
                      ),
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

  void _submit(BuildContext context, bool loading) {
    if (loading) return;
    context.read<LoginBloc>().add(
          SubmitLoginEvent(
            email: _emailController.text.trim(),
            password: _passwordController.text.trim(),
          ),
        );
  }
}
