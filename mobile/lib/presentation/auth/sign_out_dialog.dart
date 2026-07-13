import 'package:aroll_mobile/core/app_state.dart';
import 'package:aroll_mobile/core/di/injection.dart';
import 'package:aroll_mobile/domain/usecase/auth/logout_usecase.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

Future<void> confirmSignOut(
  BuildContext context, {
  String loginRoute = '/login',
}) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Sign Out'),
      content: const Text('Are you sure you want to sign out?'),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Sign Out'),
        ),
      ],
    ),
  );
  if (confirmed != true || !context.mounted) return;
  await sl<LogoutUsecase>()();
  sl<AppState>().clearSession();
  if (context.mounted) context.go(loginRoute);
}
