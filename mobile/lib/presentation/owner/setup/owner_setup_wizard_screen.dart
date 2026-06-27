import 'package:aroll_mobile/core/app_state.dart';
import 'package:aroll_mobile/core/di/injection.dart';
import 'package:aroll_mobile/data/repositories/owner_repository.dart';
import 'package:aroll_mobile/presentation/owner/setup/holiday_setup_section.dart';
import 'package:aroll_mobile/presentation/owner/setup/setup_wizard_constants.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class OwnerSetupWizardScreen extends StatefulWidget {
  const OwnerSetupWizardScreen({super.key, this.initialStep = 0});

  final int initialStep;

  @override
  State<OwnerSetupWizardScreen> createState() => _OwnerSetupWizardScreenState();
}

class _OwnerSetupWizardScreenState extends State<OwnerSetupWizardScreen> {
  static const _sectionGap = 8.0;
  static const _fieldGap = 8.0;
  static const _cardPadding = 12.0;
  static const _stepRowHeight = 38.0;

  final _repo = sl<OwnerRepository>();

  late int _step;
  bool _loading = true;
  bool _busy = false;
  String? _loadError;

  Map<String, dynamic>? _setupStatus;
  List<Map<String, dynamic>> _shifts = const [];
  List<Map<String, dynamic>> _positions = const [];

  final _shiftName = TextEditingController();
  String _shiftType = 'morning';
  TimeOfDay _shiftStart = const TimeOfDay(hour: 6, minute: 0);
  TimeOfDay _shiftEnd = const TimeOfDay(hour: 14, minute: 0);
  final _shiftBreak = TextEditingController(text: '0');
  final _shiftCapacity = TextEditingController(text: '1');

  final _positionTitle = TextEditingController();
  final _positionRate = TextEditingController();
  final _positionDescription = TextEditingController();

  String _payPeriodType = 'monthly';
  DateTime? _nextPaydayDate;
  bool _autoResetPayrollCycle = true;
  bool _payrollLateDeductionEnabled = true;
  final _payrollLateDeductionRate = TextEditingController(text: '1');
  bool _payrollOvertimeEnabled = true;
  final _payrollOvertimeRate = TextEditingController(text: '1');

  final _attEarlyClockIn = TextEditingController(text: '15');
  final _attOnTimeGrace = TextEditingController(text: '10');
  final _attHalfDay = TextEditingController(text: '120');
  final _attAbsent = TextEditingController(text: '240');
  bool _attEarlyOutDeductionEnabled = false;
  final _attEarlyOutDeductionRate = TextEditingController(text: '2');
  bool _attOvertimeEnabled = true;
  final _attOvertimeMinimum = TextEditingController(text: '30');
  String _attMissingClockOutPolicy = 'auto_clock_out';
  bool _attAttendanceBasedSalaryEnabled = true;

  String _restWeeklyDay = 'sunday';
  bool _restWorkAllowed = false;
  final _restPremiumPercent = TextEditingController(text: '30');
  bool _restUseCustomPremium = false;
  final _restCustomPremiumPercent = TextEditingController();

  final _locationLabel = TextEditingController(text: 'Main');
  final _locationAddress = TextEditingController();
  final _locationLatitude = TextEditingController();
  final _locationLongitude = TextEditingController();
  double _locationGeofence = 75;

  @override
  void initState() {
    super.initState();
    _step = clampSetupStep(widget.initialStep);
    _loadAll();
  }

  @override
  void dispose() {
    _shiftName.dispose();
    _shiftBreak.dispose();
    _shiftCapacity.dispose();
    _positionTitle.dispose();
    _positionRate.dispose();
    _positionDescription.dispose();
    _payrollLateDeductionRate.dispose();
    _payrollOvertimeRate.dispose();
    _attEarlyClockIn.dispose();
    _attOnTimeGrace.dispose();
    _attHalfDay.dispose();
    _attAbsent.dispose();
    _attEarlyOutDeductionRate.dispose();
    _attOvertimeMinimum.dispose();
    _restPremiumPercent.dispose();
    _restCustomPremiumPercent.dispose();
    _locationLabel.dispose();
    _locationAddress.dispose();
    _locationLatitude.dispose();
    _locationLongitude.dispose();
    super.dispose();
  }

