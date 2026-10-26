import 'dart:convert';
import 'dart:typed_data';

import 'package:aroll_mobile/core/app_state.dart';
import 'package:aroll_mobile/core/theme/business_brand_theme.dart';
import 'package:aroll_mobile/core/di/injection.dart';
import 'package:aroll_mobile/core/utils/data_uri_image.dart';
import 'package:aroll_mobile/core/utils/profile_image_errors.dart';
import 'package:aroll_mobile/data/repositories/owner_repository.dart';
import 'package:aroll_mobile/domain/entities/user_session.dart';
import 'package:aroll_mobile/domain/repositories/auth_repository.dart';
import 'package:aroll_mobile/presentation/auth/aroll_splash_screen.dart';
import 'package:aroll_mobile/presentation/auth/sign_out_dialog.dart';
import 'package:aroll_mobile/presentation/owner/owner_info_display.dart';
import 'package:aroll_mobile/presentation/owner/owner_shell.dart';
import 'package:aroll_mobile/presentation/shared/app_ui.dart';
import 'package:aroll_mobile/presentation/shared/confirm_action_dialog.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

const _sheetRadius = 28.0;
const _menuCardBg = Color(0xFFF3F4F6);
const _logoutColor = Color(0xFFE57373);

class OwnerProfileScreen extends StatefulWidget {
  const OwnerProfileScreen({super.key, required this.session});

  final UserSession session;

  @override
  State<OwnerProfileScreen> createState() => _OwnerProfileScreenState();
}

class _OwnerProfileScreenState extends State<OwnerProfileScreen> {
  bool _uploading = false;
  late Future<_ProfileDetails> _detailsFuture;

  @override
  void initState() {
    super.initState();
    _refreshSession();
    _detailsFuture = _loadDetails();
  }

  Future<_ProfileDetails> _loadDetails() async {
    final repo = sl<OwnerRepository>();
    final results = await Future.wait([
      repo.accountSettings(),
      repo.businessSettings(),
      repo.payrollConfig(),
    ]);
    return _ProfileDetails(
      account: Map<String, dynamic>.from(results[0] as Map),
      business: Map<String, dynamic>.from(results[1] as Map),
      payroll: Map<String, dynamic>.from(results[2] as Map),
    );
  }

  Future<void> _refreshSession() async {
    final refreshed = await sl<AuthRepository>().restoreSession();
    if (refreshed != null && mounted) {
      sl<AppState>().setSession(
        refreshed,
        mustChange: sl<AppState>().mustChangePassword,
      );
    }
  }

