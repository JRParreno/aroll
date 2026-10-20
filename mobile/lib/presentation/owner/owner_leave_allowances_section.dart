import 'package:aroll_mobile/core/di/injection.dart';
import 'package:aroll_mobile/data/repositories/owner_repository.dart';
import 'package:aroll_mobile/presentation/owner/setup/setup_ui.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class _AllowanceDraft {
  _AllowanceDraft({required this.enabled, required this.days});

  bool enabled;
  String days;
}

/// Shared owner Leave Allowances editor used by Leave Policy settings and setup.
class BusinessLeaveAllowancesSection extends StatefulWidget {
  const BusinessLeaveAllowancesSection({super.key});

  @override
  State<BusinessLeaveAllowancesSection> createState() =>
      _BusinessLeaveAllowancesSectionState();
}

class _BusinessLeaveAllowancesSectionState
    extends State<BusinessLeaveAllowancesSection> {
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
