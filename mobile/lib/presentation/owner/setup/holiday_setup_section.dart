import 'package:aroll_mobile/core/di/injection.dart';
import 'package:aroll_mobile/data/repositories/owner_repository.dart';
import 'package:aroll_mobile/presentation/owner/setup/holiday_management_copy.dart';
import 'package:aroll_mobile/presentation/owner/setup/holiday_ot_premium.dart';
import 'package:aroll_mobile/presentation/owner/setup/setup_ui.dart';
import 'package:aroll_mobile/presentation/owner/setup/setup_wizard_constants.dart';
import 'package:aroll_mobile/presentation/shared/app_ui.dart';
import 'package:aroll_mobile/presentation/shared/confirm_action_dialog.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

enum _HolidayArea { holidays, rules, help }

String _formatHolidayDate(String raw, {bool long = false}) {
  final parsed = DateTime.tryParse(raw);
  if (parsed == null) return raw.isEmpty ? '--' : raw;
  return DateFormat(long ? 'MMMM d, yyyy' : 'MMM d, yyyy').format(parsed);
}

class HolidaySetupSection extends StatefulWidget {
  const HolidaySetupSection({
    super.key,
    required this.onChanged,
  });

  final VoidCallback onChanged;

  @override
  State<HolidaySetupSection> createState() => _HolidaySetupSectionState();
}

class _HolidaySetupSectionState extends State<HolidaySetupSection> {
  static const _fieldGap = SetupUi.fieldGap;

  final _repo = sl<OwnerRepository>();
  final _nameController = TextEditingController();
  final _multiplierController = TextEditingController(text: '1.0');
  final _otPremiumController = TextEditingController();

