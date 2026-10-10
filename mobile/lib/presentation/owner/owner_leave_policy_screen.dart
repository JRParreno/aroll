import 'package:aroll_mobile/core/di/injection.dart';
import 'package:aroll_mobile/data/repositories/owner_repository.dart';
import 'package:aroll_mobile/presentation/owner/owner_shell.dart';
import 'package:aroll_mobile/presentation/owner/setup/setup_ui.dart';
import 'package:aroll_mobile/presentation/shared/app_ui.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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
  final _notice = TextEditingController(text: '0');
  int _savedNotice = 0;
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
    final notice = data['minimum_advance_notice_days'] as int? ?? 0;
    _savedNotice = notice;
    _notice.text = '$notice';
    return data;
  }

  bool get _dirty {
    if (_draft.length != _saved.length) return true;
    for (final entry in _draft.entries) {
      if (_saved[entry.key] != entry.value) return true;
    }
    return false;
  }

  bool get _noticeDirty => int.tryParse(_notice.text.trim()) != _savedNotice;

  @override
  void dispose() {
    _notice.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving || (!_dirty && !_noticeDirty)) return;
    final notice = int.tryParse(_notice.text.trim());
    if (notice == null || notice < 0 || notice > 365) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Advance notice must be a whole number from 0 to 365.'),
        ),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      await _repo.updateLeavePolicy({
        'treatments': {
          for (final entry in _draft.entries)
            if (entry.key != 'unpaid') entry.key: entry.value,
        },
        'minimum_advance_notice_days': notice,
      });
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
            return Center(
              child: CircularProgressIndicator(color: SetupUi.navyOf(context)),
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
              .where((item) => item['leave_type'] != 'unpaid')
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
              SetupSurfaceCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Minimum advance notice',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 15,
                        color: Color(0xFF111827),
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Calendar days before the leave start date. 0 means no minimum. This applies to every leave type.',
                      style: TextStyle(
                        fontSize: 12,
                        color: Color(0xFF6B7280),
                        height: 1.35,
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: _notice,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        isDense: true,
                        suffixText: 'days',
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  style: SetupUi.primaryButtonOf(context).copyWith(
                    textStyle: const WidgetStatePropertyAll(
                      TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                    ),
                  ),
                  onPressed: (!_dirty && !_noticeDirty) || _saving ? null : _save,
                  child: Text(_saving ? 'Saving…' : 'Save Leave Policy'),
                ),
              ),
              const SizedBox(height: 16),
              const _BusinessLeaveAllowances(),
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
                    fontWeight: FontWeight.w500,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 6),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: statusFill,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    paid ? 'Paid' : 'Unpaid',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
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

class _AllowanceDraft {
  _AllowanceDraft({required this.enabled, required this.days});

  bool enabled;
  String days;
}

class _BusinessLeaveAllowances extends StatefulWidget {
  const _BusinessLeaveAllowances();

  @override
  State<_BusinessLeaveAllowances> createState() =>
      _BusinessLeaveAllowancesState();
}

