import 'package:aroll_mobile/core/app_state.dart';
import 'package:aroll_mobile/core/di/injection.dart';
import 'package:aroll_mobile/core/legal/consent_sync.dart';
import 'package:aroll_mobile/core/network/api_client.dart';
import 'package:aroll_mobile/core/router/app_router.dart';
import 'package:aroll_mobile/core/theme/business_brand_theme.dart';
import 'package:aroll_mobile/domain/entities/legal_consent.dart';
import 'package:aroll_mobile/domain/repositories/employee_repository.dart';
import 'package:aroll_mobile/presentation/employee/employee_ui.dart';
import 'package:aroll_mobile/presentation/shared/app_ui.dart';
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
  bool _pageLoading = false;
  bool _pageError = false;
  int _index = 0;
  InAppWebViewController? _webController;

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
        _preparePage();
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

  bool get _browsing =>
      widget.viewOnly || sl<AppState>().consentsCompleted == true;

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

  void _preparePage() {
    _pageLoading = !_inWidgetTest;
    _pageError = false;
    _webController = null;
  }

  void _onMainFrameFailed() {
    if (!mounted) return;
    setState(() {
      _pageLoading = false;
      _pageError = true;
    });
  }

  Future<void> _reloadPage() async {
    setState(() {
      _pageError = false;
      _pageLoading = !_inWidgetTest;
    });
    await _webController?.reload();
  }

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
      setState(() {
        _index = 0;
        _preparePage();
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _submitting = false);
      showAppSnack(
        context,
        message: 'Could not record consent. Try again.',
        isError: true,
      );
    }
  }

  void _nextView() {
    if (_index + 1 < _queue.length) {
      setState(() {
        _index += 1;
        _preparePage();
      });
      return;
    }
    context.pop();
  }

  String _actionLabel(ConsentDocumentItem current) {
    if (current.accepted) {
      if (_browsing) {
        return _index + 1 < _queue.length ? 'Next' : 'Done';
      }
      return 'Accepted';
    }
    return 'Accept';
  }

  VoidCallback? _actionPressed(ConsentDocumentItem current) {
    if (_submitting) return null;
    if (current.accepted) {
      return _browsing ? _nextView : null;
    }
    if (_pageError) return null;
    return _accept;
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
          scrolledUnderElevation: 0,
          automaticallyImplyLeading: false,
          titleSpacing: _blocking ? NavigationToolbar.kMiddleSpacing : 0,
          centerTitle: false,
          leading: _blocking
              ? null
              : IconButton(
                  tooltip: 'Back',
                  constraints: const BoxConstraints(
                    minWidth: AppSizes.minTap,
                    minHeight: AppSizes.minTap,
                  ),
                  onPressed: () => appNavigateBack(
                    context,
                    fallbackRoute: '/profile',
                  ),
                  icon: const Icon(
                    Icons.arrow_back_rounded,
                    size: AppSizes.iconLg,
                  ),
                ),
          title: EmployeePageTitle(current?.title ?? 'Workplace consents'),
        ),
        body: SafeArea(
          child: _loading
              ? const _ConsentLoadingState()
              : _error != null
                  ? AppErrorState(message: _error!, onRetry: _load)
                  : current == null
                      ? const AppEmptyState(
                          title: 'No consents available',
                          description:
                              'No published consents are available. Ask your employer to publish workplace consents.',
                          icon: Icons.description_outlined,
                        )
                      : Column(
                          children: [
                            _ConsentProgressHeader(
                              title: current.title,
                              index: _index,
                              total: _queue.length,
                              browsing: _browsing,
                            ),
                            Expanded(child: _buildDocument(current)),
                            _ConsentActionBar(
                              label: _actionLabel(current),
                              loading: _submitting,
                              onPressed: _actionPressed(current),
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
      return Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          0,
          AppSpacing.lg,
          AppSpacing.sm,
        ),
        child: Container(
          width: double.infinity,
          decoration: appCardDecoration(),
          child: ColoredBox(
            color: AppColors.white,
            child: Center(
              child: Text(
                url,
                key: const Key('consent-preview-url'),
              ),
            ),
          ),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        0,
        AppSpacing.lg,
        AppSpacing.sm,
      ),
      child: Container(
        decoration: appCardDecoration(),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          children: [
            InAppWebView(
              key: ValueKey(item.id),
              initialUrlRequest: URLRequest(url: WebUri(url)),
              onWebViewCreated: (controller) {
                _webController = controller;
              },
              onLoadStart: (controller, _) {
                if (!mounted) return;
                setState(() {
                  _pageLoading = true;
                  _pageError = false;
                });
              },
              onLoadStop: (controller, _) {
                if (!mounted) return;
                setState(() => _pageLoading = false);
              },
              onReceivedError: (controller, request, error) {
                if (request.isForMainFrame != false) {
                  _onMainFrameFailed();
                }
              },
              onReceivedHttpError: (controller, request, response) {
                final code = response.statusCode ?? 0;
                if (request.isForMainFrame != false && code >= 400) {
                  _onMainFrameFailed();
                }
              },
            ),
            if (_pageLoading)
              const ColoredBox(
                color: AppColors.white,
                child: _ConsentLoadingState(compact: true),
              ),
            if (_pageError)
              ColoredBox(
                color: AppColors.white,
                child: AppErrorState(
                  message: 'This consent document could not be loaded.',
                  onRetry: _reloadPage,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _ConsentProgressHeader extends StatelessWidget {
  const _ConsentProgressHeader({
    required this.title,
    required this.index,
    required this.total,
    required this.browsing,
  });

  final String title;
  final int index;
  final int total;
  final bool browsing;

  @override
  Widget build(BuildContext context) {
    final brand = BrandColors.of(context);
    final progress = total <= 0 ? 0.0 : (index + 1) / total;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.xs,
        AppSpacing.lg,
        AppSpacing.md,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Document ${index + 1} of $total',
            style: appMutedStyle().copyWith(fontWeight: FontWeight.w600),
          ),
          if (total > 1) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: appSectionTitleStyle(),
            ),
          ],
          const SizedBox(height: AppSpacing.sm),
          ClipRRect(
            borderRadius: BorderRadius.circular(AppRadii.chip),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 4,
              color: brand.primary,
              backgroundColor: brand.iconWell,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            browsing
                ? 'Review your workplace consent documents.'
                : 'Review this workplace document, then tap Accept.',
            style: appMutedStyle(),
          ),
        ],
      ),
    );
  }
}

class _ConsentActionBar extends StatelessWidget {
  const _ConsentActionBar({
    required this.label,
    required this.loading,
    required this.onPressed,
  });

  final String label;
  final bool loading;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.md,
        AppSpacing.lg,
        AppSpacing.lg,
      ),
      decoration: const BoxDecoration(
        color: AppColors.white,
        border: Border(
          top: BorderSide(color: AppColors.border),
        ),
      ),
      child: EmployeePrimaryButton(
        label: label,
        loading: loading,
        onPressed: onPressed,
      ),
    );
  }
}

class _ConsentLoadingState extends StatelessWidget {
  const _ConsentLoadingState({this.compact = false});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: EdgeInsets.all(compact ? AppSpacing.lg : AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(
              strokeWidth: 2.5,
              color: BrandColors.of(context).primary,
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              compact ? 'Loading document' : 'Loading workplace consents',
              style: appMutedStyle(),
            ),
          ],
        ),
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