  List<Map<String, dynamic>> _holidays = const [];
  String _rulesMode = 'philippine_labor';
  Map<String, dynamic>? _payroll;
  bool _loading = true;
  bool _error = false;
  bool _seedAttempted = false;
  bool _busy = false;
  String? _togglingId;
  bool _showAdd = false;
  bool _advancedOpen = false;
  bool _rulesLearnMore = false;
  String? _editingId;
  double _bulkMultiplier = 1.0;
  String _bulkOt = '';
  String? _helpOpenTitle;
  DateTime? _customDate;
  bool _customIsPaid = true;
  _HolidayArea _area = _HolidayArea.holidays;

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _multiplierController.dispose();
    _otPremiumController.dispose();
    super.dispose();
  }

  InputDecoration _compactInput(String label, {String? hint}) =>
      SetupUi.input(label, hint: hint);

  Future<void> _loadAll() async {
    setState(() {
      _loading = true;
      _error = false;
    });
    try {
      final results = await Future.wait([
        _repo.holidays(includeInactive: true),
        _repo.payrollConfig(),
      ]);
      if (!mounted) return;
      final holidays = results[0] as List<Map<String, dynamic>>;
      final payroll = results[1] as Map<String, dynamic>;
      setState(() {
        _holidays = holidays;
        _payroll = payroll;
        _rulesMode = payroll['holiday_rules_mode'] == 'custom_company'
            ? 'custom_company'
            : 'philippine_labor';
        _loading = false;
      });
      if (holidays.isEmpty && !_seedAttempted) {
        _seedAttempted = true;
        await _seedDefaults(showEmptyToast: false);
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = true;
      });
    }
  }

  Future<void> _seedDefaults({bool showEmptyToast = true}) async {
    setState(() => _busy = true);
    try {
      final created = await _repo.seedDefaultHolidays();
      if (!mounted) return;
      if (showEmptyToast && created.isNotEmpty) {
        _showSnack('Loaded ${created.length} Philippine holidays');
      }
      widget.onChanged();
      await _loadAll();
    } catch (_) {
      if (mounted) _showSnack('Could not load default holidays');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _updateHoliday(String id, Map<String, dynamic> payload) async {
    setState(() => _busy = true);
    try {
      await _repo.updateHoliday(id, payload);
      widget.onChanged();
      await _loadAll();
      if (mounted) _showSnack('Holiday updated');
    } on DioException catch (error) {
      if (mounted) {
        _showSnack(_dioMessage(error) ?? 'Could not update holiday');
      }
    } catch (_) {
      if (mounted) _showSnack('Could not update holiday');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _applyPayDefaults() async {
    if (_holidays.isEmpty) return;
    if (_bulkMultiplier <= 0) {
      _showSnack('Holiday Pay Rate must be greater than 0%');
      return;
    }
    if (isHolidayOtPremiumInvalid(_bulkOt)) {
      _showSnack('Holiday OT Premium must be 0 or greater, or left blank');
      return;
    }
    setState(() => _busy = true);
    try {
      final otPremium = parseHolidayOtPremium(_bulkOt);
      for (final holiday in _holidays) {
        await _repo.updateHoliday('${holiday['id']}', {
          'pay_multiplier': _bulkMultiplier,
          'ot_premium_percent': otPremium,
        });
      }
      widget.onChanged();
      await _loadAll();
      if (mounted) _showSnack('Holiday updated');
    } on DioException catch (error) {
      if (mounted) {
        _showSnack(_dioMessage(error) ?? 'Could not update holiday');
      }
      await _loadAll();
    } catch (_) {
      if (mounted) _showSnack('Could not update holiday');
      await _loadAll();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _setActive(String id, bool next) async {
    final previous = _holidays;
    setState(() {
      _togglingId = id;
      _holidays = [
        for (final holiday in _holidays)
          if ('${holiday['id']}' == id)
            {...holiday, 'is_active': next}
          else
            holiday,
      ];
    });
    try {
      final updated = await _repo.updateHoliday(id, {'is_active': next});
      if (!mounted) return;
      setState(() {
        _holidays = [
          for (final holiday in _holidays)
            if ('${holiday['id']}' == id) updated else holiday,
        ];
      });
      widget.onChanged();
    } catch (_) {
      if (!mounted) return;
      setState(() => _holidays = previous);
      _showSnack('Could not update holiday');
    } finally {
      if (mounted) setState(() => _togglingId = null);
    }
  }

  Future<void> _saveRulesMode(String mode) async {
    final payroll = _payroll;
    if (payroll == null) return;
    setState(() => _busy = true);
    try {
      await _repo.updatePayrollConfig({
        ...payroll,
        'holiday_rules_mode': mode,
      });
      widget.onChanged();
      await _loadAll();
      if (mounted) _showSnack('Holiday rules updated');
    } catch (_) {
      if (mounted) _showSnack('Could not update holiday rules');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _addCustomHoliday() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      _showSnack('Please enter a holiday name');
      return;
    }
    if (_customDate == null) {
      _showSnack('Please choose a date');
      return;
    }
    final multiplier = double.tryParse(_multiplierController.text.trim()) ?? 0;
    if (multiplier <= 0) {
      _showSnack('Holiday Pay Rate must be greater than 0%');
      return;
    }
    if (isHolidayOtPremiumInvalid(_otPremiumController.text)) {
      _showSnack('Holiday OT Premium must be 0 or greater, or left blank');
      return;
    }

    final dateStr = formatApiDate(_customDate!);
    final dup = findDuplicateActiveHoliday(
      holidays: _holidays,
      holidayDate: dateStr,
    );
    if (dup != null) {
      final proceed = await showDialog<bool>(
        context: context,
        builder: (context) => ConfirmActionDialog(
          icon: Icons.warning_amber_rounded,
          title: 'Another holiday exists on this date',
          message:
              'Another active holiday already exists on this date: ${dup.name} (${holidayTypeLabel(dup.holidayType)}). You can still save, but payroll uses one holiday record per date.',
          confirmLabel: 'Add anyway',
        ),
      );
      if (proceed != true) return;
    }

    setState(() => _busy = true);
    try {
      await _repo.createHoliday(
        name: name,
        holidayDate: dateStr,
        isPaid: _customIsPaid,
        payMultiplier: multiplier,
        otPremiumPercent: parseHolidayOtPremium(_otPremiumController.text),
      );
      _nameController.clear();
      _multiplierController.text = '1.0';
      _otPremiumController.clear();
      _customDate = null;
      _customIsPaid = true;
      _advancedOpen = false;
      _showAdd = false;
      widget.onChanged();
      await _loadAll();
    } on DioException catch (error) {
      if (mounted) {
        _showSnack(_dioMessage(error) ?? 'Could not add holiday');
      }
    } catch (_) {
      if (mounted) _showSnack('Could not add holiday');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _openHolidayPayEditor(Map<String, dynamic> holiday) async {
    setState(() {
      _editingId = '${holiday['id']}';
      _showAdd = false;
    });
    final payload = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => _HolidayPayEditorDialog(
        holiday: holiday,
        rulesMode: _rulesMode,
      ),
    );
    if (!mounted) return;
    setState(() => _editingId = null);
    if (payload == null) return;
    await _updateHoliday('${holiday['id']}', payload);
  }

  String? _dioMessage(DioException error) {
    final data = error.response?.data;
    if (data is Map && data['detail'] is String) {
      return data['detail'] as String;
    }
    return null;
  }

  Future<void> _pickCustomDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _customDate ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (picked != null) setState(() => _customDate = picked);
  }

  List<Map<String, dynamic>> _byType(String type) => _holidays
      .where((h) => h['holiday_type'] == type)
      .toList()
    ..sort((a, b) => '${a['holiday_date']}'.compareTo('${b['holiday_date']}'));

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildAreaTabs(),
        const SizedBox(height: _fieldGap),
        if (_area == _HolidayArea.holidays) ..._buildHolidaysArea(),
        if (_area == _HolidayArea.rules) ..._buildRulesArea(),
        if (_area == _HolidayArea.help) ..._buildHelpArea(),
      ],
    );
  }

  Widget _buildAreaTabs() {
    Widget chip(_HolidayArea area, String label) {
      final selected = _area == area;
      return Expanded(
        child: InkWell(
          onTap: () => setState(() {
            _area = area;
            _showAdd = false;
            _editingId = null;
          }),
          borderRadius: BorderRadius.circular(10),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
            decoration: BoxDecoration(
              color: selected ? Colors.white : Colors.transparent,
              borderRadius: BorderRadius.circular(10),
              boxShadow: selected
                  ? [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.04),
                        blurRadius: 4,
                        offset: const Offset(0, 1),
                      ),
                    ]
                  : null,
            ),
            child: Text(
              label,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: selected ? SetupUi.navyOf(context) : AppColors.textMuted,
              ),
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          chip(_HolidayArea.holidays, HolidayTerms.holidays),
          chip(_HolidayArea.rules, HolidayTerms.holidayRules),
          chip(_HolidayArea.help, 'How it works'),
        ],
      ),
    );
  }

  List<Widget> _buildHolidaysArea() {
    final regular = _byType('regular');
    final special = _byType('special_non_working');
    final company = _byType('company');

    return [
      Row(
        children: [
          Expanded(
            child: Text(
              'Turn a holiday off to keep it out of schedules and pay. It stays in this list.',
              style: appMutedStyle().copyWith(fontSize: 12.5, height: 1.35),
            ),
          ),
          FilledButton(
            onPressed: _busy
                ? null
                : () => setState(() {
                      _showAdd = true;
                      _editingId = null;
                    }),
            style: SetupUi.primaryButtonOf(context),
            child: const Text('Add'),
          ),
        ],
      ),
      const SizedBox(height: _fieldGap),
      if (_loading)
        Text('Loading holidays…', style: appMutedStyle().copyWith(fontSize: 12)),
      if (_error)
        const SetupInfoBanner(
          'Unable to load holidays. Please try again.',
          tone: SetupBannerTone.danger,
        ),
      if (_showAdd) ...[
        _buildAddEditor(),
        const SizedBox(height: _fieldGap),
      ],
      if (!_loading && !_error) ...[
        _buildPayDefaults(),
        const SizedBox(height: _fieldGap),
      ],
      if (!_loading) ...[
        if (regular.isNotEmpty) ...[
          _groupLabel('Regular Holidays'),
          ...regular.map(_buildCompactCard),
        ],
        if (special.isNotEmpty) ...[
          _groupLabel('Special Non-Working Days'),
          ...special.map(_buildCompactCard),
        ],
        if (company.isNotEmpty) ...[
          _groupLabel('Company Holidays'),
          ...company.map(_buildCompactCard),
        ],
        if (regular.isEmpty && special.isEmpty && company.isEmpty && !_showAdd)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.border),
              color: const Color(0xFFFAFBFC),
            ),
            child: Text(
              'No holidays yet.',
              textAlign: TextAlign.center,
              style: appMutedStyle().copyWith(fontSize: 13),
            ),
          ),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton(
            style: SetupUi.secondaryButtonOf(context),
            onPressed: _busy ? null : () => _seedDefaults(),
            child: const Text('Load Philippine holidays'),
          ),
        ),
      ],
    ];
  }

  Widget _buildPayDefaults() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Holiday Pay Defaults',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          _HolidayPayRateControls(
            multiplier: _bulkMultiplier,
            enabled: !_busy,
            onMultiplierChanged: (next) => setState(() => _bulkMultiplier = next),
          ),
          const SizedBox(height: 8),
          _HolidayOtPremiumControls(
            valueRaw: _bulkOt,
            enabled: !_busy,
            onChanged: (value) => setState(() => _bulkOt = value),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              style: SetupUi.primaryButtonOf(context),
              onPressed: _busy || _holidays.isEmpty ? null : _applyPayDefaults,
              child: const Text('Apply to all holidays'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _groupLabel(String title) => Padding(
        padding: const EdgeInsets.only(top: 6, bottom: 6),
        child: Text(
          title,
          style: appMutedStyle().copyWith(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.5,
          ),
        ),
      );

  Widget _buildCompactCard(Map<String, dynamic> holiday) {
    final id = '${holiday['id']}';
    final type = '${holiday['holiday_type']}';
    final name = '${holiday['name']}';
    final active = holiday['is_active'] != false;
    final selected = _editingId == id;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 10, 4, 10),
      decoration: BoxDecoration(
        color: active ? Colors.white : const Color(0xFFF7F8FA),
        borderRadius: BorderRadius.circular(SetupUi.cardRadius),
        border: Border.all(
          color: active ? AppColors.border : const Color(0xFFE5E7EB),
        ),
      ),
      child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                          color: selected
                              ? SetupUi.navyOf(context)
                              : (active
                                  ? AppColors.textPrimary
                                  : const Color(0xFF4B5563)),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${holidayTypeLabel(type)} · ${_formatHolidayDate('${holiday['holiday_date']}')}',
                        style: appMutedStyle().copyWith(fontSize: 12),
                      ),
                    ],
                  ),
                ),
                _HolidayActiveSwitch(
                  value: active,
                  semanticLabel: active ? 'Turn $name off' : 'Turn $name on',
                  onChanged: _togglingId == id
                      ? null
                      : (next) => _setActive(id, next),
                ),
                IconButton(
                  tooltip: HolidayTerms.editHolidayPay,
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints.tightFor(
                    width: 32,
                    height: 32,
                  ),
                  onPressed: () => _openHolidayPayEditor(holiday),
                  icon: const Icon(Icons.edit_outlined, size: 18),
                  color: SetupUi.navyOf(context),
                ),
              ],
            ),
          ],
        ),
    );
  }

  Widget _buildAddEditor() {
    final multiplier =
        double.tryParse(_multiplierController.text.trim()) ?? 1.0;
    final unworked = unworkedRulePresentation(
      mode: _rulesMode,
      holidayType: 'company',
      isPaid: _customIsPaid,
    );
    final dateStr =
        _customDate == null ? '' : formatApiDate(_customDate!);
    final dup = findDuplicateActiveHoliday(
      holidays: _holidays,
      holidayDate: dateStr,
    );
    final summary = buildRuleSummary(
      name: _nameController.text,
      holidayType: 'company',
      mode: _rulesMode,
      isPaid: _customIsPaid,
      payMultiplier: multiplier,
      otPremiumRaw: _otPremiumController.text,
    );

    return SetupPanel(
      title: 'Add company holiday',
      icon: Icons.add_circle_outline_rounded,
      subtitle: 'Basic details first. Advanced notes stay collapsed.',
      children: [
        TextField(
          controller: _nameController,
          style: const TextStyle(fontSize: 14),
          decoration: _compactInput('Holiday name'),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: _fieldGap),
        OutlinedButton(
          style: SetupUi.secondaryButtonOf(context),
          onPressed: _pickCustomDate,
          child: Text(_customDate == null ? 'Choose holiday date' : dateStr),
        ),
        if (dup != null) ...[
          const SizedBox(height: 8),
          SetupInfoBanner(
            'Another active holiday already exists on this date: ${dup.name}.',
            tone: SetupBannerTone.warning,
          ),
        ],
        const SizedBox(height: _fieldGap),
        const Text(
          'How should employees be paid when they work?',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 6),
        _HolidayPayRateControls(
          multiplier: multiplier,
          enabled: !_busy,
          onMultiplierChanged: (next) {
            _multiplierController.text = '$next';
            setState(() {});
          },
        ),
        if (multiplierWarning(multiplier) != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              multiplierWarning(multiplier)!,
              style: const TextStyle(fontSize: 12, color: Color(0xFFB45309)),
            ),
          ),
        const SizedBox(height: 8),
        Text(unworked.explanation,
            style: appMutedStyle().copyWith(fontSize: 12, height: 1.35)),
        if (unworked.editable)
          SetupCompactSwitch(
            title: unworked.title,
            value: _customIsPaid,
            onChanged: (v) => setState(() => _customIsPaid = v),
          ),
        const SizedBox(height: _fieldGap),
        _HolidayOtPremiumControls(
          valueRaw: _otPremiumController.text,
          enabled: !_busy,
          onChanged: (next) {
            _otPremiumController.text = next;
            setState(() {});
          },
        ),
        const SizedBox(height: 8),
        _ExpandableNotes(
          open: _advancedOpen,
          onToggle: () => setState(() => _advancedOpen = !_advancedOpen),
        ),
        const SizedBox(height: 8),
        _CompactRuleSummary(
          summary: summary,
          compact: compactRuleLine(
            mode: _rulesMode,
            holidayType: 'company',
            isPaid: _customIsPaid,
            payMultiplier: multiplier,
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: FilledButton(
                onPressed: _busy ? null : _addCustomHoliday,
                style: SetupUi.primaryButtonOf(context),
                child: const Text('Save'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton(
                style: SetupUi.secondaryButtonOf(context),
                onPressed: () => setState(() => _showAdd = false),
                child: const Text('Cancel'),
              ),
            ),
          ],
        ),
      ],
    );
  }


  List<Widget> _buildRulesArea() => [
        SetupPanel(
          title: HolidayTerms.holidayRules,
          icon: Icons.tune_rounded,
          subtitle: 'How holiday types are interpreted for payroll.',
          children: [
            _rulesModeTile('philippine_labor'),
            const SizedBox(height: 8),
            _rulesModeTile('custom_company'),
            const SizedBox(height: 10),
            InkWell(
              onTap: () => setState(() => _rulesLearnMore = !_rulesLearnMore),
              child: Text(
                _rulesLearnMore ? 'Hide details' : 'Learn more',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: SetupUi.navyOf(context),
                ),
              ),
            ),
            if (_rulesLearnMore) ...[
              const SizedBox(height: 8),
              Text(
                'Current mode: ${rulesModeLabel(_rulesMode)}. Regular and Special Non-Working Days use fixed unworked treatment under Philippine labor rules. Use the edit icon on each holiday.',
                style: appMutedStyle().copyWith(fontSize: 12, height: 1.4),
              ),
            ],
          ],
        ),
      ];

  Widget _rulesModeTile(String mode) {
    final selected = _rulesMode == mode;
    return InkWell(
      onTap: _busy ? null : () => _saveRulesMode(mode),
      borderRadius: BorderRadius.circular(14),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFFF4F8FC) : Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected
                ? SetupUi.navyOf(context).withValues(alpha: 0.35)
                : AppColors.border,
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              selected ? Icons.radio_button_checked : Icons.radio_button_off,
              size: 20,
              color: selected ? SetupUi.navyOf(context) : AppColors.textMuted,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    rulesModeLabel(mode),
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    rulesModeDescription(mode),
                    style: appMutedStyle().copyWith(fontSize: 12, height: 1.35),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildHelpArea() => [
        SetupPanel(
          title: HolidayTerms.howHolidayPayWorks,
          icon: Icons.help_outline_rounded,
          subtitle: 'Simple overview. Not legal advice.',
          children: [
            for (final section in howHolidayPayWorksPrimary) ...[
              InkWell(
                onTap: () => setState(() {
                  _helpOpenTitle =
                      _helpOpenTitle == section.title ? null : section.title;
                }),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              section.title,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 13.5,
                                color: AppColors.textPrimary,
                              ),
                            ),
                          ),
                          Icon(
                            _helpOpenTitle == section.title
                                ? Icons.expand_less
                                : Icons.expand_more,
                            color: AppColors.textMuted,
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        section.summary,
                        style:
                            appMutedStyle().copyWith(fontSize: 12.5, height: 1.4),
                      ),
                      if (_helpOpenTitle == section.title) ...[
                        const SizedBox(height: 6),
                        Text(
                          section.detail,
                          style:
                              appMutedStyle().copyWith(fontSize: 12, height: 1.4),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              const Divider(height: 1),
            ],
          ],
        ),
      ];
}

