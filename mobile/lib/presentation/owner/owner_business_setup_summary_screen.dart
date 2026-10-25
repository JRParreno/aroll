import 'package:aroll_mobile/core/di/injection.dart';
import 'package:aroll_mobile/data/repositories/owner_repository.dart';
import 'package:aroll_mobile/presentation/owner/owner_info_display.dart';
import 'package:aroll_mobile/presentation/owner/owner_shell.dart';
import 'package:aroll_mobile/presentation/owner/setup/setup_ui.dart';
import 'package:aroll_mobile/presentation/shared/app_ui.dart';
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
        final shifts = summary.shifts.map(_shiftItem).whereType<_SummaryItem>().toList();
        final positions =
            summary.positions.map(_positionItem).whereType<_SummaryItem>().toList();
        final nextPayday = summary.payroll['next_payday_date'];
        final paydayText = nextPayday == null || '$nextPayday'.trim().isEmpty
            ? 'Not set'
            : '$nextPayday'.trim();
        return [
          const SizedBox(height: 6),
          _SummarySection(
            title: 'Business Profile',
            child: _FactPanel(
              rows: [
                ('Business Name', _textOrNotSet(summary.business['business_name'])),
                ('Business Type', _textOrNotSet(summary.business['business_type'])),
                ('Business Code', _textOrNotSet(summary.business['business_code'])),
                (
                  'Business Status',
                  ownerStatusLabel(summary.business['application_status']),
                ),
              ],
            ),
          ),
          _SummarySection(
            title: 'Work Location',
            child: _FactPanel(
              rows: [
                (
                  'Workplace Address',
                  _textOrNotSet(
                    summary.location['address'] ?? summary.business['address'],
                  ),
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
          ),
          _SummarySection(
            title: 'Work Shifts',
            child: _ItemList(items: shifts, emptyLabel: 'None configured'),
          ),
          _SummarySection(
            title: 'Employee Positions',
            child: _ItemList(items: positions, emptyLabel: 'None configured'),
          ),
          _SummarySection(
            title: 'Payroll',
            child: _FactPanel(
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
                ('Next Payday', paydayText),
              ],
            ),
          ),
          _SummarySection(
            title: 'Attendance',
            child: _FactPanel(
              rows: [
                (
                  'Time-In Settings',
                  summary.attendancePolicy.isEmpty
                      ? 'Not configured'
                      : 'Configured',
                ),
                (
                  'Early Time-In Window',
                  _minutesLabel(summary.attendancePolicy['early_clock_in_minutes']),
                ),
                (
                  'Extra Minutes Before Late',
                  _minutesLabel(summary.attendancePolicy['on_time_grace_minutes']),
                ),
                (
                  'Minimum Worked Shift (%)',
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
          ),
          _SummarySection(
            title: 'Holidays',
            child: _FactPanel(
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
          ),
          _SummarySection(
            title: 'Rest Days',
            child: _FactPanel(
              rows: [
                ('Configured Rest Days', _restDayLabel(summary.restDayPolicy)),
              ],
            ),
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

String _textOrNotSet(Object? value) {
  if (value == null) return 'Not set';
  final text = '$value'.trim();
  if (text.isEmpty || text == 'null') return 'Not set';
  return text;
}

_SummaryItem? _shiftItem(Map<String, dynamic> shift) {
  final name = '${shift['name'] ?? ''}'.trim();
  if (name.isEmpty) return null;
  final start = shift['start_time'];
  final end = shift['end_time'];
  if (start != null && end != null) {
    return _SummaryItem(name, '$start–$end');
  }
  return _SummaryItem(name, null);
}

_SummaryItem? _positionItem(Map<String, dynamic> position) {
  final title = '${position['title'] ?? ''}'.trim();
  if (title.isEmpty) return null;
  final daily = position['daily_rate'];
  final hourly = position['hourly_rate'];
  final parts = <String>[];
  if (daily != null) parts.add('₱$daily/day');
  if (hourly != null) parts.add('₱$hourly/hr');
  if (parts.isEmpty) return _SummaryItem(title, null);
  return _SummaryItem(title, parts.join(' · '));
}

class _SummaryItem {
  const _SummaryItem(this.name, this.detail);

  final String name;
  final String? detail;
}

class _SummarySection extends StatelessWidget {
  const _SummarySection({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }
}

class _BoardCard extends StatelessWidget {
  const _BoardCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
      ),
      child: child,
    );
  }
}

class _FactPanel extends StatelessWidget {
  const _FactPanel({required this.rows});

  final List<(String, String)> rows;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (var i = 0; i < rows.length; i++) ...[
          if (i > 0) const SizedBox(height: 8),
          _BoardCard(child: _Fact(label: rows[i].$1, value: rows[i].$2)),
        ],
      ],
    );
  }
}

class _Fact extends StatelessWidget {
  const _Fact({required this.label, required this.value});

  final String label;
  final String value;

  bool get _isStatus =>
      label == 'Business Status' ||
      label == 'Work Location Validation' ||
      label == 'Work Location Validation Status' ||
      label == 'Time-In Settings';

  bool get _missing =>
      value == 'Not set' ||
      value == 'Not configured' ||
      value == 'None configured' ||
      value == 'No job roles with daily pay yet' ||
      value == '—%';

  @override
  Widget build(BuildContext context) {
    final positive = value == 'Enabled' || value == 'Configured';
    final Color valueColor;
    if (_isStatus && positive) {
      valueColor = SetupUi.navyOf(context);
    } else if (_missing || _isStatus) {
      valueColor = AppColors.textMuted;
    } else {
      valueColor = AppColors.textPrimary;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w400,
            height: 1.3,
            color: AppColors.textMuted,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            fontSize: 14,
            fontWeight: _missing ? FontWeight.w400 : FontWeight.w500,
            height: 1.35,
            color: valueColor,
          ),
        ),
      ],
    );
  }
}

class _ItemList extends StatelessWidget {
  const _ItemList({required this.items, required this.emptyLabel});

  final List<_SummaryItem> items;
  final String emptyLabel;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return _BoardCard(
        child: Text(
          emptyLabel,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w400,
            color: AppColors.textMuted,
          ),
        ),
      );
    }

    return Column(
      children: [
        for (var i = 0; i < items.length; i++) ...[
          if (i > 0) const SizedBox(height: 8),
          _BoardCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  items[i].name,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    height: 1.3,
                    color: AppColors.textPrimary,
                  ),
                ),
                if (items[i].detail != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    items[i].detail!,
                    style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w400,
                      height: 1.35,
                      color: AppColors.textMuted,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ],
    );
  }
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
