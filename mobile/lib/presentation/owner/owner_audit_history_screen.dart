import 'package:aroll_mobile/core/di/injection.dart';
import 'package:aroll_mobile/data/repositories/owner_repository.dart';
import 'package:aroll_mobile/presentation/owner/owner_shell.dart';
import 'package:aroll_mobile/presentation/owner/setup/setup_ui.dart';
import 'package:aroll_mobile/presentation/shared/app_ui.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class OwnerAuditHistoryScreen extends StatefulWidget {
  const OwnerAuditHistoryScreen({super.key});

  @override
  State<OwnerAuditHistoryScreen> createState() =>
      _OwnerAuditHistoryScreenState();
}

class _OwnerAuditHistoryScreenState extends State<OwnerAuditHistoryScreen> {
  final _repo = sl<OwnerRepository>();
  late Future<List<Map<String, dynamic>>> _future;

  @override
  void initState() {
    super.initState();
    _future = _repo.activityLogs();
  }

  Future<void> _reload() async {
    setState(() {
      _future = _repo.activityLogs();
    });
    await _future;
  }

  String _formatAction(String action) {
    return action
        .replaceAll(RegExp(r'[_-]+'), ' ')
        .toLowerCase()
        .split(' ')
        .where((part) => part.isNotEmpty)
        .map((part) => '${part[0].toUpperCase()}${part.substring(1)}')
        .join(' ');
  }

  String _formatDate(dynamic value) {
    if (value == null) return '—';
    final parsed = DateTime.tryParse('$value');
    if (parsed == null) return '$value';
    return DateFormat('MMM d, yyyy · h:mm a').format(parsed.toLocal());
  }

  @override
  Widget build(BuildContext context) {
    return OwnerShell(
      selectedIndex: 2,
      showBackButton: true,
      title: 'Audit History',
      backgroundColor: SetupUi.scaffold,
      child: FutureBuilder<List<Map<String, dynamic>>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            final message = snapshot.error is DioException
                ? 'Unable to load audit history.'
                : 'Unable to load audit history.';
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      message,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: AppColors.textMuted),
                    ),
                    const SizedBox(height: 12),
                    TextButton(
                      onPressed: _reload,
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              ),
            );
          }

          final logs = snapshot.data ?? const [];
          if (logs.isEmpty) {
            return RefreshIndicator(
              onRefresh: _reload,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 24, 16, 28),
                children: const [
                  SizedBox(height: 48),
                  Icon(Icons.history_toggle_off_rounded, size: 40, color: AppColors.textMuted),
                  SizedBox(height: 12),
                  Text(
                    'No audit activity yet',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  SizedBox(height: 6),
                  Text(
                    'Actions taken in your business will appear here.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: AppColors.textMuted),
                  ),
                ],
              ),
            );
          }

          return RefreshIndicator(
            onRefresh: _reload,
            child: ListView.separated(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
              itemCount: logs.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (context, index) {
                final log = logs[index];
                final deleted = log['actor_deleted'] == true;
                final actor = '${log['actor'] ?? 'Deleted Account'}';
                return Container(
                  padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _formatDate(log['created_at']),
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.textMuted,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        _formatAction('${log['action'] ?? ''}'),
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      if ('${log['description'] ?? ''}'.trim().isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          '${log['description']}',
                          style: const TextStyle(
                            fontSize: 13,
                            height: 1.4,
                            color: AppColors.textMuted,
                          ),
                        ),
                      ],
                      const SizedBox(height: 8),
                      Text(
                        actor,
                        style: TextStyle(
                          fontSize: 13,
                          fontStyle:
                              deleted ? FontStyle.italic : FontStyle.normal,
                          color: deleted
                              ? AppColors.textMuted
                              : AppColors.textBody,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
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