  Future<void> _openPhotoActions() async {
    final hasImage =
        sl<AppState>().session?.branding?.ownerProfileImageUrl != null;
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Icon(
                Icons.photo_library_outlined,
                color: BrandColors.of(context).tonePrimary,
              ),
              title: const Text('Choose from gallery'),
              onTap: () => Navigator.pop(context, 'gallery'),
            ),
            ListTile(
              leading: Icon(
                Icons.photo_camera_outlined,
                color: BrandColors.of(context).tonePrimary,
              ),
              title: const Text('Take photo'),
              onTap: () => Navigator.pop(context, 'camera'),
            ),
            if (hasImage)
              ListTile(
                leading: const Icon(Icons.delete_outline_rounded),
                title: const Text('Remove profile picture'),
                onTap: () => Navigator.pop(context, 'remove'),
              ),
          ],
        ),
      ),
    );
    if (!mounted || action == null) return;
    if (action == 'remove') {
      await _confirmRemoveProfileImage();
      return;
    }
    await _pickProfileImage(
      action == 'camera' ? ImageSource.camera : ImageSource.gallery,
    );
  }

  Future<void> _pickProfileImage(ImageSource source) async {
    final picked = await ImagePicker().pickImage(
      source: source,
      maxWidth: 900,
      imageQuality: 78,
    );
    if (picked == null) return;

    setState(() => _uploading = true);
    try {
      final bytes = await picked.readAsBytes();
      final mimeType = picked.mimeType ?? 'image/jpeg';
      final imageData = 'data:$mimeType;base64,${base64Encode(bytes)}';
      final imageUrl = await sl<OwnerRepository>().updateProfileImage(imageData);
      sl<AppState>().updateOwnerProfileImage(imageUrl);
      await _refreshSession();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Profile picture updated.')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            profileImageErrorMessage(error, action: 'update'),
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _confirmRemoveProfileImage() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => const ConfirmActionDialog(
        icon: Icons.person_remove_rounded,
        title: 'Remove profile picture?',
        message: 'Your profile picture will be removed from all devices.',
        confirmLabel: 'Remove',
        iconColor: AppColors.danger,
        iconBackground: Color(0xFFFEE2E2),
        confirmColor: Color(0xFFB91C1C),
      ),
    );
    if (confirmed != true) return;

    setState(() => _uploading = true);
    try {
      await sl<OwnerRepository>().removeProfileImage();
      sl<AppState>().updateOwnerProfileImage(null);
      await _refreshSession();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Profile picture removed.')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            profileImageErrorMessage(error, action: 'remove'),
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _confirmLogout(BuildContext context) => confirmSignOut(context);

  @override
  Widget build(BuildContext context) {
    final appState = sl<AppState>();

    return ListenableBuilder(
      listenable: appState,
      builder: (context, _) {
        final session = appState.session ?? widget.session;
        final brand = BrandColors.of(context);
        final headerBg = brand.saved ? brand.toneSidebar : kAuthNavyBackground;
        final headerControl =
            brand.saved ? brand.toneButton : const Color(0xFF1E3A5F);
        final avatarBg =
            brand.saved ? brand.toneSecondary : const Color(0xFF284B73);
        final profileImageUrl = session.branding?.ownerProfileImageUrl;
        final imageBytes = dataUriBytes(profileImageUrl);

        return OwnerShell(
          selectedIndex: 2,
          showAppBar: false,
          title: 'Profile',
          backgroundColor: headerBg,
          child: ColoredBox(
            color: headerBg,
            child: SafeArea(
              bottom: false,
              child: FutureBuilder<_ProfileDetails>(
                future: _detailsFuture,
                builder: (context, snapshot) {
                  final details = snapshot.data;
                  final account = details?.account ?? const {};
                  final business = details?.business ?? const {};
                  final payroll = details?.payroll ?? const {};

                  final ownerName = _text(
                        account['owner_name'] ?? business['owner_name'],
                      ) ??
                      session.fullName;
                  final email = _text(
                        account['email'] ?? business['owner_email'],
                      ) ??
                      session.email ??
                      '';
                  final businessName = _text(business['business_name']) ??
                      session.businessName;
                  final businessType = _text(business['business_type']);
                  final businessCode = _text(business['business_code']);
                  final address =
                      _text(business['address'] ?? account['address']);
                  final payrollFrequency =
                      ownerPayFrequencyLabel(payroll['pay_period_type']);
                  final businessStatus =
                      _text(business['application_status']) == null
                          ? null
                          : ownerStatusLabel(business['application_status']);

                  return Column(
                    children: [
                      _DarkHeader(
                        headerControl: headerControl,
                        avatarColor: avatarBg,
                        imageBytes: imageBytes,
                        ownerName: ownerName,
                        email: email,
                        uploading: _uploading,
                        onBack: () => appNavigateBack(
                          context,
                          fallbackRoute: '/owner/home',
                        ),
                        onEditPhoto:
                            _uploading ? null : _openPhotoActions,
                      ),
                      Expanded(
                        child: Container(
                          width: double.infinity,
                          decoration: const BoxDecoration(
                            color: AppColors.white,
                            borderRadius: BorderRadius.vertical(
                              top: Radius.circular(_sheetRadius),
                            ),
                          ),
                          child: snapshot.connectionState ==
                                  ConnectionState.waiting
                              ? const Center(
                                  child: CircularProgressIndicator(),
                                )
                              : snapshot.hasError
                                  ? Center(
                                      child: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Text(
                                            'Unable to load profile details.',
                                            style: appMutedStyle(),
                                          ),
                                          TextButton(
                                            onPressed: () {
                                              setState(() {
                                                _detailsFuture =
                                                    _loadDetails();
                                              });
                                            },
                                            child: const Text('Retry'),
                                          ),
                                        ],
                                      ),
                                    )
                                  : SingleChildScrollView(
                                      physics:
                                          const ClampingScrollPhysics(),
                                      padding: const EdgeInsets.fromLTRB(
                                        16,
                                        14,
                                        16,
                                        16,
                                      ),
                                      child: Column(
                                        children: [
                                          _DisplayedInfoCard(
                                            title: 'Business Information',
                                            rows: [
                                              (
                                                'Business Name',
                                                businessName
                                              ),
                                              if (businessType != null)
                                                (
                                                  'Business Type',
                                                  businessType
                                                ),
                                              if (businessCode != null)
                                                (
                                                  'Business Code',
                                                  businessCode
                                                ),
                                              if (address != null)
                                                ('Address', address),
                                              (
                                                'Payroll Frequency',
                                                payrollFrequency,
                                              ),
                                              if (businessStatus != null)
                                                (
                                                  'Business Status',
                                                  businessStatus,
                                                ),
                                            ],
                                          ),
                                          const SizedBox(height: 10),
                                          _MenuCard(
                                            items: [
                                              _MenuItemData(
                                                icon:
                                                    Icons.badge_outlined,
                                                label:
                                                    'Account Information',
                                                onTap: () => context.push(
                                                  '/owner/settings/account',
                                                ),
                                              ),
                                              _MenuItemData(
                                                icon: Icons.lock_outline_rounded,
                                                label: 'Change Password',
                                                onTap: () => context.push(
                                                  '/owner/profile/change-password',
                                                ),
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 10),
                                          _MenuCard(
                                            items: [
                                              _MenuItemData(
                                                icon: Icons
                                                    .settings_outlined,
                                                label: 'Settings',
                                                onTap: () => context.push(
                                                  '/owner/settings',
                                                ),
                                              ),
                                              _MenuItemData(
                                                icon: Icons
                                                    .support_agent_outlined,
                                                label: 'Help',
                                                onTap: () => context.push(
                                                  '/owner/settings/help',
                                                ),
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 10),
                                          _MenuCard(
                                            items: [
                                              _MenuItemData(
                                                icon: Icons
                                                    .logout_rounded,
                                                label: 'Log Out',
                                                destructive: true,
                                                onTap: () =>
                                                    _confirmLogout(
                                                  context,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        );
      },
    );
  }
}

class _ProfileDetails {
  const _ProfileDetails({
    required this.account,
    required this.business,
    required this.payroll,
  });

  final Map<String, dynamic> account;
  final Map<String, dynamic> business;
  final Map<String, dynamic> payroll;
}

String? _text(Object? value) {
  if (value == null) return null;
  final text = '$value'.trim();
  if (text.isEmpty || text == 'null') return null;
  return text;
}

class _DarkHeader extends StatelessWidget {
  const _DarkHeader({
    required this.headerControl,
    required this.avatarColor,
    required this.imageBytes,
    required this.ownerName,
    required this.email,
    required this.uploading,
    required this.onBack,
    required this.onEditPhoto,
  });

  final Color headerControl;
  final Color avatarColor;
  final Uint8List? imageBytes;
  final String ownerName;
  final String email;
  final bool uploading;
  final VoidCallback onBack;
  final VoidCallback? onEditPhoto;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 2, 16, 16),
      child: Column(
        children: [
          SizedBox(
            height: 40,
            child: Row(
              children: [
                _CircleIconButton(
                  color: headerControl,
                  icon: Icons.chevron_left_rounded,
                  onTap: onBack,
                ),
                const Expanded(
                  child: Text(
                    'Profile',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(width: 40),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Stack(
            alignment: Alignment.bottomRight,
            children: [
              CircleAvatar(
                radius: 40,
                backgroundColor: avatarColor,
                backgroundImage:
                    imageBytes != null ? MemoryImage(imageBytes!) : null,
                child: imageBytes == null
                    ? const Icon(
                        Icons.person_rounded,
                        size: 40,
                        color: Colors.white70,
                      )
                    : null,
              ),
              Material(
                color: Colors.white,
                shape: const CircleBorder(),
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: onEditPhoto,
                  child: Padding(
                    padding: const EdgeInsets.all(6),
                    child: uploading
                        ? const SizedBox(
                            height: 14,
                            width: 14,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(
                            Icons.photo_camera_outlined,
                            size: 14,
                            color: Color(0xFF333333),
                          ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            ownerName,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.w700,
              height: 1.15,
            ),
          ),
          if (email.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              email,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.72),
                fontSize: 13,
                fontWeight: FontWeight.w400,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _CircleIconButton extends StatelessWidget {
  const _CircleIconButton({
    required this.color,
    required this.icon,
    required this.onTap,
  });

  final Color color;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: color,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox(
          width: 40,
          height: 40,
          child: Icon(icon, color: Colors.white, size: 24),
        ),
      ),
    );
  }
}

class _DisplayedInfoCard extends StatelessWidget {
  const _DisplayedInfoCard({
    required this.title,
    required this.rows,
  });

  final String title;
  final List<(String, String)> rows;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 6),
      decoration: BoxDecoration(
        color: _menuCardBg,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 6),
          for (var i = 0; i < rows.length; i++) ...[
            if (i > 0)
              const Divider(height: 1, color: Color(0xFFE5E7EB)),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 7),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      rows[i].$1,
                      style: appMutedStyle().copyWith(fontSize: 12),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Flexible(
                    child: Text(
                      rows[i].$2,
                      textAlign: TextAlign.end,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _MenuItemData {
  const _MenuItemData({
    required this.icon,
    required this.label,
    required this.onTap,
    this.subtitle,
    this.destructive = false,
  });

  final IconData icon;
  final String label;
  final String? subtitle;
  final VoidCallback onTap;
  final bool destructive;
}

class _MenuCard extends StatelessWidget {
  const _MenuCard({required this.items});

  final List<_MenuItemData> items;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: _menuCardBg,
        borderRadius: BorderRadius.circular(16),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (var i = 0; i < items.length; i++) ...[
            _MenuRow(item: items[i]),
            if (i < items.length - 1)
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 14),
                child: Divider(height: 1, color: Color(0xFFE5E7EB)),
              ),
          ],
        ],
      ),
    );
  }
}

class _MenuRow extends StatelessWidget {
  const _MenuRow({required this.item});

  final _MenuItemData item;

  @override
  Widget build(BuildContext context) {
    final color = item.destructive ? _logoutColor : AppColors.textPrimary;
    final iconColor = item.destructive ? _logoutColor : const Color(0xFF4B5563);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: item.onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: item.destructive
                      ? _logoutColor.withValues(alpha: 0.12)
                      : Colors.white,
                  shape: BoxShape.circle,
                ),
                child: Icon(item.icon, size: 18, color: iconColor),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.label,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: color,
                      ),
                    ),
                    if (item.subtitle != null && item.subtitle!.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        item.subtitle!,
                        style: appMutedStyle().copyWith(fontSize: 12),
                      ),
                    ],
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                size: 20,
                color: item.destructive
                    ? _logoutColor.withValues(alpha: 0.8)
                    : AppColors.textMuted,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
