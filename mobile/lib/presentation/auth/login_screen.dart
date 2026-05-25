import 'package:aroll_mobile/core/app_state.dart';
import 'package:aroll_mobile/core/di/injection.dart';
import 'package:aroll_mobile/presentation/auth/bloc/login_bloc/login_bloc.dart';
import 'package:aroll_mobile/presentation/auth/bloc/login_bloc/login_event.dart';
import 'package:aroll_mobile/presentation/auth/bloc/login_bloc/login_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => sl<LoginBloc>(),
      child: BlocConsumer<LoginBloc, LoginState>(
        listener: (context, state) {
          if (state is SuccessLoginState) {
            sl<AppState>().setSession(
              state.session,
              mustChange: state.session.mustChangePassword,
            );
            if (state.session.mustChangePassword) {
              context.go('/change-password');
            } else {
              context.go('/home');
            }
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
            body: SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: 32),
                    Icon(
                      Icons.face_retouching_natural,
                      size: 72,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Aroll+',
                      style: Theme.of(context).textTheme.headlineMedium,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Employee sign in',
                      style: Theme.of(context).textTheme.bodyMedium,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 40),
                    ShadInput(
                      controller: _emailController,
                      placeholder: const Text('Email'),
                      keyboardType: TextInputType.emailAddress,
                    ),
                    const SizedBox(height: 16),
                    ShadInput(
                      controller: _passwordController,
                      placeholder: const Text('Password'),
                      obscureText: true,
                    ),
                    const SizedBox(height: 24),
                    ShadButton(
                      onPressed: loading
                          ? null
                          : () {
                              context.read<LoginBloc>().add(
                                    SubmitLoginEvent(
                                      email: _emailController.text.trim(),
                                      password: _passwordController.text,
                                    ),
                                  );
                            },
                      child: Text(loading ? 'Signing in…' : 'Sign in'),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Use credentials from your employer',
                      style: Theme.of(context).textTheme.bodySmall,
                      textAlign: TextAlign.center,
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
