import 'package:aroll_mobile/core/di/injection.dart';
import 'package:aroll_mobile/data/repositories/owner_repository.dart';
import 'package:aroll_mobile/presentation/owner/setup/setup_wizard_constants.dart';
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
  static const _fieldGap = 8.0;

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

  InputDecoration _compactInput(String label, {String? hint}) {
    return InputDecoration(
      isDense: true,
      labelText: label,
      hintText: hint,
      labelStyle: const TextStyle(fontSize: 12),
      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: Colors.grey.shade300),
      ),
    );
  }

  ButtonStyle get _primaryButtonStyle => FilledButton.styleFrom(
        backgroundColor: const Color(0xFF1E3A5F),
        minimumSize: const Size(0, 40),
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 14),
        textStyle: const TextStyle(fontSize: 14),
      );

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
      if (mounted) _showSnack('Failed to load default holidays');
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
    } catch (_) {
      if (mounted) _showSnack('Failed to update holiday');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _addCustomHoliday() async {
    final name = _nameController.text.trim();
    final multiplier = double.tryParse(_multiplierController.text) ?? 0;
    if (name.isEmpty) {
      _showSnack('Name required');
      return;
    }
    if (_customDate == null) {
      _showSnack('Date required');
      return;
    }
    if (multiplier <= 0) {
      _showSnack('Multiplier must be greater than 0');
      return;
    }

    setState(() => _busy = true);
    try {
      await _repo.createHoliday(
        name: name,
        holidayDate: formatApiDate(_customDate!),
        isPaid: _customIsPaid,
        payMultiplier: multiplier,
      );
      _nameController.clear();
      _multiplierController.text = '1.0';
      _customDate = null;
      _customIsPaid = true;
      _showSnack('Custom holiday added');
      widget.onChanged();
      await _loadHolidays();
    } catch (e) {
      _showSnack(_errorMessage(e, fallback: 'Failed to add holiday'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _deleteHoliday(String id) async {
    setState(() => _busy = true);
    try {
      await _repo.deleteHoliday(id);
      _editingId = null;
      _showSnack('Custom holiday removed');
      widget.onChanged();
      await _loadHolidays();
    } catch (_) {
      if (mounted) _showSnack('Failed to delete holiday');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  String _errorMessage(Object error, {required String fallback}) {
    if (error is DioException) {
      final data = error.response?.data;
      if (data is Map && data['detail'] is String) {
        return data['detail'] as String;
      }
    }
    if (error is Exception && error.toString().isNotEmpty) {
      return error.toString().replaceFirst('Exception: ', '');
    }
    return fallback;
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
        _infoBox('Add holidays your business follows for schedules and pay.'),
        const SizedBox(height: _fieldGap),
        if (_loading)
          Text(
            'Loading holidays…',
            style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
          ),
        if (_error)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFFFEF2F2),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFFFECACA)),
            ),
            child: const Text(
              'Unable to load holidays.',
              style: TextStyle(color: Color(0xFFB91C1C), fontSize: 12),
            ),
          ),
        if (!_loading && _holidays.isNotEmpty) ...[
          ..._holidays.map(_buildHolidayCard),
          const SizedBox(height: 6),
        ],
        _buildCustomHolidayForm(),
        const SizedBox(height: 8),
        OutlinedButton(
          style: OutlinedButton.styleFrom(
            visualDensity: VisualDensity.compact,
            padding: const EdgeInsets.symmetric(vertical: 10),
          ),
          onPressed: _busy ? null : () => _seedDefaults(),
          child: const Text(
            'Reload Philippine Holidays',
            style: TextStyle(fontSize: 13),
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

    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${holiday['name']}',
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
            ),
            const SizedBox(height: 2),
            Text(
              '${isCustom ? 'Custom' : 'Default PH'} · ${holiday['holiday_date'] ?? '--'}',
              style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              visualDensity: VisualDensity.compact,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              title: Text(
                isPaid ? 'Enabled' : 'Disabled',
                style: const TextStyle(fontSize: 13),
              ),
              value: isPaid,
              onChanged: _busy
                  ? null
                  : (value) => _updateHoliday(id, {'is_paid': value}),
            ),
            TextFormField(
              initialValue: '${holiday['pay_multiplier'] ?? 1.0}',
              enabled: isPaid && !_busy,
              style: const TextStyle(fontSize: 14),
              decoration: _compactInput('Pay Multiplier'),
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              onFieldSubmitted: (value) {
                final multiplier = double.tryParse(value) ?? 0;
                if (multiplier <= 0) {
                  _showSnack('Pay multiplier must be greater than 0');
                  return;
                }
                _updateHoliday(id, {'pay_multiplier': multiplier});
              },
            ),
            if (isCustom) ...[
              const SizedBox(height: 6),
              Row(
                children: [
                  OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                    ),
                    onPressed: _busy
                        ? null
                        : () => setState(
                              () => _editingId = editing ? null : id,
                            ),
                    child: Text(editing ? 'Done' : 'Edit',
                        style: const TextStyle(fontSize: 12)),
                  ),
                  const SizedBox(width: 6),
                  OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                    ),
                    onPressed: _busy ? null : () => _deleteHoliday(id),
                    child:
                        const Text('Delete', style: TextStyle(fontSize: 12)),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildCustomHolidayForm() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFFFAFBFC),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Add Custom Holiday',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
          ),
          const SizedBox(height: _fieldGap),
          TextField(
            controller: _nameController,
            style: const TextStyle(fontSize: 14),
            decoration: _compactInput('Name', hint: 'Company Foundation Day'),
          ),
          const SizedBox(height: _fieldGap),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(vertical: 10),
                  ),
                  onPressed: _pickCustomDate,
                  child: Text(
                    _customDate == null
                        ? 'Pick Date'
                        : formatApiDate(_customDate!),
                    style: const TextStyle(fontSize: 13),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: TextField(
                  controller: _multiplierController,
                  enabled: _customIsPaid,
                  style: const TextStyle(fontSize: 14),
                  decoration: _compactInput('Multiplier'),
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                ),
              ),
            ],
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            visualDensity: VisualDensity.compact,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            title: const Text('Holiday pay applies', style: TextStyle(fontSize: 13)),
            value: _customIsPaid,
            onChanged: (value) => setState(() => _customIsPaid = value),
          ),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _busy ? null : _addCustomHoliday,
              style: _primaryButtonStyle,
              child: const Text('Add Custom Holiday'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _infoBox(String text) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFF3F6FA),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        text,
        style: TextStyle(fontSize: 11, height: 1.35, color: Colors.grey.shade600),
      ),
    );
  }
}
