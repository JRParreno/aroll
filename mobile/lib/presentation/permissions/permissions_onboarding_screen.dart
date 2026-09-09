import 'package:aroll_mobile/core/app_state.dart';
import 'package:aroll_mobile/core/di/injection.dart';
import 'package:aroll_mobile/core/legal/privacy_preferences.dart';
import 'package:aroll_mobile/core/router/auth_redirect.dart';
import 'package:aroll_mobile/presentation/permissions/permission_rationale.dart';
import 'package:aroll_mobile/presentation/shared/app_ui.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:permission_handler/permission_handler.dart';

class PermissionsOnboardingScreen extends StatefulWidget {
  const PermissionsOnboardingScreen({super.key});

  @override
  State<PermissionsOnboardingScreen> createState() =>
      _PermissionsOnboardingScreenState();
}

class _PermissionsOnboardingScreenState
    extends State<PermissionsOnboardingScreen> {
  bool _saving = false;

  bool get _isDemo => sl<AppState>().session?.isDemo == true;

  Future<void> _finish() async {
    if (_saving) return;
    setState(() => _saving = true);
    await sl<PrivacyPreferences>().markPermissionsIntroSeen();
    sl<AppState>().setPermissionsIntroSeen(true);
    if (!mounted) return;
    context.go(resolveAuthenticatedRoute(sl<AppState>()));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.scaffold,
      appBar: AppBar(
        backgroundColor: AppColors.white,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
        automaticallyImplyLeading: false,
        title: const Text(
          'Permissions',
          style: TextStyle(fontWeight: FontWeight.w600, fontSize: 17),
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
              children: [
                Text('How Aroll+ uses device access', style: appPageTitleStyle()),
                const SizedBox(height: 8),
                Text(
                  _isDemo
                      ? 'This Demo account does not open the camera or request phone GPS for attendance. You can still read why live accounts need these permissions.'
                      : 'Aroll+ asks for each permission only when a feature needs it. You can allow them now or wait until Time In, face setup, or notifications.',
                  style: appMutedStyle(),
                ),
                const SizedBox(height: 20),
                _PermissionCard(
                  permission: AppDevicePermission.camera,
                  demoSkipped: _isDemo,
                  onAllow: _isDemo
                      ? null
                      : () => requestCameraWithRationale(context),
                ),
                const SizedBox(height: 12),
                _PermissionCard(
                  permission: AppDevicePermission.location,
                  demoSkipped: _isDemo,
                  onAllow: _isDemo
                      ? null
                      : () => requestLocationWithRationale(context),
                ),
                const SizedBox(height: 12),
                _PermissionCard(
                  permission: AppDevicePermission.notifications,
                  demoSkipped: false,
                  onAllow: () => requestNotificationWithRationale(context),
                ),
              ],
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
              child: FilledButton(
                style: appPrimaryButtonStyle(),
                onPressed: _saving ? null : _finish,
                child: Text(_saving ? 'Continuing…' : 'Continue'),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PermissionCard extends StatefulWidget {
  const _PermissionCard({
    required this.permission,
    required this.demoSkipped,
    required this.onAllow,
  });

  final AppDevicePermission permission;
  final bool demoSkipped;
  final Future<bool> Function()? onAllow;

  @override
  State<_PermissionCard> createState() => _PermissionCardState();
}

class _PermissionCardState extends State<_PermissionCard> {
  String? _statusLabel;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: appCardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: AppColors.iconWell,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  widget.permission.icon,
                  color: AppColors.primaryDark,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  widget.permission.title,
                  style: appSectionTitleStyle(),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(widget.permission.explanation, style: appBodyStyle()),
          if (widget.demoSkipped) ...[
            const SizedBox(height: 8),
            Text(
              'Not requested in Demo Mode.',
              style: appMutedStyle().copyWith(fontWeight: FontWeight.w600),
            ),
          ] else if (widget.onAllow != null) ...[
            const SizedBox(height: 12),
            OutlinedButton(
              style: appSecondaryButtonStyle(),
              onPressed: () async {
                final allowed = await widget.onAllow!();
                if (!mounted) return;
                setState(() {
                  _statusLabel = allowed ? 'Allowed' : 'Not allowed yet';
                });
              },
              child: const Text('Review and allow'),
            ),
            if (_statusLabel != null) ...[
              const SizedBox(height: 8),
              Text(_statusLabel!, style: appMutedStyle()),
            ],
          ],
        ],
      ),
    );
  }
}

bool _notificationRationaleOffered = false;

Future<void> maybeRequestNotificationPermission(BuildContext context) async {
  final status = await Permission.notification.status;
  if (status.isGranted || status.isLimited || !context.mounted) return;
  if (_notificationRationaleOffered) return;
  _notificationRationaleOffered = true;
  await requestNotificationWithRationale(context);
}
