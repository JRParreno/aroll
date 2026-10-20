import 'package:aroll_mobile/presentation/shared/app_ui.dart';
import 'package:aroll_mobile/presentation/shared/confirm_action_dialog.dart';
import 'package:flutter/material.dart';

Future<bool> showTimeOutConfirmation(BuildContext context) async {
  final confirmed = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (context) => const TimeOutConfirmDialog(),
  );
  return confirmed == true;
}

class TimeOutConfirmDialog extends StatelessWidget {
  const TimeOutConfirmDialog({super.key});

  @override
  Widget build(BuildContext context) {
    return const ConfirmActionDialog(
      icon: Icons.schedule_rounded,
      title: 'Time Out?',
      message: 'Are you sure you want to Time Out?',
      messageSecondary: 'Your attendance for this shift will be completed.',
      // Match primary message color/weight so both lines read as one body.
      messageSecondaryStyle: TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w500,
        color: AppColors.textMuted,
        height: 1.45,
      ),
      messageTextAlign: TextAlign.center,
      confirmLabel: 'Time Out',
      iconColor: AppColors.primaryDark,
      iconBackground: AppColors.iconWell,
      confirmColor: AppColors.primaryDark,
    );
  }
}
