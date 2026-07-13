import 'dart:convert';

import 'package:aroll_mobile/core/di/injection.dart';
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
    _future = sl<EmployeeRepository>().getProfile();
  }

  Future<void> _pickProfileImage() async {
    final picked = await ImagePicker().pickImage(
      source: ImageSource.gallery,
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
      setState(() {
        _future = Future.value(updated);
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Profile picture updated.')),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Unable to update profile picture.')),
      );
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return EmployeeScaffold(
      title: 'Profile',
      selectedIndex: 4,
      child: FutureBuilder<EmployeeProfile>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return loadingView();
          }
          if (snapshot.hasError) return errorView(snapshot.error);
          final profile = snapshot.data!;

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            children: [
              Row(
                children: [
                  Stack(
                    alignment: Alignment.bottomRight,
                    children: [
                      EmployeeAvatar(
                        imageUrl: profile.profileImageUrl,
                        name: profile.fullName,
                        size: 76,
                      ),
                      Material(
                        color: EmployeeColors.primaryDark,
                        shape: const CircleBorder(),
                        child: InkWell(
                          customBorder: const CircleBorder(),
                          onTap: _uploading ? null : _pickProfileImage,
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
                          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                        ),
                        Text(titleCase(profile.employmentType)),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              _Section(
                title: 'Personal Information',
                children: [
                  EmployeeDetailField(label: 'Name', value: profile.fullName),
                  EmployeeDetailField(
                    label: 'Username',
                    value: profile.username ?? 'Not available',
                  ),
                  const EmployeeDetailField(label: 'Address', value: 'Not set'),
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
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
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