class _ExpandableNotes extends StatelessWidget {
  const _ExpandableNotes({required this.open, required this.onToggle});

  final bool open;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: onToggle,
          child: Text(
            open ? 'Hide advanced notes' : 'Advanced notes',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: SetupUi.navyOf(context),
            ),
          ),
        ),
        if (open) ...[
          const SizedBox(height: 6),
          Text(
            'Holiday pay automatically follows the employee\'s existing pay basis. '
            'Daily and Hourly employees use the payroll rules already configured in Aroll+.\n'
            'Employees with multiple shifts on the same day are handled automatically.\n'
            'Rest-day premiums remain separate.',
            style: appMutedStyle().copyWith(fontSize: 12, height: 1.4),
          ),
        ],
      ],
    );
  }
}

class _CompactRuleSummary extends StatefulWidget {
  const _CompactRuleSummary({
    required this.summary,
    required this.compact,
  });

  final RuleSummaryLines summary;
  final String compact;

  @override
  State<_CompactRuleSummary> createState() => _CompactRuleSummaryState();
}

class _CompactRuleSummaryState extends State<_CompactRuleSummary> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  widget.compact,
                  style: appMutedStyle().copyWith(fontSize: 12, height: 1.35),
                ),
              ),
              TextButton(
                onPressed: () => setState(() => _open = !_open),
                child: Text(_open ? 'Hide' : 'Details'),
              ),
            ],
          ),
          if (_open) ...[
            const SizedBox(height: 6),
            Text(
              'Worked: ${widget.summary.worked.join(' ')}',
              style: appMutedStyle().copyWith(fontSize: 12, height: 1.35),
            ),
            Text(
              'Unworked: ${widget.summary.unworked.first}',
              style: appMutedStyle().copyWith(fontSize: 12, height: 1.35),
            ),
            Text(
              'OT: ${widget.summary.overtime.join(' ')}',
              style: appMutedStyle().copyWith(fontSize: 12, height: 1.35),
            ),
            Text(
              'Shifts: ${widget.summary.multipleShifts.join(' ')}',
              style: appMutedStyle().copyWith(fontSize: 12, height: 1.35),
            ),
          ],
        ],
      ),
    );
  }
}

