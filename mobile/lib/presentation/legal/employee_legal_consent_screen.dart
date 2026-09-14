import 'package:aroll_mobile/core/app_state.dart';
import 'package:aroll_mobile/core/di/injection.dart';
import 'package:aroll_mobile/core/legal/consent_sync.dart';
import 'package:aroll_mobile/core/network/api_client.dart';
import 'package:aroll_mobile/core/router/app_router.dart';
import 'package:aroll_mobile/domain/entities/legal_consent.dart';
import 'package:aroll_mobile/domain/repositories/employee_repository.dart';
import 'package:aroll_mobile/presentation/employee/employee_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:go_router/go_router.dart';

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
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Could not load workplace consents.';
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

  String _documentUrl(ConsentDocumentItem item) {
    if (item.url.startsWith('http://') || item.url.startsWith('https://')) {
      return item.url;
    }
    if (!sl.isRegistered<ApiClient>()) {
      final path = item.url.startsWith('/') ? item.url : '/${item.url}';
      return 'http://127.0.0.1:8000$path';
    }
    return sl<ApiClient>().resolvePublicUrl(item.url);
  }

  bool get _inWidgetTest =>
      WidgetsBinding.instance.runtimeType.toString().contains('Test');

  Future<void> _accept() async {
    final current = _current;
    if (current == null || _submitting) return;
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
      });
      final remaining = pendingRequiredConsents(payload.items);
      if (remaining.isEmpty) {
        final router = GoRouter.maybeOf(context);
        if (router != null) {
          router.go(resolveAuthenticatedRoute(appState));
        }
        return;
      }
      setState(() => _index = 0);
    } catch (_) {
      if (!mounted) return;
      setState(() => _submitting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not record consent. Try again.')),
      );
    }
  }

  void _nextView() {
    if (_index + 1 < _queue.length) {
      setState(() => _index += 1);
      return;
    }
    context.pop();
  }

  @override
  Widget build(BuildContext context) {
    final current = _current;
    return PopScope(
      canPop: !_blocking,
      child: Scaffold(
        backgroundColor: EmployeeColors.scaffold,
        appBar: AppBar(
          backgroundColor: EmployeeColors.scaffold,
          elevation: 0,
          automaticallyImplyLeading: !_blocking,
          title: Text(
            current?.title ?? 'Workplace consents',
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
        body: SafeArea(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _error != null
                  ? Center(child: Text(_error!))
                  : current == null
                      ? const Center(
                          child: Text(
                            'No published consents are available. Ask your employer to publish workplace consents.',
                            textAlign: TextAlign.center,
                          ),
                        )
                      : Column(
                          children: [
                            if (_queue.length > 1)
                              Padding(
                                padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
                                child: Text(
                                  'Document ${_index + 1} of ${_queue.length}',
                                  style: const TextStyle(
                                    color: EmployeeColors.textMuted,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            Expanded(child: _buildDocument(current)),
                            Padding(
                              padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
                              child: SizedBox(
                                width: double.infinity,
                                child: FilledButton(
                                  onPressed: _submitting
                                      ? null
                                      : current.accepted
                                          ? (widget.viewOnly ||
                                                  sl<AppState>()
                                                          .consentsCompleted ==
                                                      true
                                              ? _nextView
                                              : null)
                                          : _accept,
                                  child: Text(
                                    current.accepted
                                        ? (widget.viewOnly ||
                                                sl<AppState>()
                                                        .consentsCompleted ==
                                                    true
                                            ? (_index + 1 < _queue.length
                                                ? 'Next'
                                                : 'Done')
                                            : 'Accepted')
                                        : (_submitting
                                            ? 'Saving…'
                                            : 'Accept'),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
        ),
      ),
    );
  }

  Widget _buildDocument(ConsentDocumentItem item) {
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
    return InAppWebView(
      initialUrlRequest: URLRequest(url: WebUri(url)),
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
