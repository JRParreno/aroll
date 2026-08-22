import 'package:aroll_mobile/presentation/owner/owner_shell.dart';
import 'package:aroll_mobile/presentation/owner/setup/setup_ui.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

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
          const SetupSurfaceCard(
            child: SetupSectionHeader(
              icon: Icons.settings_outlined,
              title: 'Settings',
              subtitle: 'Manage your account and business setup.',
            ),
          ),
          const SizedBox(height: 14),
          SetupMenuCard(
            label: 'Business Setup Settings',
            subtitle:
                'Set up work shifts, job roles, pay, clock-in rules, holidays, and work location.',
            icon: Icons.checklist_rounded,
            showStatus: false,
            onTap: () => context.push('/owner/setup-wizard'),
          ),
          const SizedBox(height: 10),
          SetupMenuCard(
            label: 'Leave Policy',
            subtitle:
                'Choose which leave types are Paid Leave or Unpaid Leave.',
            icon: Icons.event_busy_outlined,
            showStatus: false,
            onTap: () => context.push('/owner/settings/leave-policy'),
          ),
          const SizedBox(height: 10),
          SetupMenuCard(
            label: 'Account Information',
            subtitle: 'View your owner and business account details.',
            icon: Icons.badge_outlined,
            showStatus: false,
            onTap: () => context.push('/owner/settings/account'),
          ),
          const SizedBox(height: 10),
          SetupMenuCard(
            label: 'Business Information Setup Summary',
            subtitle:
                'Review your complete business configuration in one place.',
            icon: Icons.fact_check_outlined,
            showStatus: false,
            onTap: () => context.push('/owner/settings/setup-summary'),
          ),
        ],
      ),
    );
  }
}