  Future<void> _loadAll() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final results = await Future.wait([
        _repo.setupStatus(),
        _repo.shifts(),
        _repo.positions(),
        _repo.payrollConfig(),
        _repo.attendancePolicy(),
        _repo.location(),
        _repo.restDayPolicy(),
      ]);
      if (!mounted) return;
      final payroll = results[3] as Map<String, dynamic>;
      final attendance = results[4] as Map<String, dynamic>;
      final location = results[5] as Map<String, dynamic>;
      final restDay = results[6] as Map<String, dynamic>;

      _applyPayroll(payroll);
      _applyAttendance(attendance);
      _applyLocation(location);
      _applyRestDay(restDay);

      setState(() {
        _setupStatus = results[0] as Map<String, dynamic>;
        _shifts = results[1] as List<Map<String, dynamic>>;
        _positions = results[2] as List<Map<String, dynamic>>;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadError = 'Unable to load setup wizard.';
      });
    }
  }

  void _applyPayroll(Map<String, dynamic> payroll) {
    _payPeriodType = '${payroll['pay_period_type'] ?? 'monthly'}';
    final payday = payroll['next_payday_date'] as String?;
    _nextPaydayDate =
        payday == null || payday.isEmpty ? null : DateTime.tryParse(payday);
    _autoResetPayrollCycle = payroll['auto_reset_payroll_cycle'] != false;
    _payrollLateDeductionEnabled = payroll['late_deduction_enabled'] != false;
    _payrollLateDeductionRate.text =
        '${payroll['late_deduction_per_minute'] ?? 1}';
    _payrollOvertimeEnabled = payroll['overtime_enabled'] != false;
    _payrollOvertimeRate.text = '${payroll['overtime_per_minute'] ?? 1}';
  }

  void _applyAttendance(Map<String, dynamic> attendance) {
    _attEarlyClockIn.text = '${attendance['early_clock_in_minutes'] ?? 15}';
    _attOnTimeGrace.text = '${attendance['on_time_grace_minutes'] ?? 10}';
    _attHalfDay.text = '${attendance['half_day_threshold_minutes'] ?? 120}';
    _attAbsent.text = '${attendance['absent_threshold_minutes'] ?? 240}';
    _attEarlyOutDeductionEnabled =
        attendance['early_out_deduction_enabled'] == true;
    _attEarlyOutDeductionRate.text =
        '${attendance['early_out_deduction_per_minute'] ?? 2}';
    _attOvertimeEnabled = attendance['overtime_enabled'] != false;
    _attOvertimeMinimum.text =
        '${attendance['overtime_minimum_minutes'] ?? 30}';
    _attMissingClockOutPolicy =
        '${attendance['missing_clock_out_policy'] ?? 'auto_clock_out'}';
    _attAttendanceBasedSalaryEnabled =
        attendance['attendance_based_salary_enabled'] != false;
  }

  void _applyLocation(Map<String, dynamic> location) {
    _locationLabel.text = '${location['label'] ?? 'Main'}';
    _locationAddress.text = '${location['address'] ?? ''}';
    _locationLatitude.text = location['latitude']?.toString() ?? '';
    _locationLongitude.text = location['longitude']?.toString() ?? '';
    _locationGeofence =
        (location['geofence_radius_m'] as num?)?.toDouble() ?? 75;
  }

  void _applyRestDay(Map<String, dynamic> restDay) {
    _restWeeklyDay = '${restDay['weekly_rest_day'] ?? 'sunday'}';
    _restWorkAllowed = restDay['work_on_rest_day_allowed'] == true;
    _restPremiumPercent.text = '${restDay['rest_day_premium_percent'] ?? 30}';
    _restUseCustomPremium = restDay['use_custom_premium'] == true;
    final custom = restDay['custom_premium_percent'];
    _restCustomPremiumPercent.text = custom == null ? '' : '$custom';
  }

  Future<void> _refreshSetupStatus() async {
    final status = await _repo.setupStatus();
    if (!mounted) return;
    setState(() => _setupStatus = status);
  }

  bool get _shiftDraftValid =>
      _shiftName.text.trim().isNotEmpty &&
      int.tryParse(_shiftBreak.text) != null &&
      (int.tryParse(_shiftBreak.text) ?? -1) >= 0 &&
      (int.tryParse(_shiftCapacity.text) ?? 0) >= 1;

  bool get _positionDraftValid =>
      _positionTitle.text.trim().isNotEmpty &&
      (double.tryParse(_positionRate.text) ?? 0) > 0;

  bool get _payrollFormValid =>
      _nextPaydayDate != null &&
      (double.tryParse(_payrollLateDeductionRate.text) ?? -1) >= 0 &&
      (double.tryParse(_payrollOvertimeRate.text) ?? -1) >= 0;

  bool get _locationCanSave =>
      _locationAddress.text.trim().length >= 5 &&
      _locationLatitude.text.trim().isNotEmpty &&
      _locationLongitude.text.trim().isNotEmpty &&
      _locationGeofence >= 20 &&
      _locationGeofence <= 200;

  bool _currentStepCanContinue() {
    switch (_step) {
      case 0:
        return isSetupStepComplete(_setupStatus, 'shifts') || _shiftDraftValid;
      case 1:
        return isSetupStepComplete(_setupStatus, 'positions') ||
            _positionDraftValid;
      case 2:
        return isSetupStepComplete(_setupStatus, 'payroll') ||
            _payrollFormValid;
      case 3:
        return isSetupStepComplete(_setupStatus, 'attendance_policy');
      case 4:
        return isSetupStepComplete(_setupStatus, 'holidays');
      case 5:
        return isSetupStepComplete(_setupStatus, 'rest_day');
      case 6:
        return isSetupStepComplete(_setupStatus, 'location') ||
            _locationCanSave;
      default:
        return false;
    }
  }

  Future<bool> _addShift() async {
    if (!_shiftDraftValid) return false;
    setState(() => _busy = true);
    try {
      await _repo.createShift(
        name: _shiftName.text.trim(),
        shiftType: _shiftType,
        startTime: formatApiTime(_shiftStart),
        endTime: formatApiTime(_shiftEnd),
        breakMinutes: int.parse(_shiftBreak.text),
        employeeCapacity: int.parse(_shiftCapacity.text),
      );
      _shiftName.clear();
      _showSnack('Shift added');
      _shifts = await _repo.shifts();
      await _refreshSetupStatus();
      return true;
    } catch (_) {
      _showSnack('Failed to add shift');
      return false;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _removeShift(String id) async {
    setState(() => _busy = true);
    try {
      await _repo.deleteShift(id);
      _shifts = await _repo.shifts();
      await _refreshSetupStatus();
    } catch (_) {
      _showSnack('Failed to remove shift');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<bool> _addPosition() async {
    if (!_positionDraftValid) return false;
    setState(() => _busy = true);
    try {
      await _repo.createPosition(
        title: _positionTitle.text.trim(),
        dailyRate: double.parse(_positionRate.text.trim()),
        description: _positionDescription.text.trim(),
      );
      _positionTitle.clear();
      _positionRate.clear();
      _positionDescription.clear();
      _showSnack('Position added');
      final positions = await _repo.positions();
      await _refreshSetupStatus();
      if (!mounted) return false;
      setState(() => _positions = positions);
      return true;
    } on DioException catch (e) {
      _showSnack(_errorMessageFromDio(e, fallback: 'Failed to add position'));
      return false;
    } catch (_) {
      _showSnack('Failed to add position');
      return false;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _removePosition(String id) async {
    setState(() => _busy = true);
    try {
      await _repo.deletePosition(id);
      _positions = await _repo.positions();
      await _refreshSetupStatus();
    } catch (_) {
      _showSnack('Failed to remove position');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<bool> _savePayroll() async {
    if (!_payrollFormValid) return false;
    setState(() => _busy = true);
    try {
      await _repo.updatePayrollConfig({
        'pay_period_type': _payPeriodType,
        'next_payday_date':
            _nextPaydayDate == null ? null : formatApiDate(_nextPaydayDate!),
        'auto_reset_payroll_cycle': _autoResetPayrollCycle,
        'late_deduction_enabled': _payrollLateDeductionEnabled,
        'late_deduction_per_minute':
            double.parse(_payrollLateDeductionRate.text),
        'overtime_enabled': _payrollOvertimeEnabled,
        'overtime_per_minute': double.parse(_payrollOvertimeRate.text),
      });
      _showSnack('Payroll configuration saved');
      await _refreshSetupStatus();
      return true;
    } catch (_) {
      _showSnack('Failed to save payroll configuration');
      return false;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _saveAttendance() async {
    setState(() => _busy = true);
    try {
      await _repo.updateAttendancePolicy({
        'early_clock_in_minutes': int.parse(_attEarlyClockIn.text),
        'on_time_grace_minutes': int.parse(_attOnTimeGrace.text),
        'half_day_threshold_minutes': int.parse(_attHalfDay.text),
        'absent_threshold_minutes': int.parse(_attAbsent.text),
        'early_out_deduction_enabled': _attEarlyOutDeductionEnabled,
        'early_out_deduction_per_minute':
            double.parse(_attEarlyOutDeductionRate.text),
        'overtime_enabled': _attOvertimeEnabled,
        'overtime_minimum_minutes': int.parse(_attOvertimeMinimum.text),
        'missing_clock_out_policy': _attMissingClockOutPolicy,
        'attendance_based_salary_enabled': _attAttendanceBasedSalaryEnabled,
      });
      _showSnack('Attendance policy saved');
      await _refreshSetupStatus();
    } catch (_) {
      _showSnack('Failed to save attendance policy');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _saveRestDay() async {
    setState(() => _busy = true);
    try {
      await _repo.updateRestDayPolicy({
        'weekly_rest_day': _restWeeklyDay,
        'work_on_rest_day_allowed': _restWorkAllowed,
        'rest_day_premium_percent': double.parse(_restPremiumPercent.text),
        'use_custom_premium': _restUseCustomPremium,
        'custom_premium_percent': _restCustomPremiumPercent.text.trim().isEmpty
            ? null
            : double.parse(_restCustomPremiumPercent.text),
      });
      _showSnack('Rest day policy saved');
      await _refreshSetupStatus();
    } catch (_) {
      _showSnack('Failed to save rest day policy');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<bool> _saveLocation() async {
    if (!_locationCanSave) return false;
    setState(() => _busy = true);
    try {
      await _repo.updateLocation({
        'label': _locationLabel.text.trim(),
        'address': _locationAddress.text.trim(),
        'latitude': double.parse(_locationLatitude.text.trim()),
        'longitude': double.parse(_locationLongitude.text.trim()),
        'geofence_radius_m': _locationGeofence.round(),
      });
      _showSnack('Business location saved');
      await _refreshSetupStatus();
      return true;
    } catch (_) {
      _showSnack('Failed to save location');
      return false;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _finishSetup() async {
    setState(() => _busy = true);
    try {
      await _repo.completeSetup();
      final status = await _repo.setupStatus();
      sl<AppState>().updateSetupCompletedAt(
        parseSetupDateTime(status['setup_completed_at']),
      );
      if (!mounted) return;
      _showSnack('Business setup marked complete');
      context.go('/owner/home');
    } on DioException catch (e) {
      final missing = _missingItemsFromError(e);
      _showSnack(missing ?? 'Complete all required setup steps first');
      await _refreshSetupStatus();
    } catch (_) {
      _showSnack('Complete all required setup steps first');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String? _missingItemsFromError(DioException error) {
    final data = error.response?.data;
    if (data is Map && data['detail'] is Map) {
      final detail = data['detail'] as Map;
      final items = detail['missing_items'];
      if (items is List && items.isNotEmpty) {
        return items.join(', ');
      }
    }
    return null;
  }

  String _errorMessageFromDio(DioException error, {required String fallback}) {
    final data = error.response?.data;
    if (data is Map) {
      final detail = data['detail'];
      if (detail is String && detail.trim().isNotEmpty) {
        return detail;
      }
      if (detail is List && detail.isNotEmpty) {
        final first = detail.first;
        if (first is Map && first['msg'] is String) {
          return first['msg'] as String;
        }
      }
    }
    return fallback;
  }

  Future<void> _handleContinue() async {
    if (!_currentStepCanContinue() || _busy) return;
    setState(() => _busy = true);
    try {
      var saved = true;
      if (_step == 0 &&
          !isSetupStepComplete(_setupStatus, 'shifts') &&
          _shiftDraftValid) {
        saved = await _addShift();
      } else if (_step == 1 &&
          !isSetupStepComplete(_setupStatus, 'positions') &&
          _positionDraftValid) {
        saved = await _addPosition();
      } else if (_step == 2 &&
          !isSetupStepComplete(_setupStatus, 'payroll') &&
          _payrollFormValid) {
        saved = await _savePayroll();
      } else if (_step == 6 &&
          !isSetupStepComplete(_setupStatus, 'location') &&
          _locationCanSave) {
        saved = await _saveLocation();
      }
      if (!mounted || !saved) {
        if (!saved) _showSnack('Save this step before continuing.');
        return;
      }
      setState(() => _step = clampSetupStep(_step + 1));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _pickTime({
    required TimeOfDay initial,
    required ValueChanged<TimeOfDay> onPicked,
  }) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: initial,
    );
    if (picked != null) onPicked(picked);
  }

  Future<void> _pickPayday() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _nextPaydayDate ?? DateTime.now(),
      firstDate: DateTime.now(),
      lastDate: DateTime(2100),
    );
    if (picked != null) setState(() => _nextPaydayDate = picked);
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F8FA),
      appBar: AppBar(
        backgroundColor: const Color(0xFFF7F8FA),
        elevation: 0,
        scrolledUnderElevation: 0,
        toolbarHeight: 52,
        title: const Text(
          'Business Setup Wizard',
          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18),
        ),
        actions: [
          TextButton(
            onPressed: () => context.go('/owner/home'),
            child: const Text('Exit', style: TextStyle(fontSize: 13)),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _loadError != null
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(_loadError!),
                      const SizedBox(height: 12),
                      FilledButton(
                        onPressed: _loadAll,
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                )
              : Column(
                  children: [
                    Expanded(
                      child: ListView(
                        padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
                        children: [
                          _buildTitleSection(),
                          const SizedBox(height: 14),
                          _buildStepNav(),
                          const SizedBox(height: _sectionGap),
                          _buildStepCard(),
                        ],
                      ),
                    ),
                    _buildFooter(),
                  ],
                ),
    );
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

  Widget _compactSwitch({
    required String title,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return SwitchListTile(
      contentPadding: EdgeInsets.zero,
      dense: true,
      visualDensity: VisualDensity.compact,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      title: Text(title, style: const TextStyle(fontSize: 13)),
      value: value,
      onChanged: onChanged,
    );
  }

  Widget _compactPanel(
      {required String title, required List<Widget> children}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      decoration: BoxDecoration(
        color: const Color(0xFFFAFBFC),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
          ),
          const SizedBox(height: 4),
          ...children,
        ],
      ),
    );
  }

  Widget _buildTitleSection() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: Text(
        'Complete your business setup to start managing employees and '
        'operations.',
        style: TextStyle(
          fontSize: 13,
          height: 1.4,
          color: Colors.grey.shade600,
        ),
      ),
    );
  }

  Widget _buildStepNavRow(int startIndex) {
    return Row(
      children: [
        for (var offset = 0; offset < 4; offset++) ...[
          if (offset > 0) const SizedBox(width: 6),
          Expanded(child: _buildStepChip(startIndex + offset)),
        ],
      ],
    );
  }

  Widget _buildStepChip(int index) {
    final label = setupWizardStepLabels[index];
    final key = setupWizardStepKeys[index];
    final complete = isSetupStepComplete(_setupStatus, key);
    final active = index == _step;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => setState(() => _step = index),
        borderRadius: BorderRadius.circular(8),
        child: Container(
          height: _stepRowHeight,
          padding: const EdgeInsets.symmetric(horizontal: 6),
          alignment: Alignment.centerLeft,
          decoration: BoxDecoration(
            color: active ? const Color(0xFF1E3A5F) : const Color(0xFFFAFBFC),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: active ? const Color(0xFF1E3A5F) : const Color(0xFFE5E7EB),
            ),
          ),
          child: Row(
            children: [
              Icon(
                complete
                    ? Icons.check_circle_rounded
                    : Icons.radio_button_unchecked_rounded,
                size: 13,
                color: active
                    ? Colors.white
                    : complete
                        ? Colors.green
                        : const Color(0xFF9CA3AF),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 10.5,
                    color: active ? Colors.white : const Color(0xFF374151),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStepNav() {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(6),
        child: Column(
          children: [
            SizedBox(height: _stepRowHeight, child: _buildStepNavRow(0)),
            const SizedBox(height: 6),
            SizedBox(height: _stepRowHeight, child: _buildStepNavRow(4)),
          ],
        ),
      ),
    );
  }

  Widget _buildStepCard() {
    final label = setupWizardStepLabels[_step];
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(_cardPadding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            Text(
              setupStepHelp[label] ?? '',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11,
                height: 1.35,
                color: Colors.grey.shade600,
              ),
            ),
            const SizedBox(height: 8),
            _buildStepContent(),
          ],
        ),
      ),
    );
  }

  Widget _buildStepContent() {
    switch (_step) {
      case 0:
        return _buildShiftsStep();
      case 1:
        return _buildPositionsStep();
      case 2:
        return _buildPayrollStep();
      case 3:
        return _buildAttendanceStep();
      case 4:
        return HolidaySetupSection(onChanged: _refreshSetupStatus);
      case 5:
        return _buildRestDayStep();
      case 6:
        return _buildLocationStep();
      case 7:
        return _buildReviewStep();
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _buildShiftsStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: _shiftName,
          style: const TextStyle(fontSize: 14),
          decoration: _compactInput('Shift Name', hint: 'Morning Shift'),
        ),
        const SizedBox(height: _fieldGap),
        DropdownButtonFormField<String>(
          initialValue: _shiftType,
          isDense: true,
          decoration: _compactInput('Shift Type'),
          items: const [
            DropdownMenuItem(value: 'morning', child: Text('Morning')),
            DropdownMenuItem(value: 'afternoon', child: Text('Afternoon')),
            DropdownMenuItem(value: 'evening', child: Text('Evening')),
            DropdownMenuItem(value: 'night', child: Text('Night')),
          ],
          onChanged: (value) {
            if (value != null) setState(() => _shiftType = value);
          },
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
                onPressed: () => _pickTime(
                  initial: _shiftStart,
                  onPicked: (value) => setState(() => _shiftStart = value),
                ),
                child: Text(
                  'Start ${formatApiTime(_shiftStart)}',
                  style: const TextStyle(fontSize: 13),
                ),
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: OutlinedButton(
                style: OutlinedButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(vertical: 10),
                ),
                onPressed: () => _pickTime(
                  initial: _shiftEnd,
                  onPicked: (value) => setState(() => _shiftEnd = value),
                ),
                child: Text(
                  'End ${formatApiTime(_shiftEnd)}',
                  style: const TextStyle(fontSize: 13),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: _fieldGap),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _shiftBreak,
                style: const TextStyle(fontSize: 14),
                decoration: _compactInput('Break Min'),
                keyboardType: TextInputType.number,
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: TextField(
                controller: _shiftCapacity,
                style: const TextStyle(fontSize: 14),
                decoration: _compactInput('Capacity'),
                keyboardType: TextInputType.number,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: _busy || !_shiftDraftValid ? null : _addShift,
            style: _primaryButtonStyle,
            child: const Text('Add Shift'),
          ),
        ),
        if (_shifts.isNotEmpty) ...[
          const SizedBox(height: 10),
          ..._shifts.map(
            (shift) => Card(
              margin: const EdgeInsets.only(bottom: 6),
              child: ListTile(
                dense: true,
                visualDensity: VisualDensity.compact,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
                title: Text(
                  '${shift['name']} (${shift['start_time']}–${shift['end_time']})',
                  style: const TextStyle(fontSize: 13),
                ),
                trailing: TextButton(
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                  ),
                  onPressed:
                      _busy ? null : () => _removeShift('${shift['id']}'),
                  child: const Text('Remove', style: TextStyle(fontSize: 13)),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildPositionsStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 3,
              child: TextField(
                controller: _positionTitle,
                style: const TextStyle(fontSize: 14),
                decoration: _compactInput('Position Name'),
                onChanged: (_) => setState(() {}),
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              flex: 2,
              child: TextField(
                controller: _positionRate,
                style: const TextStyle(fontSize: 14),
                decoration: _compactInput('Daily Rate (₱)'),
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                onChanged: (_) => setState(() {}),
              ),
            ),
          ],
        ),
        const SizedBox(height: _fieldGap),
        TextField(
          controller: _positionDescription,
          style: const TextStyle(fontSize: 14),
          decoration: _compactInput('Description'),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 10),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: _busy || !_positionDraftValid
                ? null
                : () {
                    _addPosition();
                  },
            style: _primaryButtonStyle,
            child: const Text('Add Position'),
          ),
        ),
        if (_positions.isNotEmpty) ...[
          const SizedBox(height: 10),
          ..._positions.map(
            (position) => Card(
              margin: const EdgeInsets.only(bottom: 6),
              child: ListTile(
                dense: true,
                visualDensity: VisualDensity.compact,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
                title: Text(
                  '${position['title']} — ₱${position['daily_rate']}/day',
                  style: const TextStyle(fontSize: 13),
                ),
                trailing: TextButton(
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                  ),
                  onPressed:
                      _busy ? null : () => _removePosition('${position['id']}'),
                  child: const Text('Remove', style: TextStyle(fontSize: 13)),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildPayrollStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DropdownButtonFormField<String>(
          initialValue: _payPeriodType,
          isDense: true,
          decoration: _compactInput('Pay Period Type'),
          items: const [
            DropdownMenuItem(value: 'weekly', child: Text('Weekly')),
            DropdownMenuItem(
              value: 'semi_monthly',
              child: Text('Semi-Monthly'),
            ),
            DropdownMenuItem(value: 'monthly', child: Text('Monthly')),
          ],
          onChanged: (value) {
            if (value != null) setState(() => _payPeriodType = value);
          },
        ),
        const SizedBox(height: _fieldGap),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton(
            style: OutlinedButton.styleFrom(
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.symmetric(vertical: 10),
            ),
            onPressed: _pickPayday,
            child: Text(
              _nextPaydayDate == null
                  ? 'Pick Next Payday Date'
                  : 'Next Payday: ${formatApiDate(_nextPaydayDate!)}',
              style: const TextStyle(fontSize: 13),
            ),
          ),
        ),
        _compactSwitch(
          title: 'Auto-reset payroll cycle after payday',
          value: _autoResetPayrollCycle,
          onChanged: (value) => setState(() => _autoResetPayrollCycle = value),
        ),
        _compactPanel(
          title: 'Pay Rules',
          children: [
            _compactSwitch(
              title: 'Enable late deduction',
              value: _payrollLateDeductionEnabled,
              onChanged: (value) =>
                  setState(() => _payrollLateDeductionEnabled = value),
            ),
            TextField(
              controller: _payrollLateDeductionRate,
              enabled: _payrollLateDeductionEnabled,
              style: const TextStyle(fontSize: 14),
              decoration: _compactInput('Late Deduction (₱/min)'),
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
            ),
            const SizedBox(height: 4),
            _compactSwitch(
              title: 'Enable overtime pay',
              value: _payrollOvertimeEnabled,
              onChanged: (value) =>
                  setState(() => _payrollOvertimeEnabled = value),
            ),
            TextField(
              controller: _payrollOvertimeRate,
              enabled: _payrollOvertimeEnabled,
              style: const TextStyle(fontSize: 14),
              decoration: _compactInput('Overtime Rate (₱/min)'),
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
            ),
          ],
        ),
        const SizedBox(height: 10),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: _busy || !_payrollFormValid ? null : _savePayroll,
            style: _primaryButtonStyle,
            child: const Text('Save Payroll'),
          ),
        ),
      ],
    );
  }

  Widget _buildAttendanceStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: _labeledNumberField(
                'Early Clock-In (min)',
                _attEarlyClockIn,
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child:
                  _labeledNumberField('On-Time Grace (min)', _attOnTimeGrace),
            ),
          ],
        ),
        const SizedBox(height: _fieldGap),
        Row(
          children: [
            Expanded(
              child: _labeledNumberField('Half-Day (min)', _attHalfDay),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: _labeledNumberField('Absent (min)', _attAbsent),
            ),
          ],
        ),
        const SizedBox(height: _fieldGap),
        _labeledNumberField('Min Overtime (min)', _attOvertimeMinimum),
        const SizedBox(height: _fieldGap),
        _infoBox(
          'Overtime uses payroll: ₱${_payrollOvertimeRate.text}/min '
          '(${_payrollOvertimeEnabled ? 'enabled' : 'disabled'}).',
        ),
        const SizedBox(height: 10),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: _busy ? null : _saveAttendance,
            style: _primaryButtonStyle,
            child: const Text('Save Attendance Policy'),
          ),
        ),
      ],
    );
  }

  Widget _buildRestDayStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 3,
              child: DropdownButtonFormField<String>(
                initialValue: _restWeeklyDay,
                isDense: true,
                decoration: _compactInput('Weekly Rest Day'),
                items: const [
                  'sunday',
                  'monday',
                  'tuesday',
                  'wednesday',
                  'thursday',
                  'friday',
                  'saturday',
                ]
                    .map(
                      (day) => DropdownMenuItem(
                        value: day,
                        child: Text(day[0].toUpperCase() + day.substring(1)),
                      ),
                    )
                    .toList(),
                onChanged: (value) {
                  if (value != null) setState(() => _restWeeklyDay = value);
                },
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              flex: 2,
              child: TextField(
                controller: _restPremiumPercent,
                style: const TextStyle(fontSize: 14),
                decoration: _compactInput('Premium (%)'),
                keyboardType: TextInputType.number,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: _busy ? null : _saveRestDay,
            style: _primaryButtonStyle,
            child: const Text('Save Rest Day Policy'),
          ),
        ),
      ],
    );
  }

  Widget _buildLocationStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _infoBox(
          'Set your work site and geofence so employees can clock in.',
        ),
        const SizedBox(height: _fieldGap),
        TextField(
          controller: _locationAddress,
          style: const TextStyle(fontSize: 14),
          decoration: _compactInput('Address', hint: '123 Main St, Manila'),
        ),
        const SizedBox(height: _fieldGap),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _locationLatitude,
                style: const TextStyle(fontSize: 14),
                decoration: _compactInput('Latitude', hint: '14.5995'),
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                  signed: true,
                ),
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: TextField(
                controller: _locationLongitude,
                style: const TextStyle(fontSize: 14),
                decoration: _compactInput('Longitude', hint: '120.9842'),
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                  signed: true,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          'Geofence: ${_locationGeofence.round()}m',
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
        ),
        Slider(
          value: _locationGeofence,
          min: 20,
          max: 200,
          divisions: 36,
          label: '${_locationGeofence.round()}m',
          onChanged: (value) => setState(() => _locationGeofence = value),
        ),
        Text(
          'Range: 20m – 200m',
          style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
        ),
        const SizedBox(height: 10),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: _busy || !_locationCanSave ? null : _saveLocation,
            style: _primaryButtonStyle,
            child: const Text('Save Location'),
          ),
        ),
      ],
    );
  }

  Widget _buildReviewStep() {
    final steps = (_setupStatus?['steps'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .where((step) => step['key'] != 'review');
    final missingItems =
        (_setupStatus?['missing_items'] as List<dynamic>? ?? const [])
            .whereType<String>()
            .toList();
    final ready = canCompleteSetup(_setupStatus);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _infoBox(
          'Review your setup and finish when required steps are complete.',
        ),
        const SizedBox(height: _fieldGap),
        ...steps.map(
          (step) => Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text(
              '${step['complete'] == true ? '✓' : '✗'} ${step['label']}',
              style: const TextStyle(fontSize: 13),
            ),
          ),
        ),
        if (!ready && missingItems.isNotEmpty) ...[
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFFFFFBEB),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFFFDE68A)),
            ),
            child: Text(
              'Required: ${missingItems.join(', ')}',
              style: const TextStyle(color: Color(0xFF92400E), fontSize: 12),
            ),
          ),
        ],
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: _busy || !ready ? null : _finishSetup,
            style: _primaryButtonStyle,
            child: const Text('Mark Setup Complete'),
          ),
        ),
        const SizedBox(height: 6),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton(
            style: OutlinedButton.styleFrom(
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.symmetric(vertical: 10),
            ),
            onPressed: () => context.go('/owner/home'),
            child:
                const Text('Go to Dashboard', style: TextStyle(fontSize: 13)),
          ),
        ),
      ],
    );
  }

  Widget _buildFooter() {
    if (_step >= setupWizardStepLabels.length - 1) {
      return const SizedBox.shrink();
    }

    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border(top: BorderSide(color: Colors.grey.shade200)),
        ),
        child: Row(
          children: [
            OutlinedButton(
              style: OutlinedButton.styleFrom(
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(horizontal: 12),
              ),
              onPressed: _step == 0 ? null : () => setState(() => _step -= 1),
              child: const Text('Back', style: TextStyle(fontSize: 13)),
            ),
            const Spacer(),
            TextButton(
              style: TextButton.styleFrom(
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(horizontal: 8),
              ),
              onPressed: _busy
                  ? null
                  : () => setState(
                        () => _step = clampSetupStep(_step + 1),
                      ),
              child: const Text('Skip for Now', style: TextStyle(fontSize: 13)),
            ),
            if (_currentStepCanContinue()) ...[
              const SizedBox(width: 6),
              FilledButton(
                onPressed: _busy ? null : _handleContinue,
                style: _primaryButtonStyle.copyWith(
                  minimumSize: const WidgetStatePropertyAll(Size(0, 38)),
                  padding: const WidgetStatePropertyAll(
                    EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  ),
                ),
                child: const Text('Continue', style: TextStyle(fontSize: 13)),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _labeledNumberField(String label, TextEditingController controller) {
    return TextField(
      controller: controller,
      style: const TextStyle(fontSize: 14),
      decoration: _compactInput(label),
      keyboardType: TextInputType.number,
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
        style:
            TextStyle(fontSize: 11, height: 1.35, color: Colors.grey.shade600),
      ),
    );
  }
}