class _HolidayPayRateControls extends StatefulWidget {
  const _HolidayPayRateControls({
    required this.multiplier,
    required this.enabled,
    required this.onMultiplierChanged,
  });

  final double multiplier;
  final bool enabled;
  final ValueChanged<double> onMultiplierChanged;

  @override
  State<_HolidayPayRateControls> createState() =>
      _HolidayPayRateControlsState();
}

class _HolidayPayRateControlsState extends State<_HolidayPayRateControls> {
  late final TextEditingController _percentController;
  late bool _custom;

  @override
  void initState() {
    super.initState();
    _custom = !isHolidayPayRatePreset(widget.multiplier);
    _percentController = TextEditingController(
      text: multiplierToPercentInput(widget.multiplier),
    );
  }

  @override
  void dispose() {
    _percentController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final selectKey = _custom
        ? 'custom'
        : holidayPayRatePresets
            .firstWhere(
              (p) => (p.multiplier - widget.multiplier).abs() < 0.0001,
              orElse: () => holidayPayRatePresets.first,
            )
            .multiplier
            .toString();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _HolidayChoiceField(
          label: HolidayTerms.workedPremium,
          title: _custom ? 'Custom' : holidayPayRateParts(widget.multiplier).title,
          detail: _custom
              ? (_percentController.text.trim().isEmpty
                  ? 'Enter a percent'
                  : '${_percentController.text.trim()}%')
              : holidayPayRateParts(widget.multiplier).detail,
          selectedId: selectKey,
          enabled: widget.enabled,
          options: holidayPayRateMenuOptions,
          onSelected: (value) {
            if (value == 'custom') {
              setState(() => _custom = true);
              if (_percentController.text.trim().isEmpty) {
                _percentController.text =
                    multiplierToPercentInput(widget.multiplier);
              }
              return;
            }
            setState(() => _custom = false);
            widget.onMultiplierChanged(double.parse(value));
          },
        ),
        if (_custom) ...[
          const SizedBox(height: 8),
          TextField(
            controller: _percentController,
            enabled: widget.enabled,
            style: const TextStyle(fontSize: 14),
            decoration: SetupUi.input('Custom total pay rate (%)'),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            onChanged: (raw) {
              final pct = double.tryParse(raw.trim());
              if (pct != null && pct > 0) {
                widget.onMultiplierChanged(percentToPayMultiplier(pct));
              }
            },
          ),
        ],
        const SizedBox(height: 8),
        Text(
          workedRateNote(widget.multiplier, custom: _custom),
          style: appMutedStyle().copyWith(fontSize: 12, height: 1.35),
        ),
      ],
    );
  }
}

