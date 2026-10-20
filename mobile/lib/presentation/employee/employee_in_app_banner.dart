import 'dart:async';

import 'package:aroll_mobile/core/di/injection.dart';
import 'package:aroll_mobile/domain/repositories/employee_repository.dart';
import 'package:aroll_mobile/presentation/shared/app_ui.dart';
import 'package:aroll_mobile/presentation/shared/notification_routing.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// Foreground poll interval for Employee banners. Owner still uses 60s.
const Duration employeeInAppPollInterval = Duration(seconds: 8);

/// Visible lifetime of an Employee in-app banner after it is shown.
const Duration employeeInAppBannerDuration = Duration(seconds: 3);

/// Queues unread inbox items for a single top-of-screen Employee banner.
class EmployeeInAppBannerController {
  final Set<String> seenIds = {};
  final List<Map<String, dynamic>> queue = [];
  Map<String, dynamic>? visible;
  bool primed = false;
  int generation = 0;

  void prime(Iterable<Map<String, dynamic>> items) {
    primed = true;
    for (final item in items) {
      final id = idOf(item);
      if (id.isNotEmpty) seenIds.add(id);
    }
  }

  List<String> ingest(Iterable<Map<String, dynamic>> items) {
    if (!primed) {
      prime(items);
      return const [];
    }
    final newcomers = <Map<String, dynamic>>[];
    for (final item in items) {
      final id = idOf(item);
      if (id.isEmpty || seenIds.contains(id)) continue;
      if (item['is_read'] == true) continue;
      seenIds.add(id);
      newcomers.add(item);
    }
    for (final item in newcomers.reversed) {
      queue.add(Map<String, dynamic>.from(item));
    }
    return newcomers.map(idOf).toList();
  }

  Map<String, dynamic>? showNext() {
    if (visible != null) return visible;
    if (queue.isEmpty) return null;
    visible = queue.removeAt(0);
    generation += 1;
    return visible;
  }

  bool dismissIfCurrent(String id) {
    if (visible == null || idOf(visible!) != id) return false;
    visible = null;
    return true;
  }

  static String idOf(Map<String, dynamic> item) => '${item['id'] ?? ''}';
}

/// Employee-only overlay: top placement, 3s dismiss, white banner.
class EmployeeInAppNotificationHost extends StatefulWidget {
  const EmployeeInAppNotificationHost({
    super.key,
    required this.child,
    this.fetchUnread,
    this.onOpen,
    this.pollInterval = employeeInAppPollInterval,
    this.displayDuration = employeeInAppBannerDuration,
    this.controller,
  });

  final Widget child;
  final Future<List<Map<String, dynamic>>> Function()? fetchUnread;
  final Future<void> Function(Map<String, dynamic> item)? onOpen;
  final Duration pollInterval;
  final Duration displayDuration;
  final EmployeeInAppBannerController? controller;

  @override
  State<EmployeeInAppNotificationHost> createState() =>
      _EmployeeInAppNotificationHostState();
}

class _EmployeeInAppNotificationHostState
    extends State<EmployeeInAppNotificationHost> with WidgetsBindingObserver {
  late final EmployeeInAppBannerController _controller;
  Timer? _pollTimer;
  Timer? _dismissTimer;
  bool _polling = false;
  int _dismissGeneration = 0;

  @override
  void initState() {
    super.initState();
    _controller = widget.controller ?? EmployeeInAppBannerController();
    WidgetsBinding.instance.addObserver(this);
    _poll(initial: true);
    _pollTimer = Timer.periodic(widget.pollInterval, (_) => _poll());
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _dismissTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _poll();
  }

  Future<List<Map<String, dynamic>>> _loadUnread() {
    if (widget.fetchUnread != null) return widget.fetchUnread!();
    return sl<EmployeeRepository>().notifications(unreadOnly: true, limit: 10);
  }

  Future<void> _open(Map<String, dynamic> item) async {
    if (widget.onOpen != null) {
      await widget.onOpen!(item);
      return;
    }
    if (!mounted) return;
    final destination = notificationDestination(
      type: '${item['type'] ?? ''}',
      deepLink: '${item['deep_link'] ?? ''}',
      entityId: '${item['entity_id'] ?? ''}',
    );
    context.push(destination);
  }

  Future<void> _poll({bool initial = false}) async {
    if (_polling) return;
    _polling = true;
    try {
      final items = await _loadUnread();
      if (!mounted) return;
      if (initial) {
        _controller.prime(items);
        return;
      }
      _controller.ingest(items);
      _presentNext();
    } catch (_) {
    } finally {
      _polling = false;
    }
  }

  void _presentNext() {
    if (_controller.visible != null) {
      if (mounted) setState(() {});
      return;
    }
    final next = _controller.showNext();
    if (next == null) {
      if (mounted) setState(() {});
      return;
    }
    _armDismiss(EmployeeInAppBannerController.idOf(next), _controller.generation);
    if (mounted) setState(() {});
  }

  void _armDismiss(String id, int generation) {
    _dismissTimer?.cancel();
    _dismissGeneration = generation;
    _dismissTimer = Timer(widget.displayDuration, () {
      if (!mounted || _dismissGeneration != generation) return;
      if (_controller.dismissIfCurrent(id)) {
        _presentNext();
      }
    });
  }

  void _dismissVisible({required bool open}) {
    final item = _controller.visible;
    if (item == null) return;
    final id = EmployeeInAppBannerController.idOf(item);
    _dismissTimer?.cancel();
    _controller.dismissIfCurrent(id);
    if (open) {
      _open(item);
    }
    _presentNext();
  }

  @override
  Widget build(BuildContext context) {
    final item = _controller.visible;
    return Stack(
      children: [
        widget.child,
        if (item != null)
          Positioned(
            key: const Key('employee-in-app-banner'),
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                child: _EmployeeBannerCard(
                  item: item,
                  onTap: () => _dismissVisible(open: true),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _EmployeeBannerCard extends StatelessWidget {
  const _EmployeeBannerCard({required this.item, required this.onTap});

  final Map<String, dynamic> item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final title = '${item['title'] ?? 'Notification'}';
    final message = '${item['message'] ?? ''}';
    final type = '${item['type'] ?? ''}';
    return Material(
      color: Colors.transparent,
      child: AnimatedSlide(
        duration: const Duration(milliseconds: 180),
        offset: Offset.zero,
        curve: Curves.easeOutCubic,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.border),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.08),
                blurRadius: 16,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Material(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            child: InkWell(
              key: const Key('employee-in-app-banner-tap'),
              borderRadius: BorderRadius.circular(12),
              onTap: onTap,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: AppColors.iconWell,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(
                        _iconFor(type),
                        size: 18,
                        color: AppColors.primary,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              height: 1.25,
                              color: AppColors.textPrimary,
                            ),
                          ),
                          if (message.isNotEmpty) ...[
                            const SizedBox(height: 2),
                            Text(
                              message,
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 13,
                                height: 1.3,
                                color: AppColors.textMuted,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  IconData _iconFor(String type) {
    switch (notificationIconKind(type)) {
      case IconDataForType.leave:
        return Icons.event_busy_rounded;
      case IconDataForType.overtime:
        return Icons.more_time_rounded;
      case IconDataForType.attendance:
        return Icons.fact_check_outlined;
      case IconDataForType.payroll:
        return Icons.payments_outlined;
      case IconDataForType.schedule:
        return Icons.calendar_month_outlined;
      case IconDataForType.generic:
        return Icons.notifications_outlined;
    }
  }
}
