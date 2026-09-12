import 'package:aroll_mobile/core/app_state.dart';
import 'package:aroll_mobile/core/di/injection.dart';
import 'package:aroll_mobile/core/legal/consent_sync.dart';
import 'package:aroll_mobile/core/router/app_router.dart';
import 'package:aroll_mobile/domain/entities/legal_consent.dart';
import 'package:aroll_mobile/domain/repositories/employee_repository.dart';
import 'package:aroll_mobile/presentation/employee/employee_ui.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class EmployeeLegalConsentScreen extends StatefulWidget {
  const EmployeeLegalConsentScreen({super.key});

  @override
  State<EmployeeLegalConsentScreen> createState() =>
      _EmployeeLegalConsentScreenState();
}

class _EmployeeLegalConsentScreenState extends State<EmployeeLegalConsentScreen> {
  PublicLegalPage? _page;
  String? _error;
  bool _loading = true;
  bool _submitting = false;
  bool _adult = false;
  bool _readTerms = false;
  bool _readPrivacy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final code = sl<AppState>().session?.businessCode;
    if (code == null || code.isEmpty) {
      setState(() {
        _loading = false;
        _error = 'No workplace is linked to this account.';
      });
      return;
    }
    try {
      final page = await sl<EmployeeRepository>().getPublicLegalPage(code);
      if (!mounted) return;
      setState(() {
        _page = page;
        _loading = false;
        _error = null;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Could not load your workplace legal page.';
      });
    }
  }

  bool get _canAgree {
    final page = _page;
    if (page == null || _submitting) return false;
    return page.terms.published &&
        page.privacy.published &&
        _readTerms &&
        _readPrivacy &&
        _adult;
  }

  Future<void> _agree() async {
    final page = _page;
    if (page == null || !_canAgree) return;
    setState(() => _submitting = true);
    try {
      final status = await sl<EmployeeRepository>().acceptConsent(
        types: const ['terms', 'privacy'],
        versions: {
          'terms': page.terms.version ?? '',
          'privacy': page.privacy.version ?? '',
        },
        adultAcknowledged: true,
      );
      final appState = sl<AppState>();
      appState.setConsentStatus(
        legalSatisfied: status.legalSatisfied,
        biometricSatisfied: status.biometricSatisfied,
      );
      if (!mounted) return;
      context.go(resolveAuthenticatedRoute(appState));
    } catch (_) {
      if (!mounted) return;
      setState(() => _submitting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Could not record consent. Ask your employer if the legal page is published.',
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: EmployeeColors.scaffold,
      appBar: AppBar(
        backgroundColor: EmployeeColors.scaffold,
        elevation: 0,
        title: const Text(
          'Workplace legal documents',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? Center(child: Text(_error!))
                : _buildBody(),
      ),
    );
  }

  Widget _buildBody() {
    final page = _page!;
    final unpublished = !page.terms.published || !page.privacy.published;
    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
            children: [
              Text(
                page.businessName,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Review the Terms and Privacy Policy for this workplace, then record your acceptance.',
                style: TextStyle(
                  color: EmployeeColors.textMuted,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 16),
              _LegalSectionCard(section: page.terms),
              const SizedBox(height: 12),
              _LegalSectionCard(section: page.privacy),
              if (unpublished) ...[
                const SizedBox(height: 12),
                const Text(
                  'These documents are not published yet. Contact your workplace before using face enrollment or live attendance.',
                  style: TextStyle(color: EmployeeColors.danger, height: 1.4),
                ),
              ],
              const SizedBox(height: 8),
              CheckboxListTile(
                value: _readTerms,
                onChanged: unpublished
                    ? null
                    : (value) => setState(() => _readTerms = value ?? false),
                controlAffinity: ListTileControlAffinity.leading,
                contentPadding: EdgeInsets.zero,
                title: const Text('I have read the Terms and Conditions'),
              ),
              CheckboxListTile(
                value: _readPrivacy,
                onChanged: unpublished
                    ? null
                    : (value) => setState(() => _readPrivacy = value ?? false),
                controlAffinity: ListTileControlAffinity.leading,
                contentPadding: EdgeInsets.zero,
                title: const Text('I have read the Privacy Policy'),
              ),
              CheckboxListTile(
                value: _adult,
                onChanged: unpublished
                    ? null
                    : (value) => setState(() => _adult = value ?? false),
                controlAffinity: ListTileControlAffinity.leading,
                contentPadding: EdgeInsets.zero,
                title: const Text('I confirm I am 18 years of age or older'),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          child: SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton(
              onPressed: _canAgree ? _agree : null,
              child: _submitting
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('I agree'),
            ),
          ),
        ),
      ],
    );
  }
}

class BiometricConsentScreen extends StatefulWidget {
  const BiometricConsentScreen({super.key});

  @override
  State<BiometricConsentScreen> createState() => _BiometricConsentScreenState();
}

