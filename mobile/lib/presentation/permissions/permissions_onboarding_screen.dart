import 'package:aroll_mobile/core/app_state.dart';
import 'package:aroll_mobile/core/di/injection.dart';
import 'package:aroll_mobile/core/legal/privacy_preferences.dart';
import 'package:aroll_mobile/core/router/app_router.dart';
import 'package:aroll_mobile/presentation/employee/employee_ui.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:permission_handler/permission_handler.dart';

class PermissionsOnboardingScreen extends StatelessWidget {
  const PermissionsOnboardingScreen({super.key});

  Future<void> _continue(BuildContext context) async {
    await Permission.camera.request();
    await Permission.locationWhenInUse.request();
    await Permission.notification.request();
    await sl<PrivacyPreferences>().markPermissionsIntroSeen();
    sl<AppState>().setPermissionsIntroSeen(true);
    if (!context.mounted) return;
    context.go(resolveAuthenticatedRoute(sl<AppState>()));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: EmployeeColors.scaffold,
      appBar: AppBar(
        backgroundColor: EmployeeColors.scaffold,
        elevation: 0,
        title: const Text(
          'App permissions',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Aroll+ asks for these permissions only after you accept your workplace legal documents.',
                style: TextStyle(height: 1.4, color: EmployeeColors.textMuted),
              ),
              const SizedBox(height: 20),
              const _PermissionTile(
                icon: Icons.camera_alt_outlined,
                title: 'Camera',
                body: 'Used to enroll your face and to Time In / Time Out.',
              ),
              const _PermissionTile(
                icon: Icons.location_on_outlined,
                title: 'Location',
                body: 'Used to confirm you are inside the workplace geofence.',
              ),
              const _PermissionTile(
                icon: Icons.notifications_outlined,
                title: 'Notifications',
                body: 'Used for in-app attendance and leave notices on this device.',
              ),
              const Spacer(),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton(
                  onPressed: () => _continue(context),
                  child: const Text('Continue'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PermissionTile extends StatelessWidget {
  const _PermissionTile({
    required this.icon,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: EmployeeColors.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 4),
                Text(
                  body,
                  style: const TextStyle(
                    color: EmployeeColors.textMuted,
                    height: 1.4,
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
