import 'package:aroll_mobile/core/di/injection.dart';
import 'package:aroll_mobile/data/repositories/owner_repository.dart';
import 'package:aroll_mobile/presentation/owner/owner_shell.dart';
import 'package:aroll_mobile/presentation/owner/setup/setup_progress_card.dart';
import 'package:aroll_mobile/presentation/owner/setup/setup_ui.dart';
import 'package:aroll_mobile/presentation/owner/setup/setup_wizard_constants.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class OwnerSetupScreen extends StatelessWidget {
  const OwnerSetupScreen({super.key});

  int _stepIndexForKey(String key) {
    final index = setupWizardStepKeys.indexOf(key);
    return index >= 0 ? index : 0;
  }

  IconData _iconForKey(String key) {
    return switch (key) {
      'shifts' => Icons.schedule_rounded,
      'positions' => Icons.badge_outlined,
      'payroll' => Icons.payments_outlined,
      'attendance_policy' => Icons.fact_check_outlined,
      'holidays' => Icons.event_outlined,
      'location' => Icons.location_on_outlined,
      _ => Icons.settings_outlined,
    };
  }

  String _subtitleForKey(String key) {
    return switch (key) {
      'shifts' => 'Add the times your team usually works.',
      'positions' => 'Add job roles and their daily pay.',
      'payroll' => 'Choose pay frequency and pay rules.',
      'attendance_policy' => 'Set on-time, late, absent, and overtime rules.',
      'holidays' => 'Add holidays your business follows.',
      'location' => 'Set your workplace and attendance distance.',
      _ => 'Open this setup section.',
    };
  }

  @override
  Widget build(BuildContext context) => OwnerSecondaryScreen(
        title: 'Business Setup',
        future: sl<OwnerRepository>().setupStatus(),
        builder: (data) {
          final status = Map<String, dynamic>.from(data as Map);
          final steps = (status['steps'] as List<dynamic>? ?? const [])
              .whereType<Map<String, dynamic>>();
          return [
            SetupProgressCard(data: status, showContinueButton: false),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () =>
                    context.push('/owner/setup-wizard?step=menu'),
                style: SetupUi.primaryButton,
                child: const Text('Open Setup Wizard'),
              ),
            ),
            const SizedBox(height: 14),
            const SetupListLabel('Setup sections'),
            ...steps.where((step) => step['key'] != 'review').map(
              (step) {
                final key = '${step['key']}';
                final stepIndex = _stepIndexForKey(key);
                final complete = step['complete'] == true;
                final label = '${step['label'] ?? step['key']}';
                return Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: SetupMenuCard(
                    label: label,
                    subtitle: _subtitleForKey(key),
                    icon: _iconForKey(key),
                    complete: complete,
                    onTap: () => context.push(
                      '/owner/setup-wizard?step=$stepIndex',
                    ),
                  ),
                );
              },
            ),
            if (status['setup_completed_at'] != null) ...[
              const SizedBox(height: 4),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  style: SetupUi.primaryButton,
                  onPressed: () => context.go('/owner/home'),
                  child: const Text('Continue to Dashboard'),
                ),
              ),
            ],
          ];
        },
      );
}
