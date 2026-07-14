import 'package:aroll_mobile/core/di/injection.dart';
import 'package:aroll_mobile/data/repositories/owner_repository.dart';
import 'package:aroll_mobile/presentation/owner/owner_shell.dart';
import 'package:aroll_mobile/presentation/owner/setup/setup_progress_card.dart';
import 'package:aroll_mobile/presentation/owner/setup/setup_wizard_constants.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class OwnerSetupScreen extends StatelessWidget {
  const OwnerSetupScreen({super.key});

  int _stepIndexForKey(String key) {
    final index = setupWizardStepKeys.indexOf(key);
    return index >= 0 ? index : 0;
  }

  @override
  Widget build(BuildContext context) => OwnerSecondaryScreen(
        title: 'Business Setup',
        future: sl<OwnerRepository>().setupStatus(),
        builder: (data) {
          final steps = (data['steps'] as List<dynamic>? ?? const [])
              .whereType<Map<String, dynamic>>();
          return [
            SetupProgressCard(data: data, showContinueButton: false),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () => context.push('/owner/setup-wizard?step=menu'),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF1E3A5F),
                ),
                child: const Text('Open Setup Wizard'),
              ),
            ),
            const SizedBox(height: 12),
            ...steps.where((step) => step['key'] != 'review').map(
              (step) {
                final key = '${step['key']}';
                final stepIndex = _stepIndexForKey(key);
                return OwnerCard(
                  margin: const EdgeInsets.only(bottom: 10),
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(
                      step['complete'] == true
                          ? Icons.check_circle_rounded
                          : Icons.radio_button_unchecked_rounded,
                      color: step['complete'] == true
                          ? Colors.green
                          : Colors.orange,
                    ),
                    title: Text('${step['label'] ?? step['key']}'),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () => context.push(
                      '/owner/setup-wizard?step=$stepIndex',
                    ),
                  ),
                );
              },
            ),
            if (data['setup_completed_at'] != null)
              FilledButton(
                onPressed: () => context.go('/owner/home'),
                child: const Text('Continue to Dashboard'),
              ),
          ];
        },
      );
}
