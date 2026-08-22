import 'package:aroll_mobile/core/di/injection.dart';
import 'package:aroll_mobile/data/repositories/owner_repository.dart';
import 'package:aroll_mobile/presentation/employee/employee_ui.dart';
import 'package:aroll_mobile/presentation/owner/owner_shell.dart';
import 'package:aroll_mobile/presentation/shared/app_ui.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

/// Owner Mobile productivity page — presentation of existing
/// `GET /owner/performance` data (same source as Owner Web).
class OwnerProductivityScreen extends StatefulWidget {
  const OwnerProductivityScreen({super.key});

  @override
  State<OwnerProductivityScreen> createState() =>
      _OwnerProductivityScreenState();
}

class _OwnerProductivityScreenState extends State<OwnerProductivityScreen> {
  late int _month;
  late int _year;
  _ProductivityPageData? _data;
  bool _loading = true;
  bool _refreshing = false;
  Object? _error;
  bool _showAllEmployees = false;
  Map<String, String?> _profileImagesById = {};

  static const _rankColors = [
    Color(0xFF16A34A),
    Color(0xFF2563EB),
    Color(0xFFEA580C),
    Color(0xFF1E466E),
    Color(0xFF7C3AED),
  ];

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _month = now.month;
    _year = now.year;
    _load(initial: true);
  }

  Future<void> _load({bool initial = false}) async {
    setState(() {
      if (initial || _data == null) {
        _loading = true;
      } else {
        _refreshing = true;
      }
      _error = null;
    });
    try {
      final repo = sl<OwnerRepository>();
      final performance = await repo.performance(year: _year, month: _month);
      if (_profileImagesById.isEmpty) {
        final employees = await repo.employees();
        final images = <String, String?>{};
        for (final employee in employees) {
          final id = '${employee['id'] ?? ''}';
          if (id.isEmpty) continue;
          images[id] = employee['profile_image_url'] as String?;
        }
        _profileImagesById = images;
      }
      if (!mounted) return;
      setState(() {
        _data = _ProductivityPageData(
          performance: performance,
          profileImagesById: _profileImagesById,
        );
        _loading = false;
        _refreshing = false;
        _showAllEmployees = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error;
        _loading = false;
        _refreshing = false;
      });
    }
  }

  Future<void> _pickMonth() async {
    final selected = await showModalBottomSheet<int>(
      context: context,
      builder: (context) => _PickerSheet(
        title: 'Select month',
        options: [
          for (var m = 1; m <= 12; m++)
            _PickerOption(
              value: m,
              label: DateFormat.MMM().format(DateTime(2026, m)),
            ),
        ],
        selected: _month,
      ),
    );
    if (selected == null || selected == _month) return;
    setState(() => _month = selected);
    await _load();
  }

  Future<void> _pickYear() async {
    final nowYear = DateTime.now().year;
    final selected = await showModalBottomSheet<int>(
      context: context,
      builder: (context) => _PickerSheet(
        title: 'Select year',
        options: [
          for (var y = nowYear; y >= nowYear - 4; y--)
            _PickerOption(value: y, label: '$y'),
        ],
        selected: _year,
      ),
    );
    if (selected == null || selected == _year) return;
    setState(() => _year = selected);
    await _load();
  }

  String? _imageFor(Map<String, dynamic> employee) {
    final fromApi = employee['profile_image_url'] as String?;
    if (fromApi != null && fromApi.trim().isNotEmpty) return fromApi;
    final id = '${employee['employee_id'] ?? ''}';
    return _data?.profileImagesById[id];
  }

  @override
  Widget build(BuildContext context) {
    final periodLabel =
        DateFormat.yMMMM().format(DateTime(_year, _month));

    return OwnerShell(
      selectedIndex: 0,
      showBackButton: true,
      title: 'Productivity',
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  periodLabel,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF6B7280),
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Employee performance overview',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF111827),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _FilterChipButton(
                        label: DateFormat.MMM()
                            .format(DateTime(_year, _month)),
                        onTap: _refreshing ? null : _pickMonth,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _FilterChipButton(
                        label: '$_year',
                        onTap: _refreshing ? null : _pickYear,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (_refreshing)
            const LinearProgressIndicator(minHeight: 2)
          else
            const SizedBox(height: 2),
          Expanded(child: _buildBody()),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_loading && _data == null) {
      return appLoadingView(cardCount: 4);
    }
    if (_error != null && _data == null) {
      return const OwnerErrorState();
    }

    final data = _data!;
    final summary =
        data.performance['summary'] as Map<String, dynamic>? ?? const {};
    final employees =
        (data.performance['employees'] as List<dynamic>? ?? const [])
            .whereType<Map<String, dynamic>>()
            .toList();
    final hasData =
        summary['has_performance_data'] == true && employees.isNotEmpty;
    final visible = _showAllEmployees
        ? employees
        : employees.take(5).toList(growable: false);
    final topEmployee = hasData && employees.isNotEmpty ? employees.first : null;

    return RefreshIndicator(
      onRefresh: () => _load(),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          OwnerPerformanceChart(summary: summary),
          const SizedBox(height: 14),
          _StatsGrid(summary: summary, hasData: hasData),
          const SizedBox(height: 22),
          if (!hasData)
            const OwnerEmptyState(
              'No productivity data yet',
              description:
                  'Rankings will appear once your team has attendance activity for this period.',
              icon: Icons.insights_outlined,
            )
          else ...[
            if (topEmployee != null) ...[
              _EmployeeOfMonthCard(
                name: '${topEmployee['full_name'] ?? 'Employee'}',
                position: '${topEmployee['position_title'] ?? 'Team member'}',
                score: ownerParseInt(topEmployee['productivity_score']),
                imageUrl: _imageFor(topEmployee),
                reasons: (topEmployee['reasons'] as List<dynamic>? ?? const [])
                    .map((item) => '$item')
                    .where((item) => item.isNotEmpty)
                    .toList(),
              ),
              const SizedBox(height: 18),
            ],
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Top performing employees',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF111827),
                    ),
                  ),
                ),
                if (employees.length > 5)
                  TextButton(
                    onPressed: () => setState(
                      () => _showAllEmployees = !_showAllEmployees,
                    ),
                    style: TextButton.styleFrom(
                      foregroundColor: const Color(0xFF1E466E),
                      padding: EdgeInsets.zero,
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: Text(
                      _showAllEmployees
                          ? 'Show less'
                          : 'View all (${employees.length})',
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            ...List.generate(visible.length, (index) {
              final employee = visible[index];
              final color = _rankColors[index % _rankColors.length];
              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _TopPerformerCard(
                  rank: index + 1,
                  name: '${employee['full_name'] ?? 'Employee'}',
                  position: '${employee['position_title'] ?? 'Team member'}',
                  attendanceRate: ownerParseInt(employee['attendance_rate']),
                  score: ownerParseInt(employee['productivity_score']),
                  color: color,
                  imageUrl: _imageFor(employee),
                ),
              );
            }),
          ],
        ],
      ),
    );
  }
}

