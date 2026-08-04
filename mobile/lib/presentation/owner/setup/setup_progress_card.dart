import 'package:aroll_mobile/presentation/owner/setup/setup_ui.dart';
import 'package:aroll_mobile/presentation/owner/setup/setup_wizard_constants.dart';
import 'package:aroll_mobile/presentation/shared/app_ui.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class SetupProgressCard extends StatelessWidget {
  const SetupProgressCard({
    super.key,
    required this.data,
    this.showContinueButton = true,
  });

  final Map<String, dynamic> data;
  final bool showContinueButton;

  @override
  Widget build(BuildContext context) {
    final setupCompletedAt = parseSetupDateTime(data['setup_completed_at']);
    final percent = _number(data['completion_percent']).clamp(0, 100);
    if (setupCompletedAt != null && percent >= 100) {
      return const SizedBox.shrink();
    }

    final completedParts = _countCompletedSteps(data);
    final totalParts = setupWizardStepOrder.length;
    final continueStep = firstIncompleteSetupStepIndex(data);

    return SetupSurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: AppColors.iconWell,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.checklist_rounded,
                  size: 20,
                  color: SetupUi.navy,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Business Setup Progress',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '$completedParts of $totalParts parts completed',
                      style: appMutedStyle().copyWith(fontSize: 12),
                    ),
                  ],
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: AppColors.chipFill,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  '$percent%',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: SetupUi.navy,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: percent / 100,
              minHeight: 8,
              backgroundColor: const Color(0xFFE8EEF4),
              color: SetupUi.navy,
            ),
          ),
          if (showContinueButton) ...[
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                style: SetupUi.primaryButton,
                onPressed: () => context.push(
                  '/owner/setup-wizard?step=$continueStep',
                ),
                child: const Text('Continue Setup'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

int _countCompletedSteps(Map<String, dynamic> data) {
  final steps = (data['steps'] as List<dynamic>? ?? const [])
      .whereType<Map<String, dynamic>>();
  return steps
      .where((step) =>
          step['key'] != 'review' && step['complete'] == true)
      .length;
}

int _number(Object? value) {
  if (value is int) return value;
  if (value is double) return value.round();
  if (value is String) return int.tryParse(value) ?? 0;
  return 0;
}
