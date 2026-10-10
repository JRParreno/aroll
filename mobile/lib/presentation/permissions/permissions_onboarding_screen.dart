import 'package:aroll_mobile/core/app_state.dart';
import 'package:aroll_mobile/core/di/injection.dart';
import 'package:aroll_mobile/core/legal/employee_gate_loader.dart';
import 'package:aroll_mobile/core/legal/privacy_preferences.dart';
import 'package:aroll_mobile/core/router/app_router.dart';
import 'package:aroll_mobile/domain/repositories/employee_repository.dart';
import 'package:aroll_mobile/presentation/employee/employee_ui.dart';
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
  bool _loading = true;
  bool _busy = false;
  final Map<Permission, PermissionStatus> _statuses = {};

  static const _items = <_PermissionSpec>[
    _PermissionSpec(
      permission: Permission.camera,
      title: 'Camera',
      why: 'Use your camera for face attendance.',
      actionLabel: 'Allow Camera',
    ),
    _PermissionSpec(
      permission: Permission.locationWhenInUse,
      title: 'Location',
      why: 'Use your location for attendance and geofence verification.',
      actionLabel: 'Allow Location',
    ),
    _PermissionSpec(
      permission: Permission.notification,
      title: 'Notifications',
      why: 'Receive important attendance and account updates.',
      actionLabel: 'Allow Notifications',
    ),
  ];

  @override
  void initState() {
    super.initState();
    _refreshStatuses();
  }

  Future<void> _refreshStatuses() async {
    setState(() => _loading = true);
    final next = <Permission, PermissionStatus>{};
    for (final item in _items) {
      next[item.permission] = await item.permission.status;
    }
    if (!mounted) return;
    setState(() {
      _statuses
        ..clear()
        ..addAll(next);
      _loading = false;
    });
  }

  Future<void> _request(Permission permission) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final current = await permission.status;
      if (current.isGranted || current.isLimited) {
        if (!mounted) return;
        setState(() => _statuses[permission] = current);
        return;
      }
      if (current.isPermanentlyDenied || current.isRestricted) {
        await openAppSettings();
        await _refreshStatuses();
        return;
      }
      final result = await permission.request();
      if (!mounted) return;
      setState(() => _statuses[permission] = result);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _finish() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await _refreshStatuses();
      final appState = sl<AppState>();
      final userId = appState.session?.userId;
      // Persist only when required permissions were actually granted — not
      // merely because Continue was tapped (skip/deny must re-prompt later).
      final granted = !await anyOnboardingPermissionMissing();
      if (granted && userId != null && userId.isNotEmpty) {
        try {
          await sl<EmployeeRepository>().completePermissionsOnboarding();
          appState.setPermissionsOnboardingCompleted(true);
        } catch (_) {
          // Still mark local account/device state so this device does not trap
          // the employee; server remains authoritative on next successful sync.
        }
        final prefs = sl<PrivacyPreferences>();
        await prefs.markAccountOnboardingCompleted(userId);
        await prefs.markDeviceReviewedForAccount(userId);
      }
      appState.setPermissionsIntroSeen(true);
      if (!mounted) return;
      context.go(resolveAuthenticatedRoute(sl<AppState>()));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final primary = brandPrimary(context);
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : Padding(
                padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'App permissions',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.3,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Aroll+ needs a few permissions for attendance to work '
                      'on this device. You can allow or skip each one.',
                      style: TextStyle(
                        height: 1.45,
                        color: EmployeeColors.textMuted,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 28),
                    Expanded(
                      child: ListView.separated(
                        itemCount: _items.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 28),
                        itemBuilder: (context, index) {
                          final item = _items[index];
                          final status = _statuses[item.permission] ??
                              PermissionStatus.denied;
                          return _PermissionRow(
                            item: item,
                            status: status,
                            primary: primary,
                            busy: _busy,
                            onAllow: () => _request(item.permission),
                            onOpenSettings: () async {
                              await openAppSettings();
                              await _refreshStatuses();
                            },
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: FilledButton(
                        onPressed: _busy ? null : _finish,
                        style: FilledButton.styleFrom(
                          backgroundColor: primary,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: Text(
                          _busy ? 'Please wait…' : 'Continue',
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}

class _PermissionSpec {
  const _PermissionSpec({
    required this.permission,
    required this.title,
    required this.why,
    required this.actionLabel,
  });

  final Permission permission;
  final String title;
  final String why;
  final String actionLabel;
}

class _PermissionRow extends StatelessWidget {
  const _PermissionRow({
    required this.item,
    required this.status,
    required this.primary,
    required this.busy,
    required this.onAllow,
    required this.onOpenSettings,
  });

  final _PermissionSpec item;
  final PermissionStatus status;
  final Color primary;
  final bool busy;
  final VoidCallback onAllow;
  final VoidCallback onOpenSettings;

  bool get _ok => status.isGranted || status.isLimited;
  bool get _needsSettings =>
      status.isPermanentlyDenied || status.isRestricted;

  String get _hint {
    if (_ok) return 'Allowed on this device';
    if (_needsSettings) return 'Blocked — open Settings to allow';
    return '';
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          item.title,
          style: const TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          item.why,
          style: const TextStyle(
            height: 1.4,
            color: EmployeeColors.textMuted,
            fontSize: 14,
          ),
        ),
        if (_hint.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(
            _hint,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: _ok ? EmployeeColors.textBody : const Color(0xFFB45309),
            ),
          ),
        ],
        const SizedBox(height: 12),
        if (_ok)
          const SizedBox.shrink()
        else if (_needsSettings)
          OutlinedButton(
            onPressed: busy ? null : onOpenSettings,
            style: OutlinedButton.styleFrom(
              foregroundColor: primary,
              side: BorderSide(color: primary.withValues(alpha: 0.35)),
              minimumSize: const Size.fromHeight(44),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Text(
              'Open Settings',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
          )
        else
          FilledButton(
            onPressed: busy ? null : onAllow,
            style: FilledButton.styleFrom(
              backgroundColor: primary,
              minimumSize: const Size.fromHeight(44),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: Text(
              item.actionLabel,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
      ],
    );
  }
}
