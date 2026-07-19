import 'package:flutter/material.dart';

const setupWizardStepLabels = [
  'Shifts',
  'Positions',
  'Payroll',
  'Attendance Policy',
  'Holidays',
  'Location',
  'Review',
];

const setupWizardBusinessInfoStep = 7;

const setupWizardStepKeys = [
  'shifts',
  'positions',
  'payroll',
  'attendance_policy',
  'holidays',
  'location',
  'review',
];

const setupWizardStepOrder = [
  'shifts',
  'positions',
  'payroll',
  'attendance_policy',
  'holidays',
  'location',
];

const requiredSetupKeys = {'shifts', 'positions', 'payroll', 'location'};

const setupStepHelp = {
  'Shifts': 'Add the work shifts your employees can be assigned to.',
  'Positions': 'Create job roles and daily rates for payroll calculations.',
  'Payroll':
      'Set pay schedules, deductions, overtime, and rest day premium rules.',
  'Attendance Policy':
      'Choose the time rules used for lateness, absences, and overtime.',
  'Holidays':
      'Add the holidays your business follows. This helps schedules and pay stay accurate.',
  'Location':
      'Set your business work site so attendance can be checked by location.',
  'Business Information':
      'Review your registered business profile and contact details.',
  'Review':
      'Check your setup progress and finish when the required parts are ready.',
};

class SetupMenuEntry {
  const SetupMenuEntry({
    required this.label,
    required this.subtitle,
    required this.stepIndex,
    this.statusKey,
    required this.icon,
  });

  final String label;
  final String subtitle;
  final int stepIndex;
  final String? statusKey;
  final IconData icon;
}

const setupMenuEntries = [
  SetupMenuEntry(
    label: 'Business Information',
    subtitle: 'Review your registered business profile and contact details.',
    stepIndex: setupWizardBusinessInfoStep,
    icon: Icons.business_rounded,
  ),
  SetupMenuEntry(
    label: 'Positions',
    subtitle: 'Create job roles and daily rates for payroll calculations.',
    stepIndex: 1,
    statusKey: 'positions',
    icon: Icons.badge_outlined,
  ),
  SetupMenuEntry(
    label: 'Shifts',
    subtitle: 'Add the work shifts your employees can be assigned to.',
    stepIndex: 0,
    statusKey: 'shifts',
    icon: Icons.schedule_rounded,
  ),
  SetupMenuEntry(
    label: 'Payroll',
    subtitle: 'Set when employees are paid and how pay rules are applied.',
    stepIndex: 2,
    statusKey: 'payroll',
    icon: Icons.payments_outlined,
  ),
  SetupMenuEntry(
    label: 'Attendance Policy',
    subtitle:
        'Choose the time rules used for lateness, absences, and overtime.',
    stepIndex: 3,
    statusKey: 'attendance_policy',
    icon: Icons.fact_check_outlined,
  ),
  SetupMenuEntry(
    label: 'Holidays',
    subtitle:
        'Add the holidays your business follows. This helps schedules and pay stay accurate.',
    stepIndex: 4,
    statusKey: 'holidays',
    icon: Icons.event_outlined,
  ),
  SetupMenuEntry(
    label: 'Location',
    subtitle:
        'Set your business work site so attendance can be checked by location.',
    stepIndex: 5,
    statusKey: 'location',
    icon: Icons.location_on_outlined,
  ),
];

String setupWizardScreenTitle(int step) {
  if (step < 0) return 'Business Setup Wizard';
  if (step == setupWizardBusinessInfoStep) return 'Business Information';
  return setupWizardStepLabels[step];
}

String setupWizardStepHelp(int step) {
  if (step == setupWizardBusinessInfoStep) {
    return setupStepHelp['Business Information']!;
  }
  return setupStepHelp[setupWizardStepLabels[step]] ?? '';
}

int clampSetupStep(int step) => step.clamp(0, setupWizardStepLabels.length - 1);

/// `-1` opens the setup menu; `0..6` opens a specific step.
int parseSetupWizardInitialStep(String? stepParam) {
  if (stepParam == null || stepParam == 'menu') return -1;
  final parsed = int.tryParse(stepParam);
  if (parsed == null) return -1;
  return clampSetupStep(parsed);
}

int firstIncompleteSetupStepIndex(Map<String, dynamic> setupStatus) {
  final steps = (setupStatus['steps'] as List<dynamic>? ?? const [])
      .whereType<Map<String, dynamic>>();
  for (var i = 0; i < setupWizardStepOrder.length; i++) {
    final key = setupWizardStepOrder[i];
    final match = steps.where((step) => step['key'] == key);
    if (match.isEmpty || match.first['complete'] != true) {
      return i;
    }
  }
  return 0;
}

bool isSetupStepComplete(
  Map<String, dynamic>? setupStatus,
  String key,
) {
  if (setupStatus == null) return false;
  final steps = (setupStatus['steps'] as List<dynamic>? ?? const [])
      .whereType<Map<String, dynamic>>();
  for (final step in steps) {
    if (step['key'] == key) {
      return step['complete'] == true;
    }
  }
  return false;
}

bool canCompleteSetup(Map<String, dynamic>? setupStatus) {
  if (setupStatus == null) return false;
  final steps = (setupStatus['steps'] as List<dynamic>? ?? const [])
      .whereType<Map<String, dynamic>>();
  for (final step in steps) {
    final key = step['key'] as String?;
    if (key != null &&
        requiredSetupKeys.contains(key) &&
        step['complete'] != true) {
      return false;
    }
  }
  return true;
}

DateTime? parseSetupDateTime(Object? value) {
  if (value == null) return null;
  if (value is DateTime) return value;
  if (value is String && value.isNotEmpty) {
    return DateTime.tryParse(value);
  }
  return null;
}

String formatApiDate(DateTime date) {
  final y = date.year.toString().padLeft(4, '0');
  final m = date.month.toString().padLeft(2, '0');
  final d = date.day.toString().padLeft(2, '0');
  return '$y-$m-$d';
}

String formatApiTime(TimeOfDay time) {
  final h = time.hour.toString().padLeft(2, '0');
  final m = time.minute.toString().padLeft(2, '0');
  return '$h:$m';
}

TimeOfDay? parseApiTime(String? value) {
  if (value == null || value.isEmpty) return null;
  final parts = value.split(':');
  if (parts.length < 2) return null;
  final hour = int.tryParse(parts[0]);
  final minute = int.tryParse(parts[1]);
  if (hour == null || minute == null) return null;
  return TimeOfDay(hour: hour, minute: minute);
}
