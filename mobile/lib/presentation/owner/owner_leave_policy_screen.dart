import 'package:aroll_mobile/core/di/injection.dart';
import 'package:aroll_mobile/data/repositories/owner_repository.dart';
import 'package:aroll_mobile/presentation/owner/owner_shell.dart';
import 'package:aroll_mobile/presentation/owner/setup/setup_ui.dart';
import 'package:aroll_mobile/presentation/shared/app_ui.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

class OwnerLeavePolicyScreen extends StatefulWidget {
  const OwnerLeavePolicyScreen({super.key});

  @override
  State<OwnerLeavePolicyScreen> createState() => _OwnerLeavePolicyScreenState();
}

class _OwnerLeavePolicyScreenState extends State<OwnerLeavePolicyScreen> {
  final _repo = sl<OwnerRepository>();
  late Future<Map<String, dynamic>> _future;
  Map<String, bool> _draft = {};
  Map<String, bool> _saved = {};
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<Map<String, dynamic>> _load() async {
    final data = await _repo.leavePolicy();
    final items = (data['items'] as List? ?? const [])
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
    final next = <String, bool>{};
    for (final item in items) {
      next['${item['leave_type']}'] = item['is_paid'] == true;
    }
    _draft = Map<String, bool>.from(next);
    _saved = Map<String, bool>.from(next);
    return data;
  }

  bool get _dirty {
    if (_draft.length != _saved.length) return true;
    for (final entry in _draft.entries) {
      if (_saved[entry.key] != entry.value) return true;
    }
    return false;
  }

  Future<void> _save() async {
    if (_saving || !_dirty) return;
    setState(() => _saving = true);
    try {
      await _repo.updateLeavePolicy({'treatments': _draft});
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Leave Policy saved')),
      );
      setState(() {
        _future = _load();
      });
    } on DioException catch (error) {
      if (!mounted) return;
      final detail = error.response?.data is Map
          ? (error.response?.data as Map)['detail']
          : null;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            detail is String ? detail : 'Could not save Leave Policy.',
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return OwnerShell(
      selectedIndex: 2,
      showBackButton: true,
      title: 'Leave Policy',
      backgroundColor: SetupUi.scaffold,
      child: FutureBuilder<Map<String, dynamic>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting &&
              _draft.isEmpty) {
            return const Center(
              child: CircularProgressIndicator(color: SetupUi.navy),
            );
          }
          if (snapshot.hasError && _draft.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: SetupInfoBanner(
                  'Could not load Leave Policy.',
                  tone: SetupBannerTone.danger,
                ),
              ),
            );
          }
          final items = (snapshot.data?['items'] as List? ?? const [])
              .whereType<Map>()
              .map((item) => Map<String, dynamic>.from(item))
              .toList();

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
            children: [
              const SetupSurfaceCard(
                child: SetupSectionHeader(
                  icon: Icons.event_busy_outlined,
                  title: 'Leave Policy',
                  subtitle:
                      'Toggle each leave type as Paid or Unpaid. Employees do not choose this when requesting leave.',
                ),
              ),
              const SizedBox(height: 14),
              SetupSurfaceCard(
                padding: const EdgeInsets.fromLTRB(4, 4, 4, 4),
                child: Column(
                  children: [
                    for (var i = 0; i < items.length; i++) ...[
                      if (i > 0)
                        const Divider(
                          height: 1,
                          indent: 14,
                          endIndent: 14,
                          color: AppColors.border,
                        ),
                      _LeavePolicyToggleRow(
                        label: '${items[i]['leave_type_label']}',
                        paid: _draft['${items[i]['leave_type']}'] == true,
                        onChanged: (value) => setState(() {
                          _draft['${items[i]['leave_type']}'] = value;
                        }),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  style: SetupUi.primaryButton,
                  onPressed: !_dirty || _saving ? null : _save,
                  child: Text(_saving ? 'Saving…' : 'Save Leave Policy'),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _LeavePolicyToggleRow extends StatelessWidget {
  const _LeavePolicyToggleRow({
    required this.label,
    required this.paid,
    required this.onChanged,
  });

  final String label;
  final bool paid;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final statusColor =
        paid ? const Color(0xFF15803D) : const Color(0xFFB45309);
    final statusFill =
        paid ? const Color(0xFFDCFCE7) : const Color(0xFFFEF3C7);

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 6),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: statusFill,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    paid ? 'Paid' : 'Unpaid',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: statusColor,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Switch.adaptive(
            value: paid,
            activeThumbColor: const Color(0xFF16A34A),
            activeTrackColor: const Color(0xFF86EFAC),
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}
