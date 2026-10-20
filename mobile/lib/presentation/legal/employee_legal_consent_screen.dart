import 'package:aroll_mobile/core/app_state.dart';
import 'package:aroll_mobile/core/di/injection.dart';
import 'package:aroll_mobile/core/network/api_client.dart';
import 'package:aroll_mobile/core/router/app_router.dart';
import 'package:aroll_mobile/domain/entities/legal_consent.dart';
import 'package:aroll_mobile/domain/repositories/employee_repository.dart';
import 'package:aroll_mobile/presentation/employee/employee_ui.dart';
import 'package:aroll_mobile/presentation/shared/app_ui.dart';
import 'package:aroll_mobile/presentation/shared/confirm_action_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

class EmployeeConsentFlowScreen extends StatefulWidget {
  const EmployeeConsentFlowScreen({
    super.key,
    this.viewOnly = false,
    this.repository,
  });

  final bool viewOnly;
  final EmployeeRepository? repository;

  @override
  State<EmployeeConsentFlowScreen> createState() =>
      _EmployeeConsentFlowScreenState();
}

class _EmployeeConsentFlowScreenState extends State<EmployeeConsentFlowScreen> {
  EmployeeConsents? _payload;
  String? _error;
  bool _loading = true;
  bool _submitting = false;
  bool _agreed = false;
  int _index = 0;

