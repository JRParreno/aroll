import 'package:aroll_mobile/core/di/injection.dart';
import 'package:aroll_mobile/data/repositories/owner_repository.dart';
import 'package:aroll_mobile/presentation/owner/setup/setup_ui.dart';
import 'package:aroll_mobile/presentation/owner/setup/setup_wizard_constants.dart';
import 'package:aroll_mobile/presentation/shared/app_ui.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

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

  List<Map<String, dynamic>> _holidays = const [];
  bool _loading = true;
  bool _error = false;
  bool _seedAttempted = false;
  bool _busy = false;
  String? _editingId;
  DateTime? _customDate;
  bool _customIsPaid = true;

  @override
  void initState() {
    super.initState();
    _loadHolidays();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _multiplierController.dispose();
    super.dispose();
  }

  InputDecoration _compactInput(String label, {String? hint}) =>
      SetupUi.input(label, hint: hint);

  ButtonStyle get _primaryButtonStyle => SetupUi.primaryButton;

  Future<void> _loadHolidays() async {
    setState(() {
      _loading = true;
      _error = false;
    });
    try {
      final holidays = await _repo.holidays();
      if (!mounted) return;
      setState(() {
        _holidays = holidays;
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

  bool _isCustomHoliday(Map<String, dynamic> holiday) =>
      holiday['holiday_type'] == 'company';

  Future<void> _seedDefaults({bool showEmptyToast = true}) async {
    setState(() => _busy = true);
    try {
      final created = await _repo.seedDefaultHolidays();
      if (!mounted) return;
      if (showEmptyToast && created.isNotEmpty) {
        _showSnack('Loaded ${created.length} Philippine holidays');
      }
      widget.onChanged();
      await _loadHolidays();
    } catch (_) {
      if (mounted) _showSnack('Could not load default holidays');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _updateHoliday(
    String id,
    Map<String, dynamic> payload,
  ) async {
    setState(() => _busy = true);
    try {
      await _repo.updateHoliday(id, payload);
      widget.onChanged();
      await _loadHolidays();
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

  Future<void> _deleteHoliday(String id) async {
    setState(() => _busy = true);
    try {
      await _repo.deleteHoliday(id);
      widget.onChanged();
      await _loadHolidays();
    } catch (_) {
      if (mounted) _showSnack('Could not delete holiday');
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
    if (_customIsPaid && multiplier <= 0) {
      _showSnack('Please enter a holiday pay rate greater than 0');
      return;
    }

    setState(() => _busy = true);
    try {
      await _repo.createHoliday(
        name: name,
        holidayDate: formatApiDate(_customDate!),
        isPaid: _customIsPaid,
        payMultiplier: _customIsPaid ? multiplier : 1.0,
      );
      _nameController.clear();
      _multiplierController.text = '1.0';
      _customDate = null;
      _customIsPaid = true;
      widget.onChanged();
      await _loadHolidays();
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
    if (picked != null) {
      setState(() => _customDate = picked);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SetupInfoBanner(
          'Add the holidays your business follows so schedules and pay stay accurate.',
        ),
        const SizedBox(height: _fieldGap),
        if (_loading)
          Text(
            'Loading holidays…',
            style: appMutedStyle().copyWith(fontSize: 12),
          ),
        if (_error)
          const SetupInfoBanner(
            'Unable to load holidays. Please try again.',
            tone: SetupBannerTone.danger,
          ),
        if (!_loading && _holidays.isNotEmpty) ...[
          ..._holidays.map(_buildHolidayCard),
          const SizedBox(height: 4),
        ],
        _buildCustomHolidayForm(),
        const SizedBox(height: 10),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton(
            style: SetupUi.secondaryButton,
            onPressed: _busy ? null : () => _seedDefaults(),
            child: const Text('Load Philippine holidays'),
          ),
        ),
      ],
    );
  }

  Widget _buildHolidayCard(Map<String, dynamic> holiday) {
    final id = '${holiday['id']}';
    final isCustom = _isCustomHoliday(holiday);
    final isPaid = holiday['is_paid'] == true;
    final editing = _editingId == id;

    return SetupSurfaceCard(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: AppColors.iconWell,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.event_outlined,
                  size: 18,
                  color: SetupUi.navy,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${holiday['name']}',
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${isCustom ? 'Custom' : 'Default PH'} · ${holiday['holiday_date'] ?? '--'}',
                      style: appMutedStyle().copyWith(fontSize: 11.5),
                    ),
                  ],
                ),
              ),
            ],
          ),
          SetupCompactSwitch(
            title: isPaid ? 'Holiday pay enabled' : 'Holiday pay disabled',
            value: isPaid,
            onChanged: _busy
                ? null
                : (value) => _updateHoliday(id, {'is_paid': value}),
          ),
          TextFormField(
            initialValue: '${holiday['pay_multiplier'] ?? 1.0}',
            enabled: isPaid && !_busy,
            style: const TextStyle(fontSize: 14),
            decoration: _compactInput('Holiday pay rate (e.g. 2 = double)'),
            keyboardType:
                const TextInputType.numberWithOptions(decimal: true),
            onFieldSubmitted: (value) {
              final multiplier = double.tryParse(value) ?? 0;
              if (multiplier <= 0) {
                _showSnack('Please enter a holiday pay rate greater than 0');
                return;
              }
              _updateHoliday(id, {'pay_multiplier': multiplier});
            },
          ),
          if (isCustom) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    style: SetupUi.secondaryButton,
                    onPressed: _busy
                        ? null
                        : () => setState(
                              () => _editingId = editing ? null : id,
                            ),
                    child: Text(editing ? 'Done' : 'Edit'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton(
                    style: SetupUi.secondaryButton.copyWith(
                      foregroundColor:
                          const WidgetStatePropertyAll(AppColors.danger),
                    ),
                    onPressed: _busy ? null : () => _deleteHoliday(id),
                    child: const Text('Delete'),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildCustomHolidayForm() {
    return SetupPanel(
      title: 'Add your own holiday',
      icon: Icons.add_circle_outline_rounded,
      subtitle: 'Use this for company holidays or special closure days.',
      children: [
        TextField(
          controller: _nameController,
          style: const TextStyle(fontSize: 14),
          decoration:
              _compactInput('Holiday name', hint: 'Company Foundation Day'),
        ),
        const SizedBox(height: _fieldGap),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                style: SetupUi.secondaryButton,
                onPressed: _pickCustomDate,
                child: Text(
                  _customDate == null
                      ? 'Choose date'
                      : formatApiDate(_customDate!),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: _multiplierController,
                enabled: _customIsPaid,
                style: const TextStyle(fontSize: 14),
                decoration: _compactInput('Holiday pay rate'),
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
              ),
            ),
          ],
        ),
        SetupCompactSwitch(
          title: 'Employees get holiday pay',
          value: _customIsPaid,
          onChanged: (value) => setState(() => _customIsPaid = value),
        ),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: _busy ? null : _addCustomHoliday,
            style: _primaryButtonStyle,
            child: const Text('Add holiday'),
          ),
        ),
      ],
    );
  }
}