class _HolidayOtPremiumControls extends StatefulWidget {
  const _HolidayOtPremiumControls({
    required this.valueRaw,
    required this.enabled,
    required this.onChanged,
  });

  final String valueRaw;
  final bool enabled;
  final ValueChanged<String> onChanged;

  @override
  State<_HolidayOtPremiumControls> createState() =>
      _HolidayOtPremiumControlsState();
}

class _HolidayOtPremiumControlsState extends State<_HolidayOtPremiumControls> {
  late final TextEditingController _customController;
  late String _select;
  late bool _explicitCustom;

  @override
  void initState() {
    super.initState();
    _select = _resolveSelect(widget.valueRaw);
    _explicitCustom = _select == 'custom';
    _customController = TextEditingController(
      text: _explicitCustom ? widget.valueRaw : '',
    );
  }

  @override
  void didUpdateWidget(covariant _HolidayOtPremiumControls oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_explicitCustom && oldWidget.valueRaw != widget.valueRaw) {
      _select = _resolveSelect(widget.valueRaw);
    }
  }

  @override
  void dispose() {
    _customController.dispose();
    super.dispose();
  }

  String _resolveSelect(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return '0';
    final num = double.tryParse(trimmed);
    if (num == null) return 'custom';
    if (num == 0) return '0';
    if ((num - 30).abs() < 0.0001) return '30';
    return 'custom';
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _HolidayChoiceField(
          label: HolidayTerms.holidayOtPremium,
          title: _select == 'custom'
              ? 'Custom'
              : holidayOtOptions
                  .firstWhere((option) => option.id == _select)
                  .title,
          detail: _select == 'custom'
              ? (_customController.text.trim().isEmpty
                  ? 'Enter a percent'
                  : '${_customController.text.trim()}%')
              : holidayOtOptions
                  .firstWhere((option) => option.id == _select)
                  .detail,
          selectedId: _select,
          enabled: widget.enabled,
          options: holidayOtOptions,
          onSelected: (value) {
            if (value == 'custom') {
              setState(() {
                _select = 'custom';
                _explicitCustom = true;
              });
              return;
            }
            final next = value == '0' ? '' : '30';
            setState(() {
              _select = value;
              _explicitCustom = false;
            });
            widget.onChanged(next);
          },
        ),
        if (_select == 'custom') ...[
          const SizedBox(height: 8),
          TextField(
            controller: _customController,
            enabled: widget.enabled,
            style: const TextStyle(fontSize: 14),
            decoration: SetupUi.input('Custom holiday OT premium (%)'),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            onChanged: widget.onChanged,
          ),
        ],
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text(
            otPremiumWarning(widget.valueRaw),
            style: appMutedStyle().copyWith(fontSize: 11.5),
          ),
        ),
      ],
    );
  }
}