class _BiometricConsentScreenState extends State<BiometricConsentScreen> {
  PublicLegalPage? _page;
  String? _error;
  bool _loading = true;
  bool _submitting = false;
  bool _agreed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final code = sl<AppState>().session?.businessCode;
    if (code == null || code.isEmpty) {
      setState(() {
        _loading = false;
        _error = 'No workplace is linked to this account.';
      });
      return;
    }
    try {
      final page = await sl<EmployeeRepository>().getPublicLegalPage(code);
      if (!mounted) return;
      setState(() {
        _page = page;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Could not load biometric consent.';
      });
    }
  }

  Future<void> _agree() async {
    final page = _page;
    if (page == null || !_agreed || !page.biometric.published) return;
    setState(() => _submitting = true);
    try {
      final status = await sl<EmployeeRepository>().acceptConsent(
        types: const ['biometric'],
        versions: {'biometric': page.biometric.version ?? ''},
        adultAcknowledged: true,
      );
      final appState = sl<AppState>();
      appState.setConsentStatus(
        legalSatisfied: status.legalSatisfied,
        biometricSatisfied: status.biometricSatisfied,
      );
      if (!mounted) return;
      context.go(resolveAuthenticatedRoute(appState));
    } catch (_) {
      if (!mounted) return;
      setState(() => _submitting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not record biometric consent.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: EmployeeColors.scaffold,
      appBar: AppBar(
        backgroundColor: EmployeeColors.scaffold,
        elevation: 0,
        title: const Text(
          'Biometric consent',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? Center(child: Text(_error!))
                : _buildBody(),
      ),
    );
  }

  Widget _buildBody() {
    final section = _page!.biometric;
    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
            children: [
              const Text(
                'Face enrollment and live Time In / Time Out require a separate biometric consent from Terms and Privacy.',
                style: TextStyle(color: EmployeeColors.textMuted, height: 1.4),
              ),
              const SizedBox(height: 16),
              _LegalSectionCard(section: section),
              if (!section.published)
                const Padding(
                  padding: EdgeInsets.only(top: 12),
                  child: Text(
                    'Biometric consent is not published yet.',
                    style: TextStyle(color: EmployeeColors.danger),
                  ),
                ),
              CheckboxListTile(
                value: _agreed,
                onChanged: !section.published
                    ? null
                    : (value) => setState(() => _agreed = value ?? false),
                controlAffinity: ListTileControlAffinity.leading,
                contentPadding: EdgeInsets.zero,
                title: const Text(
                  'I consent to face enrollment and face-based attendance',
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          child: SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton(
              onPressed: _agreed && section.published && !_submitting
                  ? _agree
                  : null,
              child: _submitting
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('I agree'),
            ),
          ),
        ),
      ],
    );
  }
}

class WorkplaceLegalPageScreen extends StatefulWidget {
  const WorkplaceLegalPageScreen({super.key});

  @override
  State<WorkplaceLegalPageScreen> createState() =>
      _WorkplaceLegalPageScreenState();
}

class _WorkplaceLegalPageScreenState extends State<WorkplaceLegalPageScreen> {
  PublicLegalPage? _page;
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final code = sl<AppState>().session?.businessCode;
    if (code == null || code.isEmpty) {
      setState(() {
        _loading = false;
        _error = 'No workplace is linked to this account.';
      });
      return;
    }
    try {
      final page = await sl<EmployeeRepository>().getPublicLegalPage(code);
      if (!mounted) return;
      setState(() {
        _page = page;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Could not load the workplace legal page.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: EmployeeColors.scaffold,
      appBar: AppBar(
        backgroundColor: EmployeeColors.scaffold,
        elevation: 0,
        title: const Text(
          'Terms & Privacy',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!))
              : ListView(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                  children: [
                    _LegalSectionCard(section: _page!.terms),
                    const SizedBox(height: 12),
                    _LegalSectionCard(section: _page!.privacy),
                    const SizedBox(height: 12),
                    _LegalSectionCard(section: _page!.biometric),
                  ],
                ),
    );
  }
}

class _LegalSectionCard extends StatelessWidget {
  const _LegalSectionCard({required this.section});

  final LegalSection section;

  @override
  Widget build(BuildContext context) {
    return EmployeeCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            section.title,
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
          ),
          if (section.version != null) ...[
            const SizedBox(height: 4),
            Text(
              'Version ${section.version}${section.contentSource == "business_custom" ? " · Custom workplace content" : " · Aroll+ default"}',
              style: const TextStyle(
                color: EmployeeColors.textMuted,
                fontSize: 12,
              ),
            ),
          ],
          const SizedBox(height: 10),
          Text(
            section.published
                ? (section.content ?? '')
                : section.contentSource == 'admin_default'
                    ? '${section.title} has not been published yet.'
                    : '${section.title} has not been published for this workplace yet.',
            style: TextStyle(
              height: 1.45,
              color: section.published
                  ? EmployeeColors.textBody
                  : EmployeeColors.textMuted,
            ),
          ),
        ],
      ),
    );
  }
}

/// Kept so restore/login can refresh gates after password change.
Future<void> refreshConsentThenGo(BuildContext context) async {
  final appState = sl<AppState>();
  await syncEmployeeConsentGate(appState, sl<EmployeeRepository>());
  if (!context.mounted) return;
  context.go(resolveAuthenticatedRoute(appState));
}