  EmployeeRepository get _repository =>
      widget.repository ?? sl<EmployeeRepository>();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
      _agreed = false;
    });
    try {
      final payload = await _repository.getConsents();
      if (!mounted) return;
      final appState = sl<AppState>();
      appState.setConsentStatus(
        legalSatisfied: payload.consentsCompleted,
        biometricSatisfied: payload.consentsCompleted,
        consentsCompleted: payload.consentsCompleted,
      );
      setState(() {
        _payload = payload;
        _loading = false;
        _index = 0;
        _agreed = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Could not load workplace consents. Please try again.';
      });
    }
  }

  List<ConsentDocumentItem> get _queue {
    final items = _payload?.items ?? const <ConsentDocumentItem>[];
    if (widget.viewOnly || sl<AppState>().consentsCompleted == true) {
      final copy = [...items]..sort((a, b) => a.position.compareTo(b.position));
      return copy;
    }
    return pendingRequiredConsents(items);
  }

  ConsentDocumentItem? get _current {
    final queue = _queue;
    if (queue.isEmpty || _index >= queue.length) return null;
    return queue[_index];
  }

  bool get _blocking =>
      !widget.viewOnly && sl<AppState>().consentsCompleted != true;

  bool get _isLastStep => _index + 1 >= _queue.length;

  String _documentUrl(ConsentDocumentItem item) {
    String url;
    if (item.url.startsWith('http://') || item.url.startsWith('https://')) {
      url = item.url;
    } else if (!sl.isRegistered<ApiClient>()) {
      final path = item.url.startsWith('/') ? item.url : '/${item.url}';
      url = 'http://127.0.0.1:8000$path';
    } else {
      url = sl<ApiClient>().resolvePublicUrl(item.url);
    }
    final uri = Uri.parse(url);
    return uri.replace(
      queryParameters: {
        ...uri.queryParameters,
        'embed': '1',
      },
    ).toString();
  }

  bool get _inWidgetTest =>
      WidgetsBinding.instance.runtimeType.toString().contains('Test');

  Future<void> _acceptCurrent() async {
    final current = _current;
    if (current == null || _submitting || (!_agreed && !current.accepted)) {
      return;
    }
    if (current.accepted) {
      _goNextAfterAccept();
      return;
    }
    setState(() => _submitting = true);
    try {
      final payload = await _repository.acceptConsentDocument(current.id);
      if (!mounted) return;
      final appState = sl<AppState>();
      appState.setConsentStatus(
        legalSatisfied: payload.consentsCompleted,
        biometricSatisfied: payload.consentsCompleted,
        consentsCompleted: payload.consentsCompleted,
      );
      setState(() {
        _payload = payload;
        _submitting = false;
        _agreed = false;
      });
      _goNextAfterAccept();
    } catch (_) {
      if (!mounted) return;
      setState(() => _submitting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not record consent. Please try again.'),
        ),
      );
    }
  }

  void _goNextAfterAccept() {
    final appState = sl<AppState>();
    final remaining = pendingRequiredConsents(_payload?.items ?? const []);
    if (!_blocking || remaining.isEmpty || appState.consentsCompleted == true) {
      if (widget.viewOnly) {
        if (_index + 1 < _queue.length) {
          setState(() {
            _index += 1;
            _agreed = false;
          });
        } else if (context.canPop()) {
          context.pop();
        }
        return;
      }
      final router = GoRouter.maybeOf(context);
      router?.go(resolveAuthenticatedRoute(appState));
      return;
    }
    setState(() {
      _index = 0;
      _agreed = false;
    });
  }

  void _goBack() {
    if (_index <= 0) return;
    setState(() {
      _index -= 1;
      _agreed = _current?.accepted == true;
    });
  }

  Future<void> _onDecline() async {
    final current = _current;
    final isBiometric = current?.isBiometric == true;
    final result = await showDialog<_DeclineChoice>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          isBiometric ? 'Biometric consent declined' : 'Required terms declined',
        ),
        content: Text(
          isBiometric
              ? 'Without biometric consent you cannot enroll your face or use '
                  'face Time In / Time Out. Other workplace features that do not '
                  'require face recognition are unaffected. You must accept this '
                  'document to continue enrollment and live attendance.'
              : 'These terms are required to use Aroll+. Declining means you '
                  'cannot continue into the app. No agreement has been recorded.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, _DeclineChoice.returnToTerms),
            child: const Text('Return to Terms'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, _DeclineChoice.signOut),
            child: const Text('Sign Out'),
          ),
        ],
      ),
    );
    if (!mounted || result == null) return;
    if (result == _DeclineChoice.signOut) {
      await confirmEmployeeSignOut(context);
    }
  }

  Future<void> _withdrawBiometric() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => const ConfirmActionDialog(
        icon: Icons.fingerprint_rounded,
        title: 'Withdraw biometric consent',
        message:
            'This records a withdrawal for biometric consent. Face enrollment '
            'and face attendance will be blocked until you agree again. '
            'Your previous agreement history is kept.',
        confirmLabel: 'Withdraw',
        iconColor: AppColors.danger,
        iconBackground: Color(0xFFFEE2E2),
        confirmColor: Color(0xFFB91C1C),
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _submitting = true);
    try {
      await _repository.withdrawBiometricConsent();
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Biometric consent withdrawn.')),
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _submitting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not withdraw biometric consent. Try again.'),
        ),
      );
    }
  }

  String _formatAcceptedAt(DateTime? value) {
    if (value == null) return 'Not recorded';
    return DateFormat('MMM d, yyyy').format(value.toLocal());
  }

  @override
  Widget build(BuildContext context) {
    final current = _current;
    final primary = brandPrimary(context);

    return PopScope(
      canPop: !_blocking,
      child: Scaffold(
        backgroundColor: const Color(0xFFF7F8FA),
        body: SafeArea(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _error != null
                  ? _ErrorPane(message: _error!, onRetry: _load)
                  : current == null
                      ? const Center(
                          child: Padding(
                            padding: EdgeInsets.all(24),
                            child: Text(
                              'No published consents are available. Ask your '
                              'employer to publish workplace consents.',
                              textAlign: TextAlign.center,
                            ),
                          ),
                        )
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Padding(
                              padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
                              child: _StepHeader(
                                step: _index + 1,
                                total: _queue.length,
                                title: current.title,
                                primary: primary,
                                showBack: (_blocking && _index > 0) ||
                                    (!_blocking && _index > 0),
                                onBack: _submitting ? null : _goBack,
                                canPop: !_blocking && _index == 0,
                              ),
                            ),
                            if (widget.viewOnly)
                              Padding(
                                padding:
                                    const EdgeInsets.fromLTRB(24, 12, 24, 0),
                                child: _MinimalStatus(
                                  accepted: current.accepted,
                                  required: current.required,
                                  version: current.acceptedVersion ??
                                      current.version,
                                  agreedLabel: _formatAcceptedAt(
                                    current.acceptedAt,
                                  ),
                                ),
                              ),
                            const SizedBox(height: 8),
                            Expanded(
                              child: Padding(
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 24),
                                child: DecoratedBox(
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(16),
                                    border: Border.all(
                                      color: const Color(0xFFE5E7EB),
                                    ),
                                  ),
                                  child: Padding(
                                    padding: const EdgeInsets.fromLTRB(
                                      16,
                                      12,
                                      16,
                                      8,
                                    ),
                                    child: _buildDocument(current),
                                  ),
                                ),
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.fromLTRB(24, 8, 24, 20),
                              child: widget.viewOnly
                                  ? _ViewConsentActions(
                                      item: current,
                                      primary: primary,
                                      submitting: _submitting,
                                      isLast: _isLastStep,
                                      onNext: () {
                                        if (_isLastStep) {
                                          if (context.canPop()) context.pop();
                                        } else {
                                          setState(() {
                                            _index += 1;
                                            _agreed = false;
                                          });
                                        }
                                      },
                                      onWithdrawBiometric:
                                          current.isBiometric && current.accepted
                                              ? _withdrawBiometric
                                              : null,
                                    )
                                  : _OnboardingActions(
                                      item: current,
                                      agreed: _agreed || current.accepted,
                                      isLast: _isLastStep,
                                      submitting: _submitting,
                                      primary: primary,
                                      canGoBack: _index > 0,
                                      onBack: _goBack,
                                      onAgreedChanged: current.accepted
                                          ? null
                                          : (value) => setState(
                                                () => _agreed = value ?? false,
                                              ),
                                      onContinue: _acceptCurrent,
                                      onDecline: _onDecline,
                                    ),
                            ),
                          ],
                        ),
        ),
      ),
    );
  }

  Widget _buildDocument(ConsentDocumentItem item) {
    final body = item.bodyText?.trim() ?? '';
    if (body.isNotEmpty) {
      return _LegalBodyView(text: body);
    }
    final url = _documentUrl(item);
    if (_inWidgetTest) {
      return ColoredBox(
        color: Colors.white,
        child: Center(
          child: Text(
            url,
            key: const Key('consent-preview-url'),
          ),
        ),
      );
    }
    if ((item.fileUrl ?? '').trim().isNotEmpty) {
      return InAppWebView(
        initialUrlRequest: URLRequest(url: WebUri(url)),
      );
    }
    return const Center(
      child: Text(
        'This document has no published content yet.',
        textAlign: TextAlign.center,
      ),
    );
  }
}

