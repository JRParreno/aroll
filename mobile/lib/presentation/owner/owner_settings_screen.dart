import 'package:aroll_mobile/presentation/owner/owner_shell.dart';
import 'package:aroll_mobile/presentation/owner/setup/setup_ui.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class OwnerSettingsEntry {
  const OwnerSettingsEntry({
    required this.label,
    required this.subtitle,
    required this.icon,
    required this.route,
  });

  final String label;
  final String subtitle;
  final IconData icon;
  final String route;
}

const ownerSettingsBrandingRoute = '/owner/settings/branding';

const ownerSettingsEntries = [
  OwnerSettingsEntry(
    label: 'Business Setup Settings',
    subtitle:
        'Set up work shifts, job roles, pay, time-in rules, holidays, and work location.',
    icon: Icons.checklist_rounded,
    route: '/owner/setup-wizard',
  ),
  OwnerSettingsEntry(
    label: 'Business Branding',
    subtitle: 'View and update your business logo and brand colors.',
    icon: Icons.palette_outlined,
    route: ownerSettingsBrandingRoute,
  ),
  OwnerSettingsEntry(
    label: 'Leave Policy',
    subtitle: 'Choose which leave types are Paid Leave or Unpaid Leave.',
    icon: Icons.event_busy_outlined,
    route: '/owner/settings/leave-policy',
  ),
  OwnerSettingsEntry(
    label: 'Consent Configuration',
    subtitle:
        'Manage workplace consent documents employees review and accept.',
    icon: Icons.gavel_outlined,
    route: '/owner/settings/consents',
  ),
  OwnerSettingsEntry(
    label: 'Audit History',
    subtitle:
        'Review read-only account and workplace activity for your business.',
    icon: Icons.history_rounded,
    route: '/owner/settings/audit-history',
  ),
  OwnerSettingsEntry(
    label: 'Account Information',
    subtitle: 'View your owner and business account details.',
    icon: Icons.badge_outlined,
    route: '/owner/settings/account',
  ),
  OwnerSettingsEntry(
    label: 'Business Information Setup Summary',
    subtitle: 'Review your complete business configuration in one place.',
    icon: Icons.fact_check_outlined,
    route: '/owner/settings/setup-summary',
  ),
];

class OwnerSettingsScreen extends StatelessWidget {
  const OwnerSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return OwnerShell(
      selectedIndex: 2,
      showBackButton: true,
      title: 'Settings',
      backgroundColor: SetupUi.scaffold,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
        children: [
          const SizedBox(height: 14),
          for (var i = 0; i < ownerSettingsEntries.length; i++) ...[
            if (i > 0) const SizedBox(height: 10),
            SetupMenuCard(
              label: ownerSettingsEntries[i].label,
              subtitle: ownerSettingsEntries[i].subtitle,
              icon: ownerSettingsEntries[i].icon,
              showStatus: false,
              onTap: () => context.push(ownerSettingsEntries[i].route),
            ),
          ],
        ],
      ),
    );
  }
}
