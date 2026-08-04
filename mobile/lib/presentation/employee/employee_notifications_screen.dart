import 'package:aroll_mobile/core/di/injection.dart';
import 'package:aroll_mobile/core/theme/business_brand_theme.dart';
import 'package:aroll_mobile/domain/repositories/employee_repository.dart';
import 'package:aroll_mobile/presentation/employee/employee_ui.dart';
import 'package:aroll_mobile/presentation/shared/app_ui.dart';
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
  late Future<List<Map<String, dynamic>>> _future;

  @override
  void initState() {
    super.initState();
    _future = _repo.notifications();
  }

  Future<void> _reload() async {
    final next = _repo.notifications();
    setState(() => _future = next);
    await next;
  }

  IconData _iconFor(String type) {
    if (type.startsWith('leave')) return Icons.event_busy_rounded;
    if (type.contains('incomplete') || type.startsWith('attendance')) {
      return Icons.fact_check_outlined;
    }
    if (type.startsWith('payroll')) return Icons.payments_outlined;
    if (type.startsWith('schedule')) return Icons.calendar_month_outlined;
    return Icons.notifications_outlined;
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
    final deepLink = '${item['deep_link'] ?? ''}';
    final type = '${item['type'] ?? ''}';
    final entityId = '${item['entity_id'] ?? ''}';

    if (deepLink.isNotEmpty) {
      context.push(deepLink);
      return;
    }
    if (type.startsWith('leave')) {
      if (entityId.isNotEmpty) {
        context.push('/leave-requests/$entityId');
      } else {
        context.push('/leave-requests');
      }
      return;
    }
    if (type.contains('incomplete') || type.startsWith('attendance')) {
      context.push('/shift-history');
      return;
    }
    if (type.startsWith('payroll')) {
      context.push('/payslip');
      return;
    }
    context.push('/home');
  }

  @override
  Widget build(BuildContext context) {
    return EmployeeScaffold(
      title: 'Notifications',
      selectedIndex: 0,
      showBack: true,
      actions: [
        TextButton(
          onPressed: () async {
            await _repo.markAllNotificationsRead();
            if (mounted) await _reload();
          },
          child: const Text('Mark all read'),
        ),
      ],
      child: FutureBuilder<List<Map<String, dynamic>>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final items = snapshot.data ?? const [];
          if (items.isEmpty) {
            return Center(
              child: Text('No notifications yet.', style: appMutedStyle()),
            );
          }
          return RefreshIndicator(
            onRefresh: _reload,
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              itemCount: items.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final item = items[index];
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
        },
      ),
    );
  }
}
