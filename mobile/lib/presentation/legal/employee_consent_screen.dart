import 'package:aroll_mobile/core/app_state.dart';
import 'package:aroll_mobile/core/di/injection.dart';
import 'package:aroll_mobile/core/router/auth_redirect.dart';
import 'package:aroll_mobile/domain/entities/legal_consent.dart';
import 'package:aroll_mobile/domain/repositories/employee_repository.dart';
import 'package:aroll_mobile/presentation/shared/app_ui.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

class EmployeeConsentScreen extends StatefulWidget {
  const EmployeeConsentScreen({super.key});

  @override
  State<EmployeeConsentScreen> createState() => _EmployeeConsentScreenState();
}

class _EmployeeConsentScreenState extends State<EmployeeConsentScreen> {
  LegalConsentStatus? _status;
  String? _error;
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final status = await sl<EmployeeRepository>().getLegalConsent();
      if (!mounted) return;
      if (status.accepted) {
        sl<AppState>().setLegalConsentAccepted(
          accepted: true,
          legalConsentUrl: status.legalConsentUrl,
          legalConsentPageUrl: status.legalConsentPageUrl,
        );
        context.go(resolveAuthenticatedRoute(sl<AppState>()));
        return;
      }
      setState(() {
        _status = status;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error =
            'We couldn’t load your workplace consent page. Please try again.';
      });
    }
  }

  Future<void> _openWebpage() async {
    final status = _status;
    if (status == null) return;
    final raw = status.legalConsentPageUrl;
    if (raw == null || raw.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Consent webpage is not available yet.')),
      );
      return;
    }
    final uri = Uri.tryParse(raw);
    if (uri == null) return;
    final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!opened && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Unable to open the consent webpage.')),
      );
    }
  }

  Future<void> _agree() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      final status = await sl<EmployeeRepository>().acceptLegalConsent();
      sl<AppState>().setLegalConsentAccepted(
        accepted: true,
        legalConsentUrl: status.legalConsentUrl,
        legalConsentPageUrl: status.legalConsentPageUrl,
      );
      if (!mounted) return;
      context.go(resolveAuthenticatedRoute(sl<AppState>()));
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('We couldn’t save your agreement. Please try again.'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final status = _status;
    return Scaffold(
      backgroundColor: AppColors.scaffold,
      appBar: AppBar(
        backgroundColor: AppColors.white,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
        automaticallyImplyLeading: false,
        title: const Text(
          'Workplace consent',
          style: TextStyle(fontWeight: FontWeight.w600, fontSize: 17),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(_error!, textAlign: TextAlign.center, style: appMutedStyle()),
                      const SizedBox(height: 16),
                      FilledButton(
                        style: appPrimaryButtonStyle(),
                        onPressed: _load,
                        child: const Text('Try again'),
                      ),
                    ],
                  ),
                )
              : Column(
                  children: [
                    Expanded(
                      child: ListView(
                        padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
                        children: [
                          Text(
                            status?.businessName ?? 'Workplace consent',
                            style: appPageTitleStyle(),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            status?.isDemo == true
                                ? 'Please review this Demo Café consent page before continuing. Agreeing here does not turn on live camera or phone GPS.'
                                : 'Please review your workplace consent page, including terms, privacy, and face enrollment, before continuing.',
                            style: appMutedStyle(),
                          ),
                          const SizedBox(height: 18),
                          Container(
                            padding: const EdgeInsets.all(16),
                            decoration: appCardDecoration(),
                            child: Text(
                              status?.content ?? '',
                              style: appBodyStyle().copyWith(height: 1.55),
                            ),
                          ),
                          const SizedBox(height: 8),
                          TextButton(
                            onPressed: _openWebpage,
                            child: const Text('Open consent webpage'),
                          ),
                        ],
                      ),
                    ),
                    SafeArea(
                      top: false,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              'I agree records this consent on your employee profile. You will not be asked again unless your employer requires it.',
                              style: appMutedStyle().copyWith(fontSize: 12),
                            ),
                            const SizedBox(height: 12),
                            FilledButton(
                              style: appPrimaryButtonStyle(),
                              onPressed: _saving ? null : _agree,
                              child: Text(_saving ? 'Saving…' : 'I agree'),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
    );
  }
}