class _ProductivityPageData {
  const _ProductivityPageData({
    required this.performance,
    required this.profileImagesById,
  });

  final Map<String, dynamic> performance;
  final Map<String, String?> profileImagesById;
}

class _FilterChipButton extends StatelessWidget {
  const _FilterChipButton({
    required this.label,
    required this.onTap,
  });

  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFE5E7EB)),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                    color: Color(0xFF111827),
                  ),
                ),
              ),
              const Icon(
                Icons.keyboard_arrow_down_rounded,
                color: Color(0xFF6B7280),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatsGrid extends StatelessWidget {
  const _StatsGrid({
    required this.summary,
    required this.hasData,
  });

  final Map<String, dynamic> summary;
  final bool hasData;

  @override
  Widget build(BuildContext context) {
    final attendance = hasData
        ? '${ownerParseInt(summary['attendance_rate'])}%'
        : '—';
    final punctuality = hasData
        ? '${ownerParseInt(summary['punctuality_rate'])}%'
        : '—';
    final overtimeHours = summary['total_overtime_hours'];
    final overtimeLabel =
        hasData ? '${_formatHours(overtimeHours)} hrs' : '—';
    final score = hasData
        ? '${ownerParseInt(summary['productivity_score'])}/100'
        : '—';

    final cards = [
      (
        'Attendance',
        attendance,
        Icons.check_circle_outline_rounded,
        const Color(0xFF16A34A),
      ),
      (
        'Punctuality',
        punctuality,
        Icons.schedule_rounded,
        const Color(0xFF2563EB),
      ),
      (
        'Overtime',
        overtimeLabel,
        Icons.more_time_rounded,
        const Color(0xFFEA580C),
      ),
      (
        'Score',
        score,
        Icons.trending_up_rounded,
        const Color(0xFF1E466E),
      ),
    ];

    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _StatCard(
                label: cards[0].$1,
                value: cards[0].$2,
                icon: cards[0].$3,
                accent: cards[0].$4,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _StatCard(
                label: cards[1].$1,
                value: cards[1].$2,
                icon: cards[1].$3,
                accent: cards[1].$4,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: _StatCard(
                label: cards[2].$1,
                value: cards[2].$2,
                icon: cards[2].$3,
                accent: cards[2].$4,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _StatCard(
                label: cards[3].$1,
                value: cards[3].$2,
                icon: cards[3].$3,
                accent: cards[3].$4,
              ),
            ),
          ],
        ),
      ],
    );
  }

  static String _formatHours(Object? value) {
    if (value is num) {
      final v = value.toDouble();
      if ((v - v.round()).abs() < 0.05) return '${v.round()}';
      return v.toStringAsFixed(1);
    }
    return '0';
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.accent,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return OwnerCard(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF6B7280),
                  ),
                ),
              ),
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, size: 16, color: accent),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            value,
            style: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w800,
              color: Color(0xFF111827),
              height: 1.1,
            ),
          ),
        ],
      ),
    );
  }
}