class _BusinessLeaveAllowancesState extends State<_BusinessLeaveAllowances> {
  final _repo = sl<OwnerRepository>();
  int _year = DateTime.now().year;
  List<Map<String, dynamic>> _items = const [];
  final Map<String, _AllowanceDraft> _draft = {};
  bool _loading = true;
  bool _saving = false;
  String? _error;

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
      final data = await _repo.leaveAllowances(year: _year);
      final items = (data['items'] as List? ?? const [])
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList();
      _draft.clear();
      for (final item in items) {
        final type = '${item['leave_type']}';
        final days = item['allowance_days'];
        _draft[type] = _AllowanceDraft(
          enabled: item['enabled'] == true,
          days: days == null ? '' : '$days',
        );
      }
      if (!mounted) return;
      setState(() {
        _items = items;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Could not load leave allowances.';
      });
    }
  }

  List<Map<String, dynamic>> get _configurableItems => [
        for (final item in _items)
          if (item['leave_type'] != 'unpaid') item,
      ];

  bool get _invalid {
    for (final item in _configurableItems) {
      final row = _draft['${item['leave_type']}'];
      if (row == null || !row.enabled) continue;
      final value = int.tryParse(row.days.trim());
      if (value == null || value < 0 || value > 366) return true;
    }
    return false;
  }

  Future<void> _save() async {
    if (_saving || _invalid) return;
    setState(() => _saving = true);
    try {
      await _repo.updateLeaveAllowances({
        'year': _year,
        'items': [
          for (final item in _configurableItems)
            {
              'leave_type': item['leave_type'],
              'enabled': _draft['${item['leave_type']}']?.enabled ?? false,
              'allowance_days': () {
                final row = _draft['${item['leave_type']}'];
                if (row == null || !row.enabled) return null;
                return int.parse(row.days.trim());
              }(),
            },
        ],
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Leave allowances saved')),
      );
      await _load();
    } on DioException catch (error) {
      if (!mounted) return;
      final detail = error.response?.data is Map
          ? (error.response?.data as Map)['detail']
          : null;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            detail is String ? detail : 'Could not save leave allowances.',
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SetupSurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Leave Allowances',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 15,
                    color: Color(0xFF111827),
                  ),
                ),
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                onPressed: _saving
                    ? null
                    : () {
                        setState(() => _year -= 1);
                        _load();
                      },
                icon: const Icon(Icons.chevron_left),
              ),
              Text('$_year', style: const TextStyle(fontWeight: FontWeight.w500)),
              IconButton(
                visualDensity: VisualDensity.compact,
                onPressed: _saving
                    ? null
                    : () {
                        setState(() => _year += 1);
                        _load();
                      },
                icon: const Icon(Icons.chevron_right),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'These days apply to every employee for $_year. Available off means employees cannot request that leave type.',
            style: const TextStyle(
              fontSize: 12,
              color: Color(0xFF6B7280),
              height: 1.35,
            ),
          ),
          const SizedBox(height: 8),
          if (_loading)
            const Text(
              'Loading allowances…',
              style: TextStyle(fontSize: 13, color: Color(0xFF6B7280)),
            )
          else if (_error != null)
            Text(_error!, style: const TextStyle(color: Color(0xFFB91C1C)))
          else
            for (final item in _configurableItems) ...[
              const Divider(height: 16),
              _AllowanceEditor(
                key: ValueKey('${item['leave_type']}-$_year'),
                label: '${item['leave_type_label']}',
                draft: _draft['${item['leave_type']}']!,
                onChanged: () => setState(() {}),
              ),
            ],
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              style: SetupUi.primaryButtonOf(context).copyWith(
                textStyle: const WidgetStatePropertyAll(
                  TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                ),
              ),
              onPressed: _loading || _saving || _invalid ? null : _save,
              child: Text(_saving ? 'Saving…' : 'Save Allowances'),
            ),
          ),
        ],
      ),
    );
  }
}

class _AllowanceEditor extends StatefulWidget {
  const _AllowanceEditor({
    super.key,
    required this.label,
    required this.draft,
    required this.onChanged,
  });

  final String label;
  final _AllowanceDraft draft;
  final VoidCallback onChanged;

  @override
  State<_AllowanceEditor> createState() => _AllowanceEditorState();
}

class _AllowanceEditorState extends State<_AllowanceEditor> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(
      text: widget.draft.enabled ? widget.draft.days : '',
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                widget.label,
                style: const TextStyle(
                  fontWeight: FontWeight.w500,
                  fontSize: 14,
                  color: Color(0xFF111827),
                ),
              ),
            ),
            const Text(
              'Available',
              style: TextStyle(fontSize: 12, color: Color(0xFF6B7280)),
            ),
            Switch.adaptive(
              value: widget.draft.enabled,
              onChanged: (value) {
                widget.draft.enabled = value;
                if (!value) {
                  widget.draft.days = '';
                  _controller.text = '';
                }
                widget.onChanged();
              },
            ),
          ],
        ),
        const Text(
          'Allowance Days',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: Color(0xFF6B7280),
          ),
        ),
        const SizedBox(height: 4),
        TextField(
          enabled: widget.draft.enabled,
          controller: _controller,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          onChanged: (value) {
            widget.draft.days = value;
            widget.onChanged();
          },
          decoration: InputDecoration(
            isDense: true,
            hintText: widget.draft.enabled ? 'Set allowance' : '—',
            border: const OutlineInputBorder(),
          ),
        ),
      ],
    );
  }
}
