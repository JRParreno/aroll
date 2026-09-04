import 'package:aroll_mobile/core/di/injection.dart';
import 'package:aroll_mobile/data/repositories/owner_repository.dart';
import 'package:aroll_mobile/presentation/owner/owner_shell.dart';
import 'package:aroll_mobile/presentation/shared/app_ui.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

class OwnerNotificationsScreen extends StatefulWidget {
  const OwnerNotificationsScreen({super.key});

  @override
  State<OwnerNotificationsScreen> createState() =>
      _OwnerNotificationsScreenState();
}

class _OwnerNotificationsScreenState extends State<OwnerNotificationsScreen> {
  final _repo = sl<OwnerRepository>();
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
    if (type.startsWith('attendance')) return Icons.fact_check_outlined;
    if (type.startsWith('payroll')) return Icons.payments_outlined;
    if (type.startsWith('schedule')) return Icons.calendar_month_outlined;
    return Icons.notifications_outlined;
  }

  String _relativeTime(DateTime? value) {
    if (value == null) return '';
    final diff = DateTime.now().difference(value);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes} minutes ago';
    if (diff.inHours < 24) return '${diff.inHours} hours ago';
    if (diff.inDays < 7) return '${diff.inDays} days ago';
    return DateFormat.MMMd().add_jm().format(value);
  }

  Future<void> _open(Map<String, dynamic> item) async {
    final id = '${item['id']}';
    if (item['is_read'] != true) {
      try {
        await _repo.markRead(id);
      } catch (_) {}
    }
    if (!mounted) return;
    final deepLink = '${item['deep_link'] ?? ''}';
    final type = '${item['type'] ?? ''}';
    final entityType = '${item['entity_type'] ?? ''}';
    final entityId = '${item['entity_id'] ?? ''}';
    if (deepLink.isNotEmpty) {
      context.push(deepLink);
      return;
    }
    if (type.startsWith('leave') || entityType == 'leave') {
      if (entityId.isNotEmpty) {
        context.push('/owner/leave/$entityId');
      } else {
        context.push('/owner/leave');
      }
      return;
    }
    if (type.startsWith('attendance') || entityType == 'attendance_correction') {
      if (entityId.isNotEmpty) {
        context.push('/owner/attendance?correctionId=$entityId');
      } else {
        context.push('/owner/attendance');
      }
      return;
    }
    context.push('/owner/leave');
  }

  @override
  Widget build(BuildContext context) {
    return OwnerShell(
      selectedIndex: 0,
      showBackButton: true,
      showNotificationBell: false,
      title: 'Notifications',
      actions: [
        TextButton(
          onPressed: () async {
            await _repo.markAllRead();
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
              child: Text(
                'No notifications yet.',
                style: appMutedStyle(),
              ),
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
                        border: Border.all(color: AppColors.border),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              color: AppColors.primary.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Icon(
                              _iconFor('${item['type'] ?? ''}'),
                              size: 18,
                              color: AppColors.primary,
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
                                    fontWeight:
                                        unread ? FontWeight.w800 : FontWeight.w700,
                                    fontSize: 14,
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
                              decoration: const BoxDecoration(
                                color: AppColors.primary,
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
