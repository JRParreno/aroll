import 'package:aroll_mobile/core/app_state.dart';
import 'package:aroll_mobile/core/di/injection.dart';
import 'package:aroll_mobile/domain/usecase/auth/logout_usecase.dart';
import 'package:aroll_mobile/presentation/shared/confirm_action_dialog.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

Future<void> confirmSignOut(
  BuildContext context, {
  String loginRoute = '/login',
}) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => const ConfirmActionDialog(
      icon: Icons.logout_rounded,
      title: 'Sign Out',
      message: 'Are you sure you want to sign out?',
      messageTextAlign: TextAlign.center,
      confirmLabel: 'Sign Out',
    ),
  );
  if (confirmed != true || !context.mounted) return;
  await sl<LogoutUsecase>()();
  sl<AppState>().clearSession();
  if (context.mounted) context.go(loginRoute);
}