class _LegalBodyView extends StatelessWidget {
  const _LegalBodyView({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: _parseLegalBody(text),
      ),
    );
  }
}

List<Widget> _parseLegalBody(String text) {
  final widgets = <Widget>[];
  final paragraph = <String>[];
  final bullets = <String>[];
  final ordered = <String>[];

  const bodyStyle = TextStyle(
    fontSize: 15,
    height: 1.55,
    color: EmployeeColors.textBody,
  );
  const headingStyle = TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.w700,
    height: 1.35,
    color: EmployeeColors.textPrimary,
  );

  void flushParagraph() {
    if (paragraph.isEmpty) return;
    widgets.add(
      Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Text(paragraph.join('\n'), style: bodyStyle),
      ),
    );
    paragraph.clear();
  }

  void flushList({required bool numbered}) {
    final items = numbered ? ordered : bullets;
    if (items.isEmpty) return;
    widgets.add(
      Padding(
        padding: const EdgeInsets.only(bottom: 12, left: 2),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var i = 0; i < items.length; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 22,
                      child: Text(
                        numbered ? '${i + 1}.' : '•',
                        style: bodyStyle,
                      ),
                    ),
                    Expanded(child: Text(items[i], style: bodyStyle)),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
    items.clear();
  }

  void flushAll() {
    flushParagraph();
    flushList(numbered: false);
    flushList(numbered: true);
  }

  for (final raw in text.replaceAll('\r\n', '\n').split('\n')) {
    final stripped = raw.trim();
    if (stripped.isEmpty) {
      flushAll();
      continue;
    }
    if (stripped == '---' || stripped == '***') {
      flushAll();
      widgets.add(const Padding(
        padding: EdgeInsets.only(bottom: 12),
        child: Divider(height: 1, color: Color(0xFFE5E7EB)),
      ));
      continue;
    }
    if (stripped.startsWith('### ')) {
      flushAll();
      widgets.add(
        Padding(
          padding: const EdgeInsets.only(top: 4, bottom: 8),
          child: Text(stripped.substring(4).trim(), style: headingStyle),
        ),
      );
      continue;
    }
    if (stripped.startsWith('## ')) {
      flushAll();
      widgets.add(
        Padding(
          padding: const EdgeInsets.only(top: 4, bottom: 8),
          child: Text(stripped.substring(3).trim(), style: headingStyle),
        ),
      );
      continue;
    }
    if (stripped.startsWith('# ')) {
      flushAll();
      widgets.add(
        Padding(
          padding: const EdgeInsets.only(top: 4, bottom: 8),
          child: Text(stripped.substring(2).trim(), style: headingStyle),
        ),
      );
      continue;
    }
    if (stripped.startsWith('• ') ||
        stripped.startsWith('- ') ||
        stripped.startsWith('* ')) {
      flushParagraph();
      flushList(numbered: true);
      bullets.add(stripped.substring(2).trim());
      continue;
    }
    final orderedMatch = RegExp(r'^(\d+)[.)]\s+(.*)$').firstMatch(stripped);
    if (orderedMatch != null) {
      flushParagraph();
      flushList(numbered: false);
      ordered.add(orderedMatch.group(2)!);
      continue;
    }
    flushList(numbered: false);
    flushList(numbered: true);
    paragraph.add(stripped);
  }
  flushAll();
  return widgets;
}

