import 'package:aroll_mobile/core/di/injection.dart';
import 'package:aroll_mobile/data/repositories/owner_repository.dart';
import 'package:aroll_mobile/presentation/owner/owner_info_display.dart';
import 'package:aroll_mobile/presentation/owner/owner_shell.dart';
import 'package:aroll_mobile/presentation/owner/setup/setup_ui.dart';
import 'package:flutter/material.dart';

class OwnerBusinessSetupSummaryScreen extends StatelessWidget {
  const OwnerBusinessSetupSummaryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return OwnerSecondaryScreen(
      selectedIndex: 2,
      title: 'Setup Summary',
      backgroundColor: SetupUi.scaffold,
      future: _loadSummary(),
      builder: (data) {
        final summary = data as _SetupSummaryData;
        return [
          const SetupSurfaceCard(
            child: SetupSectionHeader(
              icon: Icons.fact_check_outlined,
              title: 'Business Information Setup Summary',
              subtitle:
                  'Read-only overview of your business configuration. Use Business Setup Settings to make changes.',
            ),
          ),
          const SizedBox(height: 14),
          OwnerInfoSection(
            title: 'Business Profile',
            icon: Icons.business_rounded,
            skipEmpty: false,
            rows: [
              ('Business Name', summary.business['business_name']),
              ('Business Type', summary.business['business_type']),
              ('Business Code', summary.business['business_code']),
              (
                'Business Status',
                ownerStatusLabel(summary.business['application_status']),
              ),
            ],
          ),
          OwnerInfoSection(
            title: 'Work Location',
            icon: Icons.location_on_outlined,
            skipEmpty: false,
            rows: [
              (
                'Workplace Address',
                summary.location['address'] ?? summary.business['address'],
              ),
              (
                'Allowed Attendance Radius',
                _radiusLabel(summary.location['geofence_radius_m']),
              ),
              (
                'Work Location Validation',
                _locationValidationLabel(summary.location),
              ),
            ],
          ),
          OwnerInfoSection(
            title: 'Work Shifts',
            icon: Icons.schedule_rounded,
            skipEmpty: false,
            rows: [
              (
                'Configured Shifts',
                summary.shifts.isEmpty
                    ? 'None configured'
                    : summary.shifts
                        .map(_shiftLabel)
                        .whereType<String>()
                        .join('\n'),
              ),
            ],
          ),
          OwnerInfoSection(
            title: 'Employee Positions',
            icon: Icons.badge_outlined,
            skipEmpty: false,
            rows: [
              (
                'Configured Positions',
                summary.positions.isEmpty
                    ? 'None configured'
                    : summary.positions
                        .map(_positionLabel)
                        .whereType<String>()
                        .join('\n'),
              ),
            ],
          ),
          OwnerInfoSection(
            title: 'Payroll',
            icon: Icons.payments_outlined,
            skipEmpty: false,
            rows: [
              (
                'Payroll Frequency',
                ownerPayFrequencyLabel(summary.payroll['pay_period_type']),
              ),
              (
                'Daily Rate Settings',
                summary.positions.isEmpty
                    ? 'No job roles with daily pay yet'
                    : '${summary.positions.length} job role'
                        '${summary.positions.length == 1 ? '' : 's'} configured',
              ),
              (
                'Next Payday',
                summary.payroll['next_payday_date'],
              ),
            ],
          ),
          OwnerInfoSection(
            title: 'Attendance',
            icon: Icons.fact_check_outlined,
            skipEmpty: false,
            rows: [
              (
                'Clock-In Settings',
                summary.attendancePolicy.isEmpty
                    ? 'Not configured'
                    : 'Configured',
              ),
              (
                'Early Clock-In Window',
                _minutesLabel(summary.attendancePolicy['early_clock_in_minutes']),
              ),
              (
                'Extra Minutes Before Late',
                _minutesLabel(summary.attendancePolicy['on_time_grace_minutes']),
              ),
              (
                'Absent If Under (% of Shift)',
                '${summary.attendancePolicy['absent_threshold_percent'] ?? '—'}%',
              ),
              (
                'Minimum Overtime',
                _minutesLabel(
                  summary.attendancePolicy['overtime_minimum_minutes'],
                ),
              ),
              (
                'Maximum Overtime Duration',
                _minutesLabel(
                  summary.attendancePolicy['maximum_overtime_minutes'],
                ),
              ),
              (
                'Work Location Validation Status',
                _locationValidationLabel(summary.location),
              ),
            ],
          ),
          OwnerInfoSection(
            title: 'Holidays',
            icon: Icons.event_outlined,
            skipEmpty: false,
            rows: [
              (
                'Configured Holidays',
                summary.holidays.isEmpty
                    ? 'None configured'
                    : '${summary.holidays.length} holiday'
                        '${summary.holidays.length == 1 ? '' : 's'}',
              ),
            ],
          ),
          OwnerInfoSection(
            title: 'Rest Days',
            icon: Icons.weekend_outlined,
            skipEmpty: false,
            rows: [
              (
                'Configured Rest Days',
                _restDayLabel(summary.restDayPolicy),
              ),
            ],
          ),
        ];
      },
    );
  }

  Future<_SetupSummaryData> _loadSummary() async {
    final repo = sl<OwnerRepository>();
    final results = await Future.wait([
      repo.businessSettings(),
      repo.location(),
      repo.shifts(),
      repo.positions(),
      repo.payrollConfig(),
      repo.attendancePolicy(),
      repo.holidays(),
      repo.restDayPolicy(),
    ]);

    return _SetupSummaryData(
      business: results[0] as Map<String, dynamic>,
      location: results[1] as Map<String, dynamic>,
      shifts: (results[2] as List).whereType<Map<String, dynamic>>().toList(),
      positions: (results[3] as List).whereType<Map<String, dynamic>>().toList(),
      payroll: results[4] as Map<String, dynamic>,
      attendancePolicy: results[5] as Map<String, dynamic>,
      holidays: (results[6] as List).whereType<Map<String, dynamic>>().toList(),
      restDayPolicy: results[7] as Map<String, dynamic>,
    );
  }
}

