import 'package:aroll_mobile/presentation/owner/setup/setup_wizard_constants.dart';
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

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Business Setup Progress',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF3F6FA),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    '$percent%',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF1E3A5F),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              '$completedParts of $totalParts parts completed',
              style: const TextStyle(fontSize: 12, color: Color(0xFF6B7280)),
            ),
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: LinearProgressIndicator(
                value: percent / 100,
                minHeight: 6,
                backgroundColor: const Color(0xFFE5E7EB),
                color: const Color(0xFF1E3A5F),
              ),
            ),
            if (showContinueButton) ...[
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () => context.push(
                    '/owner/setup-wizard?step=$continueStep',
                  ),
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF1E3A5F),
                  ),
                  child: const Text('Continue Setup'),
                ),
              ),
            ],
          ],
        ),
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
