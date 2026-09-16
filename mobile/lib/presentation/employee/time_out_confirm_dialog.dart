import 'package:aroll_mobile/presentation/shared/app_ui.dart';
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
    return AlertDialog(
      title: const Text('Are you sure you want to Time Out?'),
      content: const Text('Your attendance for this shift will be completed.'),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.primaryDark,
          ),
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Time Out'),
        ),
      ],
    );
  }
}
