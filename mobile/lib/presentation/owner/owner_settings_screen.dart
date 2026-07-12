import 'package:aroll_mobile/core/di/injection.dart';
import 'package:aroll_mobile/data/repositories/owner_repository.dart';
import 'package:aroll_mobile/presentation/owner/owner_shell.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class OwnerSettingsScreen extends StatelessWidget {
  const OwnerSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) => OwnerSecondaryScreen(
        title: 'Settings',
        future: Future.wait([
          sl<OwnerRepository>().accountSettings(),
          sl<OwnerRepository>().businessSettings(),
          sl<OwnerRepository>().payrollConfig(),
          sl<OwnerRepository>().attendancePolicy(),
        ]),
        builder: (data) {
          final values = data as List<Map<String, dynamic>>;
          return [
            _SettingsCard(title: 'Owner account', data: values[0]),
            _SettingsCard(title: 'Business profile', data: values[1]),
            _SettingsCard(title: 'Payroll configuration', data: values[2]),
            _SettingsCard(title: 'Attendance policy', data: values[3]),
            OwnerActionCard(
              title: 'Business Setup Wizard',
              subtitle: 'Walk through shifts, payroll, attendance, and location.',
              icon: Icons.checklist_rounded,
              onTap: () => context.push('/owner/setup-wizard'),
            ),
          ];
        },
      );
}

class _SettingsCard extends StatelessWidget {
  const _SettingsCard({required this.title, required this.data});

  final String title;
  final Map<String, dynamic> data;

  @override
  Widget build(BuildContext context) {
    final visible = data.entries
        .where((entry) =>
            entry.value != null &&
            entry.value is! Map &&
            entry.value is! List &&
            entry.key != 'id')
        .take(6);
    return OwnerCard(
      margin: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: const TextStyle(
                  fontWeight: FontWeight.w700, fontSize: 16)),
          const Divider(height: 24),
          for (final entry in visible)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: Text(ownerFormatKey(entry.key))),
                  const SizedBox(width: 12),
                  Flexible(
                    child: Text(
                      '${entry.value}',
                      textAlign: TextAlign.end,
                      style: const TextStyle(color: Color(0xFF6B7280)),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