class _TopPerformerCard extends StatelessWidget {
  const _TopPerformerCard({
    required this.rank,
    required this.name,
    required this.position,
    required this.attendanceRate,
    required this.score,
    required this.color,
    required this.imageUrl,
  });

  final int rank;
  final String name;
  final String position;
  final int attendanceRate;
  final int score;
  final Color color;
  final String? imageUrl;

  @override
  Widget build(BuildContext context) {
    final progress = (score.clamp(0, 100)) / 100.0;

    return OwnerCard(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          SizedBox(
            width: 28,
            child: Text(
              '$rank',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: color,
              ),
            ),
          ),
          EmployeeAvatar(imageUrl: imageUrl, name: name, size: 44),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF111827),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '$position · $attendanceRate% attendance',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    color: Color(0xFF6B7280),
                  ),
                ),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: LinearProgressIndicator(
                    value: progress,
                    minHeight: 5,
                    backgroundColor: const Color(0xFFF3F4F6),
                    color: color,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '$score',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: color,
                ),
              ),
              const Text(
                'score',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF9CA3AF),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _EmployeeOfMonthCard extends StatelessWidget {
  const _EmployeeOfMonthCard({
    required this.name,
    required this.position,
    required this.score,
    required this.imageUrl,
    required this.reasons,
  });

  final String name;
  final String position;
  final int score;
  final String? imageUrl;
  final List<String> reasons;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFFFF7E8), Color(0xFFFFFBEB)],
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFFDE68A)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 12,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Employee of the Month',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFFC2410C),
                  ),
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFFFEF3C7),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: const Text(
                  'Top score',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF92400E),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  EmployeeAvatar(imageUrl: imageUrl, name: name, size: 64),
                  Positioned(
                    right: -4,
                    bottom: -4,
                    child: Container(
                      width: 26,
                      height: 26,
                      decoration: BoxDecoration(
                        color: const Color(0xFFF59E0B),
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 2),
                      ),
                      child: const Icon(
                        Icons.emoji_events_rounded,
                        color: Colors.white,
                        size: 14,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF111827),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      position,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: Color(0xFF6B7280),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '$score% productive · top performer',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF15803D),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (reasons.isNotEmpty) ...[
            const SizedBox(height: 14),
            ...reasons.take(3).map(
                  (reason) => Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFFBEB),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: const Color(0xFFFDE68A)),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.star_rounded,
                            size: 16,
                            color: Color(0xFFF59E0B),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              reason,
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF92400E),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
          ],
        ],
      ),
    );
  }
}

class _PickerOption {
  const _PickerOption({required this.value, required this.label});

  final int value;
  final String label;
}

class _PickerSheet extends StatelessWidget {
  const _PickerSheet({
    required this.title,
    required this.options,
    required this.selected,
  });

  final String title;
  final List<_PickerOption> options;
  final int selected;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              title,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.sizeOf(context).height * 0.45,
              ),
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: options.length,
                itemBuilder: (context, index) {
                  final option = options[index];
                  final isSelected = option.value == selected;
                  return ListTile(
                    title: Text(option.label),
                    trailing: isSelected
                        ? const Icon(
                            Icons.check_rounded,
                            color: Color(0xFF1E466E),
                          )
                        : null,
                    onTap: () => Navigator.pop(context, option.value),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
