import 'package:aroll_mobile/core/app_state.dart';
import 'package:aroll_mobile/core/di/injection.dart';
import 'package:aroll_mobile/core/theme/business_brand_theme.dart';
import 'package:aroll_mobile/domain/repositories/employee_repository.dart';
import 'package:aroll_mobile/presentation/employee/employee_notification_badge.dart';
import 'package:aroll_mobile/presentation/employee/employee_ui.dart';
import 'package:aroll_mobile/presentation/shared/app_ui.dart';
import 'package:aroll_mobile/presentation/shared/notification_routing.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

class EmployeeNotificationsScreen extends StatefulWidget {
  const EmployeeNotificationsScreen({super.key});

  @override
  State<EmployeeNotificationsScreen> createState() =>
      _EmployeeNotificationsScreenState();
}

class _EmployeeNotificationsScreenState
    extends State<EmployeeNotificationsScreen> {
  final _repo = sl<EmployeeRepository>();
  List<Map<String, dynamic>> _items = const [];
  bool _loading = true;
  bool _markingAll = false;
  String? _loadError;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _load(acknowledge: true);
    });
  }

  Future<void> _load({required bool acknowledge}) async {
    try {
      final store = sl<EmployeeNotificationBadgeStore>();
      final prepared = acknowledge ? store.takePrepared() : null;
      final items = prepared ?? await _repo.notifications();
      if (acknowledge && prepared == null) {
        await _acknowledge(items);
      }
      if (!mounted) return;
      setState(() {
        _items = items;
        _loading = false;
        _loadError = null;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        if (_items.isEmpty) {
          _loadError = 'Could not load notifications.';
        }
      });
      if (_items.isNotEmpty) {
        _show('Could not refresh notifications.');
      }
    }
  }

  Future<void> _acknowledge(List<Map<String, dynamic>> items) async {
    final userId = sl<AppState>().session?.userId;
    if (userId == null) return;
    try {
      await sl<EmployeeNotificationBadgeStore>().acknowledge(userId, items);
    } catch (_) {}
  }

  Future<void> _markAllRead() async {
    if (_markingAll) return;
    final before = [
      for (final item in _items) Map<String, dynamic>.from(item),
    ];
    if (!before.any(notificationIsUnread)) {
      _show('No unread notifications.');
      return;
    }
    setState(() => _markingAll = true);
    final createdThrough = newestNotificationCreatedAt(before);
    try {
      await _repo.markAllNotificationsRead(createdThrough: createdThrough);
      List<Map<String, dynamic>>? refreshed;
      try {
        refreshed = await _repo.notifications();
      } catch (_) {}
      if (!mounted) return;
      final next = refreshed;
      if (next != null) {
        final persisted = intendedNotificationsMarked(
          before: before,
          after: next,
        );
        setState(() => _items = next);
        if (!persisted) {
          _show('Could not mark notifications as read.');
          return;
        }
        _show('All notifications marked as read.');
        return;
      }
      setState(() {
        _items = markNotificationsReadThrough(before, createdThrough);
      });
      _show('All notifications marked as read.');
    } catch (error) {
      if (!mounted) return;
      setState(() => _items = before);
      _show(_markAllError(error));
      try {
        final restored = await _repo.notifications();
        if (mounted) setState(() => _items = restored);
      } catch (_) {}
    } finally {
      if (mounted) setState(() => _markingAll = false);
    }
  }

  String _markAllError(Object error) {
    if (error is DioException) {
      final data = error.response?.data;
      if (data is Map && data['detail'] is String) {
        final detail = (data['detail'] as String).trim();
        if (detail.isNotEmpty) return detail;
      }
    }
    return 'Could not mark notifications as read.';
  }

  void _show(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
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

  String _relativeTime(DateTime? value) {
    if (value == null) return '';
    final diff = DateTime.now().difference(value);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return DateFormat.MMMd().add_jm().format(value);
  }

  Future<void> _open(Map<String, dynamic> item) async {
    final id = '${item['id']}';
    if (item['is_read'] != true) {
      try {
        await _repo.markNotificationRead(id);
      } catch (_) {}
    }
    if (!mounted) return;
    final destination = notificationDestination(
      type: '${item['type'] ?? ''}',
      deepLink: '${item['deep_link'] ?? ''}',
      entityId: '${item['entity_id'] ?? ''}',
    );
    context.push(destination);
  }

  @override
  Widget build(BuildContext context) {
    final markDisabled = _markingAll ||
        _loading ||
        (_loadError != null && _items.isEmpty);
    return EmployeeScaffold(
      title: 'Notifications',
      selectedIndex: 0,
      showBack: true,
      actions: [
        TextButton(
          onPressed: markDisabled ? null : _markAllRead,
          child: _markingAll
              ? const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    SizedBox(width: 8),
                    Text('Mark all read'),
                  ],
                )
              : const Text('Mark all read'),
        ),
      ],
      child: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading && _items.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_loadError != null && _items.isEmpty) {
      return Center(
        child: Text(_loadError!, style: appMutedStyle()),
      );
    }
    if (_items.isEmpty) {
      return Center(
        child: Text('No notifications yet.', style: appMutedStyle()),
      );
    }
    return RefreshIndicator(
      onRefresh: () => _load(acknowledge: false),
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        itemCount: _items.length,
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (context, index) {
          final item = _items[index];
          final unread = item['is_read'] != true;
          final created = DateTime.tryParse('${item['created_at']}');
          return Material(
            color: unread ? const Color(0xFFEFF6FF) : Colors.white,
            borderRadius: BorderRadius.circular(14),
            child: InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: () => _open(item),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: EmployeeColors.border),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: BrandColors.of(context)
                            .primary
                            .withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(
                        _iconFor('${item['type'] ?? ''}'),
                        size: 18,
                        color: BrandColors.of(context).primary,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${item['title'] ?? 'Notification'}',
                            style: TextStyle(
                              fontWeight: unread
                                  ? FontWeight.w800
                                  : FontWeight.w700,
                              fontSize: 14,
                              color: EmployeeColors.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '${item['message'] ?? ''}',
                            style: appMutedStyle().copyWith(fontSize: 13),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _relativeTime(created),
                            style: appMutedStyle().copyWith(fontSize: 11),
                          ),
                        ],
                      ),
                    ),
                    if (unread)
                      Container(
                        width: 8,
                        height: 8,
                        margin: const EdgeInsets.only(top: 6),
                        decoration: BoxDecoration(
                          color: BrandColors.of(context).primary,
                          shape: BoxShape.circle,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
