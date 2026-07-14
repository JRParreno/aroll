import 'dart:convert';

import 'package:aroll_mobile/core/app_state.dart';
import 'package:aroll_mobile/core/di/injection.dart';
import 'package:aroll_mobile/core/utils/data_uri_image.dart';
import 'package:aroll_mobile/core/utils/profile_image_errors.dart';
import 'package:aroll_mobile/data/repositories/owner_repository.dart';
import 'package:aroll_mobile/domain/entities/user_session.dart';
import 'package:aroll_mobile/domain/repositories/auth_repository.dart';
import 'package:aroll_mobile/presentation/auth/sign_out_dialog.dart';
import 'package:aroll_mobile/presentation/owner/owner_shell.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

class OwnerProfileScreen extends StatefulWidget {
  const OwnerProfileScreen({super.key, required this.session});

  final UserSession session;

  @override
  State<OwnerProfileScreen> createState() => _OwnerProfileScreenState();
}

class _OwnerProfileScreenState extends State<OwnerProfileScreen> {
  bool _uploading = false;

  @override
  void initState() {
    super.initState();
    _refreshSession();
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

  Future<void> _chooseImageSource() async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Choose from gallery'),
              onTap: () => Navigator.pop(context, ImageSource.gallery),
            ),
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Take photo'),
              onTap: () => Navigator.pop(context, ImageSource.camera),
            ),
          ],
        ),
      ),
    );
    if (source == null) return;
    await _pickProfileImage(source);
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
      builder: (context) => AlertDialog(
        title: const Text('Remove profile picture?'),
        content: const Text(
          'Your profile picture will be removed from all devices.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Remove'),
          ),
        ],
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
        final profileImageUrl = session.branding?.ownerProfileImageUrl;
        final imageBytes = dataUriBytes(profileImageUrl);

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
                    Stack(
                      alignment: Alignment.bottomRight,
                      children: [
                        CircleAvatar(
                          radius: 38,
                          backgroundColor: const Color(0xFFE7EEF5),
                          backgroundImage: imageBytes != null
                              ? MemoryImage(imageBytes)
                              : null,
                          child: imageBytes == null
                              ? const Icon(Icons.person_rounded, size: 40)
                              : null,
                        ),
                        Material(
                          color: const Color(0xFF1E466E),
                          shape: const CircleBorder(),
                          child: InkWell(
                            customBorder: const CircleBorder(),
                            onTap: _uploading ? null : _chooseImageSource,
                            child: Padding(
                              padding: const EdgeInsets.all(7),
                              child: _uploading
                                  ? const SizedBox(
                                      height: 15,
                                      width: 15,
                                      child: CircularProgressIndicator(
                                        color: Colors.white,
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Icon(
                                      Icons.camera_alt_rounded,
                                      color: Colors.white,
                                      size: 15,
                                    ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      session.fullName,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                    Text(session.email ?? ''),
                    const SizedBox(height: 4),
                    Text(session.businessName),
                    if (profileImageUrl != null) ...[
                      const SizedBox(height: 8),
                      TextButton(
                        onPressed:
                            _uploading ? null : _confirmRemoveProfileImage,
                        child: const Text('Remove profile picture'),
                      ),
                    ],
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
                subtitle: 'Set workplace location on the map and geofence.',
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
                onPressed: () => _confirmLogout(context),
                icon: const Icon(Icons.logout_rounded),
                label: const Text('Log Out'),
              ),
            ],
          ),
        );
      },
    );
  }
}
