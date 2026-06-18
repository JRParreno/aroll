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

    final router = GoRouter.of(context);



    debugPrint(

      '[pwd] SUCCESS listener fired '

      'route=${router.state.matchedLocation} '

      'uri=${router.state.uri}',

    );

    debugPrint(

      '[pwd] must_change_password BEFORE: '

      'appState=${appState.mustChangePassword} '

      'session=${appState.session?.mustChangePassword}',

    );

    debugPrint(

      '[pwd] API session must_change_password=${state.session.mustChangePassword}',

    );



    // Password change succeeded — always clear the gate so router allows /home.

    final clearedSession = state.session.copyWith(mustChangePassword: false);

    appState.setSession(clearedSession, mustChange: false);



    debugPrint(

      '[pwd] must_change_password AFTER: '

      'appState=${appState.mustChangePassword} '

      'session=${appState.session?.mustChangePassword}',

    );

    debugPrint('[pwd] navigating to /home (same pattern as login)');



    context.go('/home');



    debugPrint(

      '[pwd] route immediately after go: '

      'loc=${router.state.matchedLocation} uri=${router.state.uri}',

    );

  }



  @override

  Widget build(BuildContext context) {

    debugPrint('[pwd] ChangePasswordScreen build');



    return BlocProvider.value(

      value: _bloc,

      child: BlocConsumer<ChangePasswordBloc, ChangePasswordState>(

        listener: (context, state) {

          debugPrint('[pwd] bloc state -> ${state.runtimeType}');

          if (state is SuccessChangePasswordState) {

            _onSuccess(state);

          }

          if (state is ErrorChangePasswordState) {

            debugPrint('[pwd] error: ${state.message}');

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

                                    content: Text(

                                      'Password must be at least 8 characters',

                                    ),

                                  ),

                                );

                                return;

                              }

                              if (_newPass.text != _confirm.text) {

                                ScaffoldMessenger.of(context).showSnackBar(

                                  const SnackBar(

                                    content: Text('Passwords do not match'),

                                  ),

                                );

                                return;

                              }

                              _bloc.add(

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