enum _DeclineChoice { returnToTerms, signOut }

class _StepHeader extends StatelessWidget {
  const _StepHeader({
    required this.step,
    required this.total,
    required this.title,
    required this.primary,
    required this.showBack,
    required this.onBack,
    required this.canPop,
  });

  final int step;
  final int total;
  final String title;
  final Color primary;
  final bool showBack;
  final VoidCallback? onBack;
  final bool canPop;

  @override
  Widget build(BuildContext context) {
    final progress = total <= 0 ? 0.0 : step / total;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            if (showBack)
              IconButton(
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                icon: const Icon(Icons.arrow_back_rounded, size: 22),
                onPressed: onBack,
              )
            else if (canPop)
              IconButton(
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                icon: const Icon(Icons.close_rounded, size: 22),
                onPressed: () => Navigator.of(context).maybePop(),
              )
            else
              const SizedBox(width: 36, height: 36),
            const Spacer(),
            Text(
              'Step $step of $total',
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: EmployeeColors.textMuted,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: LinearProgressIndicator(
            value: progress.clamp(0.0, 1.0),
            minHeight: 3,
            backgroundColor: const Color(0xFFE8EEF4),
            color: primary,
          ),
        ),
        const SizedBox(height: 18),
        Text(
          title,
          style: const TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.3,
            color: EmployeeColors.textPrimary,
          ),
        ),
        const SizedBox(height: 14),
        const Divider(height: 1, color: Color(0xFFE5E7EB)),
      ],
    );
  }
}

class _MinimalStatus extends StatelessWidget {
  const _MinimalStatus({
    required this.accepted,
    required this.required,
    required this.version,
    required this.agreedLabel,
  });

  final bool accepted;
  final bool required;
  final String? version;
  final String agreedLabel;