class _HolidayPayEditorDialog extends StatefulWidget {
  const _HolidayPayEditorDialog({
    required this.holiday,
    required this.rulesMode,
  });

  final Map<String, dynamic> holiday;
  final String rulesMode;

  @override
  State<_HolidayPayEditorDialog> createState() => _HolidayPayEditorDialogState();
}

class _HolidayPayEditorDialogState extends State<_HolidayPayEditorDialog> {
  late final TextEditingController _nameController;
  late double _multiplier;
  late String _otRaw;
  late bool _isPaid;
  late String _date;

  bool get _isCustom => widget.holiday['holiday_type'] == 'company';

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: '${widget.holiday['name']}');
    _multiplier =
        double.tryParse('${widget.holiday['pay_multiplier']}') ?? 1.0;
    _otRaw = holidayOtPremiumDisplay(widget.holiday['ot_premium_percent']);
    _isPaid = widget.holiday['is_paid'] == true;
    _date = '${widget.holiday['holiday_date']}';
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  void _save() {
    if (_multiplier <= 0) return;
    if (isHolidayOtPremiumInvalid(_otRaw)) return;
    final unworked = unworkedRulePresentation(
      mode: widget.rulesMode,
      holidayType: '${widget.holiday['holiday_type']}',
      isPaid: _isPaid,
    );
    final payload = <String, dynamic>{
      'pay_multiplier': _multiplier,
      'ot_premium_percent': parseHolidayOtPremium(_otRaw),
    };
    if (unworked.editable) payload['is_paid'] = _isPaid;
    if (_isCustom) {
      final name = _nameController.text.trim();
      if (name.isNotEmpty) payload['name'] = name;
      if (_date.isNotEmpty) payload['holiday_date'] = _date;
    }
    Navigator.of(context).pop(payload);
  }

  @override
  Widget build(BuildContext context) {
    final type = '${widget.holiday['holiday_type']}';
    final typedName = _nameController.text.trim();
    final headerName = _isCustom
        ? (typedName.isEmpty ? '${widget.holiday['name']}' : typedName)
        : '${widget.holiday['name']}';
    final unworked = unworkedRulePresentation(
      mode: widget.rulesMode,
      holidayType: type,
      isPaid: _isPaid,
    );
    final maxHeight = MediaQuery.sizeOf(context).height * 0.78;

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 480, maxHeight: maxHeight),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                headerName,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                holidayTypeLabel(type),
                style: const TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF374151),
                ),
              ),
              Text(
                _formatHolidayDate(_date, long: true),
                style: appMutedStyle().copyWith(fontSize: 13),
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Container(
                    width: 7,
                    height: 7,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: widget.holiday['is_active'] != false
                          ? SetupUi.navyOf(context)
                          : const Color(0xFF9CA3AF),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    widget.holiday['is_active'] != false
                        ? HolidayTerms.active
                        : HolidayTerms.inactive,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF4B5563),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (_isCustom) ...[
                        TextField(
                          controller: _nameController,
                          decoration: SetupUi.input('Holiday name'),
                          onChanged: (_) => setState(() {}),
                        ),
                        const SizedBox(height: 8),
                      ],
                      const Text(
                        'Worked holiday',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.4,
                          color: AppColors.textMuted,
                        ),
                      ),
                      const SizedBox(height: 6),
                      _HolidayPayRateControls(
                        multiplier: _multiplier,
                        enabled: true,
                        onMultiplierChanged: (next) =>
                            setState(() => _multiplier = next),
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'Unworked holiday',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.4,
                          color: AppColors.textMuted,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  HolidayTerms.payScheduledDay,
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.textPrimary,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  unworked.explanation,
                                  style: appMutedStyle().copyWith(
                                    fontSize: 12,
                                    height: 1.35,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          _HolidayActiveSwitch(
                            value: unworked.editable
                                ? _isPaid
                                : unworked.effectivePaysUnworked,
                            semanticLabel: unworked.editable
                                ? unworked.title
                                : unworked.explanation,
                            onChanged: unworked.editable
                                ? (value) => setState(() => _isPaid = value)
                                : null,
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'Holiday OT',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.4,
                          color: AppColors.textMuted,
                        ),
                      ),
                      const SizedBox(height: 6),
                      _HolidayOtPremiumControls(
                        valueRaw: _otRaw,
                        enabled: true,
                        onChanged: (value) => setState(() => _otRaw = value),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        "Holiday pay follows each employee's current pay basis. More than one shift on the same day is handled automatically.",
                        style: appMutedStyle().copyWith(
                          fontSize: 11.5,
                          height: 1.35,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      style: SetupUi.secondaryButtonOf(context),
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: FilledButton(
                      style: SetupUi.primaryButtonOf(context),
                      onPressed: _save,
                      child: const Text('Save'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HolidayActiveSwitch extends StatelessWidget {
  const _HolidayActiveSwitch({
    required this.value,
    required this.semanticLabel,
    required this.onChanged,
  });

  final bool value;
  final String semanticLabel;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final enabled = onChanged != null;
    return Semantics(
      button: true,
      toggled: value,
      enabled: enabled,
      label: semanticLabel,
      child: Material(
        color: value ? SetupUi.navyOf(context) : const Color(0xFFE5E7EB),
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          onTap: enabled ? () => onChanged!(!value) : null,
          borderRadius: BorderRadius.circular(20),
          child: SizedBox(
            width: 44,
            height: 24,
            child: AnimatedAlign(
              duration: const Duration(milliseconds: 160),
              alignment: value ? Alignment.centerRight : Alignment.centerLeft,
              child: const Padding(
                padding: EdgeInsets.all(2),
                child: _SwitchKnob(),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SwitchKnob extends StatelessWidget {
  const _SwitchKnob();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 20,
      height: 20,
      decoration: const BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
      ),
    );
  }
}

class _HolidayChoiceField extends StatelessWidget {
  const _HolidayChoiceField({
    required this.label,
    required this.title,
    required this.detail,
    required this.selectedId,
    required this.options,
    required this.enabled,
    required this.onSelected,
  });

  final String label;
  final String title;
  final String detail;
  final String selectedId;
  final List<HolidayMenuOption> options;
  final bool enabled;
  final ValueChanged<String> onSelected;

  Future<void> _open(BuildContext context) async {
    final picked = await showModalBottomSheet<String>(
      context: context,
      useRootNavigator: true,
      showDragHandle: true,
      backgroundColor: Colors.white,
      builder: (context) {
        return SafeArea(
          child: ListView(
            shrinkWrap: true,
            scrollDirection: Axis.vertical,
            physics: const ClampingScrollPhysics(),
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Text(
                  label,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textMuted,
                  ),
                ),
              ),
              for (final option in options)
                ListTile(
                  dense: true,
                  selected: option.id == selectedId,
                  selectedColor: SetupUi.navyOf(context),
                  title: Text(
                    option.title,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  subtitle: Text(option.detail),
                  onTap: () => Navigator.of(context).pop(option.id),
                ),
            ],
          ),
        );
      },
    );
    if (picked != null) onSelected(picked);
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: '$label, $title, $detail',
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(SetupUi.fieldRadius),
        child: InkWell(
          onTap: enabled ? () => _open(context) : null,
          borderRadius: BorderRadius.circular(SetupUi.fieldRadius),
          child: Container(
            constraints: const BoxConstraints(minHeight: 44),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(SetupUi.fieldRadius),
              border: Border.all(color: AppColors.border),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      Text(
                        detail,
                        style: appMutedStyle().copyWith(fontSize: 12),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.expand_more, color: AppColors.textMuted),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
