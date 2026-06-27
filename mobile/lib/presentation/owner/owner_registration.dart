import 'package:aroll_mobile/core/di/injection.dart';
import 'package:aroll_mobile/data/repositories/owner_repository.dart';
import 'package:aroll_mobile/presentation/auth/owner_auth_ui.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

class OwnerRegistrationScreen extends StatefulWidget {
  const OwnerRegistrationScreen({super.key});

  @override
  State<OwnerRegistrationScreen> createState() =>
      _OwnerRegistrationScreenState();
}

class _OwnerRegistrationScreenState extends State<OwnerRegistrationScreen> {
  final _business = TextEditingController();
  final _owner = TextEditingController();
  final _email = TextEditingController();
  final _phone = TextEditingController();
  final _address = TextEditingController();
  final _type = TextEditingController();
  final _picker = ImagePicker();
  final Map<String, XFile> _documents = {};
  String? _registrationId;
  bool _loading = false;

  static const _required = {
    'business_permit': 'Business Permit',
    'valid_id': 'Valid ID',
    'dti_sec': 'DTI / SEC Registration',
    'bir_cor': 'BIR Certificate of Registration',
  };

  @override
  void dispose() {
    for (final controller in [
      _business,
      _owner,
      _email,
      _phone,
      _address,
      _type,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _pick(String type) async {
    final file = await _picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 90,
    );
    if (file != null) setState(() => _documents[type] = file);
  }

  Future<void> _submit() async {
    if (_loading) return;
    if ([
      _business,
      _owner,
      _email,
      _address,
    ].any((controller) => controller.text.trim().isEmpty)) {
      _message('Complete all required business details.');
      return;
    }
    if (_documents.length != _required.length) {
      _message('Upload all four required documents.');
      return;
    }
    setState(() => _loading = true);
    try {
      final repo = sl<OwnerRepository>();
      final email = _email.text.trim();
      final existing = await _lookupExistingRegistration(repo, email);

      if (existing?.status == 'pending') {
        if (!mounted) return;
        _message('An application is already pending review.');
        context.go('/track-registration?email=${Uri.encodeComponent(email)}');
        return;
      }

      if (existing?.status == 'rejected') {
        _message(
          'A rejected application exists for this email. Please contact support or use the resubmission flow.',
        );
        return;
      }

      final registrationId = existing?.status == 'draft'
          ? existing!.id
          : await _createRegistration(repo, email);

      for (final entry in _documents.entries) {
        await repo.uploadRegistrationDocument(
          registrationId,
          entry.key,
          entry.value,
        );
      }
      await repo.submitRegistration(registrationId);
      if (!mounted) return;
      setState(() => _registrationId = registrationId);
      _message('Registration submitted successfully.');
      context.go('/track-registration?email=${Uri.encodeComponent(email)}');
    } on DioException catch (error) {
      _message(_detail(error) ?? 'Registration could not be submitted.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<String> _createRegistration(
    OwnerRepository repo,
    String email,
  ) async {
    final registration = await repo.createRegistration(
      businessName: _business.text.trim(),
      ownerName: _owner.text.trim(),
      email: email,
      phone: _phone.text.trim(),
      address: _address.text.trim(),
      businessType: _type.text.trim(),
    );
    return '${registration['id']}';
  }

  Future<_ExistingRegistration?> _lookupExistingRegistration(
    OwnerRepository repo,
    String email,
  ) async {
    try {
      final existing = await repo.registrationByEmail(email);
      return _ExistingRegistration(
        id: '${existing['id']}',
        status:
            '${existing['application_status'] ?? existing['status'] ?? ''}',
      );
    } on DioException catch (error) {
      if (error.response?.statusCode == 404) {
        return null;
      }
      rethrow;
    }
  }

  void _message(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return OwnerAuthScaffold(
      badgeLabel: 'Owner portal',
      title: 'Register Business',
      subtitle:
          'Submit your business details and upload the required documents.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          OwnerAuthCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const OwnerAuthSectionTitle(
                  title: 'Business details',
                  subtitle: 'Fields marked with * are required.',
                ),
                OwnerAuthField(
                  controller: _business,
                  label: 'Business Name *',
                  hintText: 'Enter business name',
                  prefixIcon: Icons.business_outlined,
                  textInputAction: TextInputAction.next,
                ),
                OwnerAuthField(
                  controller: _owner,
                  label: 'Owner Name *',
                  hintText: 'Enter owner full name',
                  prefixIcon: Icons.person_outline_rounded,
                  textInputAction: TextInputAction.next,
                ),
                OwnerAuthField(
                  controller: _email,
                  label: 'Owner Email *',
                  hintText: 'owner@business.com',
                  prefixIcon: Icons.mail_outline_rounded,
                  keyboardType: TextInputType.emailAddress,
                  textInputAction: TextInputAction.next,
                ),
                OwnerAuthField(
                  controller: _phone,
                  label: 'Phone Number',
                  hintText: 'Optional contact number',
                  prefixIcon: Icons.phone_outlined,
                  keyboardType: TextInputType.phone,
                  textInputAction: TextInputAction.next,
                ),
                OwnerAuthField(
                  controller: _address,
                  label: 'Business Address *',
                  hintText: 'Street, city, province',
                  prefixIcon: Icons.location_on_outlined,
                  maxLines: 2,
                  textInputAction: TextInputAction.next,
                ),
                OwnerAuthField(
                  controller: _type,
                  label: 'Business Type',
                  hintText: 'Restaurant, cafe, retail, etc.',
                  prefixIcon: Icons.category_outlined,
                  textInputAction: TextInputAction.done,
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          OwnerAuthCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const OwnerAuthSectionTitle(
                  title: 'Required documents',
                  subtitle: 'Select a clear JPG or PNG image for each item.',
                ),
                for (final entry in _required.entries)
                  OwnerAuthDocumentTile(
                    title: entry.value,
                    subtitle:
                        _documents[entry.key]?.name ?? 'No image selected',
                    uploaded: _documents.containsKey(entry.key),
                    enabled: !_loading,
                    onTap: () => _pick(entry.key),
                  ),
                const SizedBox(height: 8),
                OwnerAuthPrimaryButton(
                  label: _loading ? 'Submitting…' : 'Submit Registration',
                  loading: _loading,
                  icon: Icons.send_rounded,
                  onPressed: _loading ? null : _submit,
                ),
                if (_registrationId != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: Text(
                      'Application reference: $_registrationId',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 11,
                        color: OwnerAuthColors.textMuted,
                      ),
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

class TrackRegistrationScreen extends StatefulWidget {
  const TrackRegistrationScreen({super.key, this.initialEmail});

  final String? initialEmail;

  @override
  State<TrackRegistrationScreen> createState() =>
      _TrackRegistrationScreenState();
}

class _TrackRegistrationScreenState extends State<TrackRegistrationScreen> {
  late final TextEditingController _email =
      TextEditingController(text: widget.initialEmail ?? '');
  Map<String, dynamic>? _registration;
  bool _loading = false;

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  Future<void> _track() async {
    if (_email.text.trim().isEmpty || _loading) return;
    setState(() => _loading = true);
    try {
      final result =
          await sl<OwnerRepository>().registrationByEmail(_email.text);
      if (mounted) setState(() => _registration = result);
    } on DioException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_detail(error) ?? 'Registration not found.')),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = _registration;
    final status = '${data?['application_status'] ?? data?['status'] ?? ''}';

    return OwnerAuthScaffold(
      badgeLabel: 'Owner portal',
      title: 'Registration Status',
      subtitle: 'Check an existing application using your owner email.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          OwnerAuthCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                OwnerAuthField(
                  controller: _email,
                  label: 'Email Address',
                  hintText: 'Enter the email used during registration',
                  prefixIcon: Icons.search_rounded,
                  keyboardType: TextInputType.emailAddress,
                  textInputAction: TextInputAction.search,
                  onSubmitted: (_) => _track(),
                ),
                OwnerAuthPrimaryButton(
                  label: _loading ? 'Checking…' : 'Check Status',
                  loading: _loading,
                  onPressed: _loading ? null : _track,
                ),
              ],
            ),
          ),
          if (data != null) ...[
            const SizedBox(height: 14),
            OwnerAuthStatusCard(
              title: '${data['business_name'] ?? 'Business'}',
              rows: [
                ('Application status', _formatStatus(status)),
                ('Owner', '${data['owner_name'] ?? ''}'),
                ('Submitted', '${data['submitted_at'] ?? 'Draft'}'),
                (
                  'Documents',
                  '${(data['documents'] as List<dynamic>? ?? const []).length}/4',
                ),
                if (data['rejection_reason'] != null)
                  ('Review note', '${data['rejection_reason']}'),
              ],
            ),
          ],
          OwnerAuthTextLink(
            label: 'Start a new registration',
            onPressed: () => context.go('/register-business'),
          ),
        ],
      ),
    );
  }
}

String _formatStatus(String status) {
  if (status.isEmpty) return 'Unknown';
  return status
      .replaceAll('_', ' ')
      .split(' ')
      .where((part) => part.isNotEmpty)
      .map((part) => '${part[0].toUpperCase()}${part.substring(1)}')
      .join(' ');
}

String? _detail(DioException error) {
  final data = error.response?.data;
  if (data is Map<String, dynamic>) {
    final detail = data['detail'];
    if (detail is String) return detail;
    if (detail is Map) {
      return detail['message']?.toString();
    }
    if (detail is List && detail.isNotEmpty) {
      final first = detail.first;
      if (first is Map) {
        return first['msg']?.toString();
      }
    }
  }
  return error.message;
}

class _ExistingRegistration {
  const _ExistingRegistration({
    required this.id,
    required this.status,
  });

  final String id;
  final String status;
}
