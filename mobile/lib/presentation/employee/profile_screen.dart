import 'dart:convert';

import 'package:aroll_mobile/core/app_state.dart';
import 'package:aroll_mobile/core/di/injection.dart';
import 'package:aroll_mobile/core/utils/profile_image_errors.dart';
import 'package:aroll_mobile/domain/entities/employee_portal.dart';
import 'package:aroll_mobile/domain/repositories/employee_repository.dart';
import 'package:aroll_mobile/presentation/employee/employee_ui.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

class EmployeeProfileScreen extends StatefulWidget {
  const EmployeeProfileScreen({super.key});

  @override
  State<EmployeeProfileScreen> createState() => _EmployeeProfileScreenState();
}

class _EmployeeProfileScreenState extends State<EmployeeProfileScreen> {
  late Future<EmployeeProfile> _future;
  bool _uploading = false;

  @override
  void initState() {
    super.initState();
    _reloadProfile();
  }

  void _reloadProfile() {
    _future = sl<EmployeeRepository>().getProfile().then((profile) {
      sl<AppState>().updateEmployeeProfileImage(profile.profileImageUrl);
      return profile;
    });
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
      final updated = await sl<EmployeeRepository>().updateProfileImage(
        imageData,
      );
      if (!mounted) return;
      sl<AppState>().updateEmployeeProfileImage(updated.profileImageUrl);
      setState(() {
        _future = Future.value(updated);
      });
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
      final updated = await sl<EmployeeRepository>().removeProfileImage();
      if (!mounted) return;
      sl<AppState>().updateEmployeeProfileImage(null);
      setState(() {
        _future = Future.value(updated);
      });
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

  @override
  Widget build(BuildContext context) {
    final appState = sl<AppState>();

    return EmployeeScaffold(
      title: 'Profile',
      selectedIndex: 4,
      child: ListenableBuilder(
        listenable: appState,
        builder: (context, _) {
          return FutureBuilder<EmployeeProfile>(
            future: _future,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return loadingView();
              }
              if (snapshot.hasError) return errorView(snapshot.error);
              final profile = snapshot.data!;
              final avatarUrl = appState.resolveEmployeeAvatarUrl(
                profile.profileImageUrl,
              );

              return ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                children: [
                  Row(
                    children: [
                      Stack(
                        alignment: Alignment.bottomRight,
                        children: [
                          EmployeeAvatar(
                            imageUrl: avatarUrl,
                            name: profile.fullName,
                            size: 76,
                          ),
                          Material(
                            color: EmployeeColors.primaryDark,
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
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              profile.fullName,
                              style: Theme.of(context)
                                  .textTheme
                                  .titleLarge
                                  ?.copyWith(
                                    fontWeight: FontWeight.w700,
                                  ),
                            ),
                            Text(titleCase(profile.employmentType)),
                            if (avatarUrl != null) ...[
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
                    ],
                  ),
                  const SizedBox(height: 18),
                  _Section(
                    title: 'Personal Information',
                    children: [
                      EmployeeDetailField(
                        label: 'Name',
                        value: profile.fullName,
                      ),
                      EmployeeDetailField(
                        label: 'Username',
                        value: profile.username ?? 'Not available',
                      ),
                      const EmployeeDetailField(
                        label: 'Address',
                        value: 'Not set',
                      ),
                      EmployeeDetailField(
                        label: 'Phone Number',
                        value: profile.phone ?? 'Not set',
                      ),
                      const EmployeeDetailField(
                        label: 'Date of Birth',
                        value: 'Not set',
                      ),
                      EmployeeDetailField(
                        label: 'Position',
                        value: profile.position ?? 'Employee',
                      ),
                      EmployeeDetailField(
                        label: 'Employee Status',
                        value: titleCase(profile.status),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  _Section(
                    title: 'Business Information',
                    children: [
                      Row(
                        children: [
                          BusinessLogo(
                            logoUrl: profile.branding?.logoUrl,
                            height: 48,
                            width: 48,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              profile.businessName,
                              style: Theme.of(context)
                                  .textTheme
                                  .titleMedium
                                  ?.copyWith(
                                    fontWeight: FontWeight.w700,
                                  ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      EmployeeDetailField(
                        label: 'Assigned Business',
                        value: profile.businessName,
                      ),
                      EmployeeDetailField(
                        label: 'Business Code',
                        value: profile.businessCode,
                      ),
                      EmployeeDetailField(
                        label: 'Business Type',
                        value: profile.businessType ?? 'Not specified',
                      ),
                      EmployeeDetailField(
                        label: 'Owner',
                        value: profile.ownerName ?? 'Not available',
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  _Section(
                    title: 'Face Registration',
                    children: [
                      EmployeeDetailField(
                        label: 'Status',
                        value: profile.faceRegistered
                            ? 'Completed'
                            : titleCase(profile.faceRegistrationStatus),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  EmployeeOutlinedButton(
                    label: 'Sign Out',
                    onPressed: () => confirmEmployeeSignOut(context),
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return EmployeeCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          EmployeeSectionTitle(title),
          const SizedBox(height: 12),
          ...children,
        ],
      ),
    );
  }
}