class _SetupSummaryData {
  const _SetupSummaryData({
    required this.business,
    required this.location,
    required this.shifts,
    required this.positions,
    required this.payroll,
    required this.attendancePolicy,
    required this.holidays,
    required this.restDayPolicy,
  });

  final Map<String, dynamic> business;
  final Map<String, dynamic> location;
  final List<Map<String, dynamic>> shifts;
  final List<Map<String, dynamic>> positions;
  final Map<String, dynamic> payroll;
  final Map<String, dynamic> attendancePolicy;
  final List<Map<String, dynamic>> holidays;
  final Map<String, dynamic> restDayPolicy;
}

String? _shiftLabel(Map<String, dynamic> shift) {
  final name = '${shift['name'] ?? ''}'.trim();
  if (name.isEmpty) return null;
  final start = shift['start_time'];
  final end = shift['end_time'];
  if (start != null && end != null) {
    return '$name ($start–$end)';
  }
  return name;
}

String? _positionLabel(Map<String, dynamic> position) {
  final title = '${position['title'] ?? ''}'.trim();
  if (title.isEmpty) return null;
  final rate = position['daily_rate'];
  if (rate != null) {
    return '$title — ₱$rate/day';
  }
  return title;
}

String _radiusLabel(Object? radius) {
  if (radius == null) return 'Not set';
  final text = '$radius'.trim();
  if (text.isEmpty) return 'Not set';
  return '${text}m';
}

String _minutesLabel(Object? minutes) {
  if (minutes == null) return 'Not set';
  final text = '$minutes'.trim();
  if (text.isEmpty) return 'Not set';
  return '$text min';
}

String _locationValidationLabel(Map<String, dynamic> location) {
  final lat = location['latitude'];
  final lng = location['longitude'];
  final radius = location['geofence_radius_m'];
  if (lat != null && lng != null && radius != null) {
    return 'Enabled';
  }
  return 'Not set';
}

String _restDayLabel(Map<String, dynamic> policy) {
  final premium = policy['rest_day_premium_percent'];
  if (premium == null) return 'Not configured';
  return 'Extra pay on rest days: $premium%';
}
