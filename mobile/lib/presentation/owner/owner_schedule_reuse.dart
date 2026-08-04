import 'package:aroll_mobile/data/repositories/owner_repository.dart';
import 'package:aroll_mobile/presentation/shared/app_ui.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

/// Blue selected-date banner with a minimal Schedule Library icon on the right.
/// Tapping the icon opens a floating panel over the schedule page.
class OwnerScheduleDateBanner extends StatefulWidget {
  const OwnerScheduleDateBanner({
    super.key,
    required this.date,
    required this.weekStart,
    required this.repo,
    required this.assignmentCount,
    required this.onApplied,
  });

  final DateTime date;
  final DateTime weekStart;
  final OwnerRepository repo;
  final int assignmentCount;
  final Future<void> Function() onApplied;

  @override
  State<OwnerScheduleDateBanner> createState() =>
      _OwnerScheduleDateBannerState();
}

class _OwnerScheduleDateBannerState extends State<OwnerScheduleDateBanner> {
  final OverlayPortalController _portal = OverlayPortalController();
  final LayerLink _link = LayerLink();

  Map<String, dynamic>? _suggestions;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _loadSuggestions();
  }

  @override
  void didUpdateWidget(covariant OwnerScheduleDateBanner oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.weekStart != widget.weekStart) {
      _loadSuggestions();
    }
  }

  Future<void> _loadSuggestions() async {
    try {
      final data = await widget.repo.scheduleReuseSuggestions(widget.weekStart);
      if (!mounted) return;
      setState(() => _suggestions = data);
    } catch (_) {
      if (!mounted) return;
      setState(() => _suggestions = null);
    }
  }

  void _toggleLibrary() {
    if (_portal.isShowing) {
      _portal.hide();
    } else {
      _portal.show();
    }
    setState(() {});
  }

  void _closeLibrary() {
    if (_portal.isShowing) {
      _portal.hide();
      setState(() {});
    }
  }

  String? _dioDetail(DioException error) {
    final data = error.response?.data;
    if (data is Map && data['detail'] is String) return data['detail'] as String;
    return null;
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _previewAndApply({
    required String source,
    String? templateId,
  }) async {
    _closeLibrary();
    setState(() => _busy = true);
    try {
      final preview = await widget.repo.previewScheduleReuse(
        source: source,
        targetWeekStart: widget.weekStart,
        templateId: templateId,
      );
      if (!mounted) return;
      final confirmed = await showDialog<Map<String, dynamic>>(
        context: context,
        builder: (context) => _PreviewDialog(preview: preview),
      );
      if (confirmed == null || !mounted) return;

      final result = await widget.repo.applyScheduleReuse(
        source: source,
        targetWeekStart: widget.weekStart,
        conflictMode: confirmed['conflict_mode'] as String,
        templateId: templateId,
      );
      final created = result['created'] as int? ?? 0;
      final removed = result['removed'] as int? ?? 0;
      final skipped = result['skipped'] as int? ?? 0;
      _toast(
        'Applied schedule: $created added'
        '${removed > 0 ? ', $removed replaced' : ''}'
        '${skipped > 0 ? ', $skipped skipped' : ''}',
      );
      await widget.onApplied();
      await _loadSuggestions();
    } on DioException catch (error) {
      _toast(_dioDetail(error) ?? 'Unable to reuse schedule');
    } catch (_) {
      _toast('Unable to reuse schedule');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _saveTemplate() async {
    _closeLibrary();
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Text('Save as template'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Save this week’s assignments so you can reuse them later.',
              style: appMutedStyle().copyWith(fontSize: 13),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              autofocus: true,
              decoration: InputDecoration(
                hintText: 'e.g. Regular Week',
                filled: true,
                fillColor: AppColors.fieldFill,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: AppColors.border),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: AppColors.border),
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            style: TextButton.styleFrom(foregroundColor: AppColors.primaryDark),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (name == null || name.isEmpty) return;
    setState(() => _busy = true);
    try {
      await widget.repo.createScheduleTemplate(
        name: name,
        weekStart: widget.weekStart,
      );
      _toast('Template saved');
      await _loadSuggestions();
    } on DioException catch (error) {
      _toast(_dioDetail(error) ?? 'Unable to save template');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _renameTemplate(String id, String currentName) async {
    final controller = TextEditingController(text: currentName);
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Text('Rename template'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(
            filled: true,
            fillColor: AppColors.fieldFill,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (name == null || name.isEmpty) return;
    try {
      await widget.repo.renameScheduleTemplate(templateId: id, name: name);
      _toast('Template renamed');
      await _loadSuggestions();
    } on DioException catch (error) {
      _toast(_dioDetail(error) ?? 'Unable to rename template');
    }
  }

  Future<void> _deleteTemplate(String id) async {
    try {
      await widget.repo.deleteScheduleTemplate(id);
      _toast('Template deleted');
      await _loadSuggestions();
    } on DioException catch (error) {
      _toast(_dioDetail(error) ?? 'Unable to delete template');
    }
  }

  @override
  Widget build(BuildContext context) {
    final open = _portal.isShowing;
    final suggestions = _suggestions;
    final templates = (suggestions?['templates'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .toList(growable: false);

    return OverlayPortal(
      controller: _portal,
      overlayChildBuilder: (context) {
        final width = MediaQuery.sizeOf(context).width;
        return Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _closeLibrary,
                child: const ColoredBox(color: Color(0x33000000)),
              ),
            ),
            CompositedTransformFollower(
              link: _link,
              showWhenUnlinked: false,
              targetAnchor: Alignment.bottomRight,
              followerAnchor: Alignment.topRight,
              offset: const Offset(0, 10),
              child: Material(
                color: Colors.transparent,
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: (width - 32).clamp(260.0, 340.0),
                    maxHeight: MediaQuery.sizeOf(context).height * 0.62,
                  ),
                  child: _LibraryFloatCard(
                    busy: _busy,
                    suggestions: suggestions,
                    templates: templates,
                    canSave: widget.assignmentCount > 0,
                    suggestPrevious: suggestions?['suggest_previous'] == true &&
                        widget.assignmentCount == 0,
                    onCopyPreviousWeek: () =>
                        _previewAndApply(source: 'previous_week'),
                    onUseLastSchedule: () =>
                        _previewAndApply(source: 'last_schedule'),
                    onSaveTemplate: _saveTemplate,
                    onApplyTemplate: (id) =>
                        _previewAndApply(source: 'template', templateId: id),
                    onRenameTemplate: _renameTemplate,
                    onDeleteTemplate: _deleteTemplate,
                  ),
                ),
              ),
            ),
          ],
        );
      },
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [AppColors.primary, AppColors.primaryDark],
          ),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.16),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(
                Icons.calendar_today_rounded,
                color: Colors.white,
                size: 18,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Selected date',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.78),
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    DateFormat('EEEE, MMM d').format(widget.date),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
            CompositedTransformTarget(
              link: _link,
              child: Tooltip(
                message: 'Schedule Library',
                child: Material(
                  color: Colors.white.withValues(alpha: open ? 0.28 : 0.16),
                  borderRadius: BorderRadius.circular(12),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: _busy ? null : _toggleLibrary,
                    child: const SizedBox(
                      width: 40,
                      height: 40,
                      child: Icon(
                        Icons.folder_copy_outlined,
                        color: Colors.white,
                        size: 20,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LibraryFloatCard extends StatelessWidget {
  const _LibraryFloatCard({
    required this.busy,
    required this.suggestions,
    required this.templates,
    required this.canSave,
    required this.suggestPrevious,
    required this.onCopyPreviousWeek,
    required this.onUseLastSchedule,
    required this.onSaveTemplate,
    required this.onApplyTemplate,
    required this.onRenameTemplate,
    required this.onDeleteTemplate,
  });

  final bool busy;
  final Map<String, dynamic>? suggestions;
  final List<Map<String, dynamic>> templates;
  final bool canSave;
  final bool suggestPrevious;
  final VoidCallback onCopyPreviousWeek;
  final VoidCallback onUseLastSchedule;
  final VoidCallback onSaveTemplate;
  final void Function(String id) onApplyTemplate;
  final Future<void> Function(String id, String name) onRenameTemplate;
  final Future<void> Function(String id) onDeleteTemplate;

  @override
  Widget build(BuildContext context) {
    final hasPrevious = suggestions?['previous_week_start'] != null;
    final hasLast = suggestions?['last_schedule_week_start'] != null;

    return Container(
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.12),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 8),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: AppColors.iconWell,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.folder_copy_outlined,
                    color: AppColors.primary,
                    size: 18,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Schedule Library', style: appSectionTitleStyle()),
                      Text(
                        'Reuse a past week or a saved template',
                        style: appMutedStyle().copyWith(fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (suggestPrevious)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: AppColors.iconWell,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  'Tip: this week is empty. Copy last week to get started.',
                  style: appMutedStyle().copyWith(
                    fontSize: 12,
                    color: AppColors.primaryDark,
                  ),
                ),
              ),
            ),
          const Divider(height: 1),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 320),
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.symmetric(vertical: 6),
              children: [
                _LibraryAction(
                  icon: Icons.copy_all_rounded,
                  title: 'Copy previous week',
                  subtitle: hasPrevious
                      ? '${suggestions?['previous_week_assignment_count']} assignments'
                      : 'Nothing to copy',
                  enabled: !busy && hasPrevious,
                  onTap: onCopyPreviousWeek,
                ),
                _LibraryAction(
                  icon: Icons.history_rounded,
                  title: 'Use last schedule',
                  subtitle: hasLast
                      ? 'Week of ${suggestions?['last_schedule_week_start']}'
                      : 'No previous schedule',
                  enabled: !busy && hasLast,
                  onTap: onUseLastSchedule,
                ),
                _LibraryAction(
                  icon: Icons.save_outlined,
                  title: 'Save this week',
                  subtitle: canSave
                      ? 'Save as a reusable template'
                      : 'Assign someone first',
                  enabled: !busy && canSave,
                  onTap: onSaveTemplate,
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 10, 14, 4),
                  child: Text(
                    'Saved templates',
                    style: appMutedStyle().copyWith(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.3,
                    ),
                  ),
                ),
                if (templates.isEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(14, 4, 14, 12),
                    child: Text(
                      'No templates yet.',
                      style: appMutedStyle().copyWith(fontSize: 13),
                    ),
                  )
                else
                  ...templates.map((template) {
                    final id = '${template['id']}';
                    return _LibraryAction(
                      icon: Icons.event_note_outlined,
                      title: '${template['name']}',
                      subtitle:
                          '${template['entry_count']} assignments · '
                          '${template['employee_count']} employees',
                      enabled: !busy,
                      onTap: () => onApplyTemplate(id),
                      trailing: PopupMenuButton<String>(
                        icon: const Icon(
                          Icons.more_horiz_rounded,
                          color: AppColors.textMuted,
                        ),
                        onSelected: (value) async {
                          if (value == 'rename') {
                            await onRenameTemplate(id, '${template['name']}');
                          } else if (value == 'delete') {
                            await onDeleteTemplate(id);
                          }
                        },
                        itemBuilder: (_) => const [
                          PopupMenuItem(
                            value: 'rename',
                            child: Text('Rename'),
                          ),
                          PopupMenuItem(
                            value: 'delete',
                            child: Text('Delete'),
                          ),
                        ],
                      ),
                    );
                  }),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _LibraryAction extends StatelessWidget {
  const _LibraryAction({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.enabled,
    required this.onTap,
    this.trailing,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool enabled;
  final VoidCallback onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: enabled ? onTap : null,
      child: Opacity(
        opacity: enabled ? 1 : 0.45,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: AppColors.iconWell,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, size: 18, color: AppColors.primary),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    Text(
                      subtitle,
                      style: appMutedStyle().copyWith(fontSize: 12),
                    ),
                  ],
                ),
              ),
              if (trailing != null)
                trailing!
              else
                const Icon(
                  Icons.chevron_right_rounded,
                  color: AppColors.textMuted,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PreviewDialog extends StatefulWidget {
  const _PreviewDialog({required this.preview});

  final Map<String, dynamic> preview;

  @override
  State<_PreviewDialog> createState() => _PreviewDialogState();
}

class _PreviewDialogState extends State<_PreviewDialog> {
  String _conflictMode = 'merge';

  @override
  Widget build(BuildContext context) {
    final preview = widget.preview;
    final conflicts =
        (preview['conflicts'] as Map<String, dynamic>?) ?? const {};
    final items = (preview['items'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .toList(growable: false);
    final existing = conflicts['existing_assignment_count'] as int? ?? 0;
    final conflictCount = conflicts['conflict_count'] as int? ?? 0;
    final duplicates = conflicts['duplicate_count'] as int? ?? 0;
    final creatable = conflicts['creatable_count'] as int? ?? 0;
    final hasConflicts = existing > 0 || conflictCount > 0 || duplicates > 0;

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420, maxHeight: 560),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Preview before applying', style: appSectionTitleStyle()),
                  const SizedBox(height: 6),
                  Text(
                    '${preview['source_label']} → '
                    '${preview['target_week_start']} to '
                    '${preview['target_week_end']}',
                    style: appMutedStyle().copyWith(fontSize: 12),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${preview['employee_count']} employees · '
                    '${preview['working_day_count']} working days',
                    style: appMutedStyle().copyWith(fontSize: 12),
                  ),
                  if (hasConflicts) ...[
                    const SizedBox(height: 10),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFFBEB),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFFFDE68A)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'This week already has schedules. '
                            'Existing $existing · conflicts $conflictCount · '
                            'can add $creatable',
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF78350F),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            children: [
                              ChoiceChip(
                                label: const Text('Keep & add'),
                                selected: _conflictMode == 'merge',
                                onSelected: (_) =>
                                    setState(() => _conflictMode = 'merge'),
                              ),
                              ChoiceChip(
                                label: const Text('Replace week'),
                                selected: _conflictMode == 'replace',
                                onSelected: (_) =>
                                    setState(() => _conflictMode = 'replace'),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                itemCount: items.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final item = items[index];
                  final status = '${item['status']}';
                  final reason = item['conflict_reason'] as String?;
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    title: Text(
                      '${item['employee_name']}',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    subtitle: Text(
                      '${item['shift_name']} · ${item['work_date']}'
                      '${item['is_rest_day_work'] == true ? ' · rest day' : ''}',
                    ),
                    trailing: Text(
                      status == 'new' ? 'Will add' : (reason ?? status),
                      style: TextStyle(
                        fontSize: 11,
                        color: status == 'new'
                            ? AppColors.success
                            : AppColors.warning,
                      ),
                    ),
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.primaryDark,
                      ),
                      onPressed: () => Navigator.pop(context, {
                        'conflict_mode': _conflictMode,
                      }),
                      child: const Text('Apply'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
