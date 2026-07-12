import 'package:flutter/material.dart';

const setupWizardStepLabels = [
  'Shifts',
  'Positions',
  'Payroll',
  'Attendance',
  'Holidays',
  'Rest Day',
  'Location',
  'Review',
];

const setupWizardStepKeys = [
  'shifts',
  'positions',
  'payroll',
  'attendance_policy',
  'holidays',
  'rest_day',
  'location',
  'review',
];

const setupWizardStepOrder = [
  'shifts',
  'positions',
  'payroll',
  'attendance_policy',
  'holidays',
  'rest_day',
  'location',
];

const requiredSetupKeys = {'shifts', 'positions', 'payroll', 'location'};

const setupStepHelp = {
  'Shifts': 'Add the work shifts your employees can be assigned to.',
  'Positions': 'Create job roles and daily rates for payroll calculations.',
  'Payroll': 'Set when employees are paid and how pay rules are applied.',
  'Attendance':
      'Choose the time rules used for lateness, absences, and overtime.',
  'Holidays':
      'Add the holidays your business follows. This helps schedules and pay stay accurate.',
  'Rest Day': 'Choose the regular weekly rest day and rest day pay settings.',
  'Location':
      'Set your business work site so attendance can be checked by location.',
  'Review':
      'Check your setup progress and finish when the required parts are ready.',
};

int clampSetupStep(int step) =>
    step.clamp(0, setupWizardStepLabels.length - 1);

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