  @override
  Widget build(BuildContext context) {
    final versionLabel =
        (version != null && version!.isNotEmpty) ? version! : '—';
    final requirementLabel = required ? 'Required' : 'Optional';
    return Text.rich(
      TextSpan(
        style: const TextStyle(
          fontSize: 13,
          height: 1.45,
          color: EmployeeColors.textMuted,
        ),
        children: [
          TextSpan(
            text: accepted ? '✓ Agreed' : 'Not agreed',
            style: TextStyle(
              fontWeight: FontWeight.w700,
              color: accepted
                  ? EmployeeColors.textBody
                  : EmployeeColors.textMuted,
            ),
          ),
          TextSpan(
            text: '  ·  $requirementLabel  ·  Version $versionLabel  ·  $agreedLabel',
          ),
        ],
      ),
    );
  }
}

class _OnboardingActions extends StatelessWidget {
  const _OnboardingActions({
    required this.item,
    required this.agreed,
    required this.isLast,
    required this.submitting,
    required this.primary,
    required this.canGoBack,
    required this.onBack,
    required this.onAgreedChanged,
    required this.onContinue,
    required this.onDecline,
  });

  final ConsentDocumentItem item;
  final bool agreed;
  final bool isLast;
  final bool submitting;
  final Color primary;
  final bool canGoBack;
  final VoidCallback onBack;
  final ValueChanged<bool?>? onAgreedChanged;
  final VoidCallback onContinue;
  final VoidCallback onDecline;

  @override
  Widget build(BuildContext context) {
    final canContinue = agreed && !submitting;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        CheckboxListTile(
          value: agreed,
          onChanged: submitting ? null : onAgreedChanged,
          controlAffinity: ListTileControlAffinity.leading,
          contentPadding: EdgeInsets.zero,
          activeColor: primary,
          title: Text(
            item.isBiometric
                ? 'I have read this biometric consent and agree to facial verification for attendance.'
                : 'I have read and agree to this document.',
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              height: 1.35,
            ),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            if (canGoBack)
              TextButton(
                onPressed: submitting ? null : onBack,
                child: const Text(
                  'Back',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
              )
            else
              TextButton(
                onPressed: submitting ? null : onDecline,
                child: const Text(
                  "I Don't Agree",
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: EmployeeColors.textMuted,
                  ),
                ),
              ),
            const SizedBox(width: 8),
            Expanded(
              child: FilledButton(
                onPressed: canContinue ? onContinue : null,
                style: FilledButton.styleFrom(
                  backgroundColor: primary,
                  disabledBackgroundColor: primary.withValues(alpha: 0.28),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: Text(
                  submitting
                      ? 'Saving…'
                      : (isLast ? 'I Agree & Continue' : 'Next'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            ),
          ],
        ),
        if (canGoBack) ...[
          const SizedBox(height: 4),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: submitting ? null : onDecline,
              child: const Text(
                "I Don't Agree",
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: EmployeeColors.textMuted,
                  fontSize: 13,
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _ViewConsentActions extends StatelessWidget {
  const _ViewConsentActions({
    required this.item,
    required this.primary,
    required this.submitting,
    required this.isLast,
    required this.onNext,
    this.onWithdrawBiometric,
  });

  final ConsentDocumentItem item;
  final Color primary;
  final bool submitting;
  final bool isLast;
  final VoidCallback onNext;
  final VoidCallback? onWithdrawBiometric;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (onWithdrawBiometric != null) ...[
          TextButton(
            onPressed: submitting ? null : onWithdrawBiometric,
            child: const Text(
              'Withdraw biometric consent',
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: EmployeeColors.textMuted,
              ),
            ),
          ),
          const SizedBox(height: 4),
        ],
        FilledButton(
          onPressed: submitting ? null : onNext,
          style: FilledButton.styleFrom(
            backgroundColor: primary,
            minimumSize: const Size.fromHeight(48),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          child: Text(
            isLast ? 'Done' : 'Next',
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
      ],
    );
  }
}

class _ErrorPane extends StatelessWidget {
  const _ErrorPane({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton(onPressed: onRetry, child: const Text('Retry')),
          ],
        ),
      ),
    );
  }
}
