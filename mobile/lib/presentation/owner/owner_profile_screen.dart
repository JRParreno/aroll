import 'package:aroll_mobile/core/app_state.dart';
import 'package:aroll_mobile/core/di/injection.dart';
import 'package:aroll_mobile/domain/entities/user_session.dart';
import 'package:aroll_mobile/domain/usecase/auth/logout_usecase.dart';
import 'package:aroll_mobile/presentation/owner/owner_shell.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class OwnerProfileScreen extends StatelessWidget {
  const OwnerProfileScreen({super.key, required this.session});

  final UserSession session;

  Future<void> _logout(BuildContext context) async {
    await sl<LogoutUsecase>()();
    sl<AppState>().clearSession();
    if (context.mounted) context.go('/login');
  }

  @override
  Widget build(BuildContext context) {
    return OwnerShell(
      selectedIndex: 2,
      showBackButton: true,
      title: 'Profile',
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          OwnerCard(
            child: Column(
              children: [
                const CircleAvatar(
                  radius: 38,
                  child: Icon(Icons.person_rounded, size: 40),
                ),
                const SizedBox(height: 12),
                Text(session.fullName,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                        )),
                Text(session.email ?? ''),
                const SizedBox(height: 4),
                Text(session.businessName),
              ],
            ),
          ),
          const SizedBox(height: 12),
          OwnerActionCard(
            title: 'Productivity Insights',
            subtitle: 'Performance trends and employee scores.',
            icon: Icons.insights_rounded,
            onTap: () => context.push('/owner/productivity'),
          ),
          OwnerActionCard(
            title: 'Business Location',
            subtitle: 'View workplace geofence configuration.',
            icon: Icons.location_on_outlined,
            onTap: () => context.push('/owner/location'),
          ),
          OwnerActionCard(
            title: 'Settings & Business Setup',
            subtitle: 'Account, payroll, attendance, and setup status.',
            icon: Icons.settings_outlined,
            onTap: () => context.push('/owner/settings'),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: () => _logout(context),
            icon: const Icon(Icons.logout_rounded),
            label: const Text('Log Out'),
          ),
        ],
      ),
    );
  }
}
