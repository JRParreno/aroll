import 'package:aroll_mobile/core/app_state.dart';
import 'package:aroll_mobile/core/di/injection.dart';
import 'package:aroll_mobile/core/location/business_location_defaults.dart';
import 'package:aroll_mobile/core/location/business_location_geocoding.dart';
import 'package:aroll_mobile/core/location/employee_location_service.dart';
import 'package:aroll_mobile/data/repositories/owner_repository.dart';
import 'package:aroll_mobile/presentation/owner/setup/holiday_setup_section.dart';
import 'package:aroll_mobile/presentation/owner/setup/setup_ui.dart';
import 'package:aroll_mobile/presentation/owner/setup/setup_wizard_constants.dart';
import 'package:aroll_mobile/presentation/owner/widgets/business_location_map_picker.dart';
import 'package:aroll_mobile/presentation/shared/app_ui.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';

class OwnerSetupWizardScreen extends StatefulWidget {
  const OwnerSetupWizardScreen({super.key, this.initialStep = -1});

  final int initialStep;

  @override
  State<OwnerSetupWizardScreen> createState() => _OwnerSetupWizardScreenState();
}

class _OwnerSetupWizardScreenState extends State<OwnerSetupWizardScreen> {
  static const _fieldGap = SetupUi.fieldGap;
  static const _cardPadding = 16.0;

  final _repo = sl<OwnerRepository>();

  late int _step;
  bool _loading = true;
  bool _busy = false;
  String? _loadError;

  Map<String, dynamic>? _setupStatus;
  Map<String, dynamic>? _businessSettings;
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
  String _holidayRulesMode = 'philippine_labor';
  bool _payrollLateDeductionEnabled = true;
  final _payrollLateDeductionRate = TextEditingController(text: '1');
  bool _payrollOvertimeEnabled = true;
  final _payrollOvertimeRate = TextEditingController(text: '1');
  bool _payrollLateOtBalancing = false;

  final _attEarlyClockIn = TextEditingController(text: '15');
  final _attOnTimeGrace = TextEditingController(text: '10');
  final _attHalfDay = TextEditingController(text: '120');
  final _attAbsent = TextEditingController(text: '240');
  final _attAbsentPercent = TextEditingController(text: '25');
  final _attHalfDayPercent = TextEditingController(text: '50');
  bool _attEarlyOutDeductionEnabled = false;
  final _attEarlyOutDeductionRate = TextEditingController(text: '2');
  bool _attOvertimeEnabled = true;
  final _attOvertimeMinimum = TextEditingController(text: '30');
  final _attMaximumOvertime = TextEditingController(text: '180');
  String _attMissingClockOutPolicy = 'auto_clock_out';
  bool _attAttendanceBasedSalaryEnabled = true;

  final _restPremiumPercent = TextEditingController(text: '30');

  final _locationLabel = TextEditingController(text: 'Main');
  final _locationAddress = TextEditingController();
  final _locationLatitude = TextEditingController();
  final _locationLongitude = TextEditingController();
  double _locationGeofence = kDefaultGeofenceRadiusM.toDouble();
  bool _locationLocating = false;
  bool _locationAddressEditedManually = false;

  final _locationService = EmployeeLocationService();

  @override
  void initState() {
    super.initState();
    _step = widget.initialStep < 0 ? -1 : clampSetupStep(widget.initialStep);
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
    _attAbsentPercent.dispose();
    _attHalfDayPercent.dispose();
    _attEarlyOutDeductionRate.dispose();
    _attOvertimeMinimum.dispose();
    _attMaximumOvertime.dispose();
    _restPremiumPercent.dispose();
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
        _repo.businessSettings(),
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
        _businessSettings = results[7] as Map<String, dynamic>;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadError = 'Unable to load setup. Please try again.';
      });
    }
  }

  void _applyPayroll(Map<String, dynamic> payroll) {
    _payPeriodType = '${payroll['pay_period_type'] ?? 'monthly'}';
    final payday = payroll['next_payday_date'] as String?;
    _nextPaydayDate =
        payday == null || payday.isEmpty ? null : DateTime.tryParse(payday);
    _autoResetPayrollCycle = payroll['auto_reset_payroll_cycle'] != false;
    _holidayRulesMode =
        payroll['holiday_rules_mode'] == 'custom_company'
            ? 'custom_company'
            : 'philippine_labor';
    _payrollLateDeductionEnabled = payroll['late_deduction_enabled'] != false;
    _payrollLateDeductionRate.text =
        '${payroll['late_deduction_per_minute'] ?? 1}';
    _payrollOvertimeEnabled = payroll['overtime_enabled'] != false;
    _payrollOvertimeRate.text = '${payroll['overtime_per_minute'] ?? 1}';
    _payrollLateOtBalancing =
        payroll['enable_late_overtime_balancing'] == true;
  }

  void _applyAttendance(Map<String, dynamic> attendance) {
    _attEarlyClockIn.text = '${attendance['early_clock_in_minutes'] ?? 15}';
    _attOnTimeGrace.text = '${attendance['on_time_grace_minutes'] ?? 10}';
    _attHalfDay.text = '${attendance['half_day_threshold_minutes'] ?? 120}';
    _attAbsent.text = '${attendance['absent_threshold_minutes'] ?? 240}';
    _attAbsentPercent.text = '${attendance['absent_threshold_percent'] ?? 25}';
    _attHalfDayPercent.text =
        '${attendance['half_day_threshold_percent'] ?? 50}';
    _attEarlyOutDeductionEnabled =
        attendance['early_out_deduction_enabled'] == true;
    _attEarlyOutDeductionRate.text =
        '${attendance['early_out_deduction_per_minute'] ?? 2}';
    _attOvertimeEnabled = attendance['overtime_enabled'] != false;
    _attOvertimeMinimum.text =
        '${attendance['overtime_minimum_minutes'] ?? 30}';
    _attMaximumOvertime.text =
        '${attendance['maximum_overtime_minutes'] ?? 180}';
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
    _locationAddressEditedManually = false;
  }

  void _applyRestDay(Map<String, dynamic> restDay) {
    _restPremiumPercent.text = '${restDay['rest_day_premium_percent'] ?? 30}';
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
      (double.tryParse(_payrollOvertimeRate.text) ?? -1) >= 0 &&
      (double.tryParse(_restPremiumPercent.text) ?? -1) >= 0;

  bool get _locationCanSave =>
      _locationAddress.text.trim().length >= 5 &&
      _locationLatitude.text.trim().isNotEmpty &&
      _locationLongitude.text.trim().isNotEmpty &&
      _locationGeofence >= kMinGeofenceRadiusM &&
      _locationGeofence <= kMaxGeofenceRadiusM;

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
      _showSnack('Work shift added');
      _shifts = await _repo.shifts();
      await _refreshSetupStatus();
      return true;
    } catch (_) {
      _showSnack('Could not add work shift');
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
      _showSnack('Could not remove work shift');
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
      _showSnack('Job role added');
      final positions = await _repo.positions();
      await _refreshSetupStatus();
      if (!mounted) return false;
      setState(() => _positions = positions);
      return true;
    } on DioException catch (e) {
      _showSnack(_errorMessageFromDio(e, fallback: 'Could not add job role'));
      return false;
    } catch (_) {
      _showSnack('Could not add job role');
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
      _showSnack('Could not remove job role');
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
        'holiday_rules_mode': _holidayRulesMode,
        'late_deduction_enabled': _payrollLateDeductionEnabled,
        'late_deduction_per_minute':
            double.parse(_payrollLateDeductionRate.text),
        'overtime_enabled': _payrollOvertimeEnabled,
        'overtime_per_minute': double.parse(_payrollOvertimeRate.text),
        'enable_late_overtime_balancing': _payrollLateOtBalancing,
      });
      await _repo.updateRestDayPolicy({
        'rest_day_premium_percent': double.parse(_restPremiumPercent.text),
      });
      _showSnack('Pay settings saved');
      await _refreshSetupStatus();
      return true;
    } catch (_) {
      _showSnack('Could not save pay settings');
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
        'absent_threshold_percent': int.parse(_attAbsentPercent.text),
        'half_day_threshold_percent': int.parse(_attHalfDayPercent.text),
        'early_out_deduction_enabled': _attEarlyOutDeductionEnabled,
        'early_out_deduction_per_minute':
            double.parse(_attEarlyOutDeductionRate.text),
        'overtime_enabled': _attOvertimeEnabled,
        'overtime_minimum_minutes': int.parse(_attOvertimeMinimum.text),
        'maximum_overtime_minutes': int.parse(_attMaximumOvertime.text),
        'missing_clock_out_policy': _attMissingClockOutPolicy,
        'attendance_based_salary_enabled': _attAttendanceBasedSalaryEnabled,
      });
      _showSnack('Clock-in settings saved');
      await _refreshSetupStatus();
    } catch (_) {
      _showSnack('Could not save clock-in settings');
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
      _showSnack('Workplace location saved');
      await _refreshSetupStatus();
      return true;
    } catch (_) {
      _showSnack('Could not save workplace location');
      return false;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _useWizardCurrentLocation() async {
    setState(() => _locationLocating = true);
    try {
      final position = await _locationService.currentPosition();
      if (!mounted) return;
      setState(() {
        _locationLatitude.text = position.latitude.toStringAsFixed(6);
        _locationLongitude.text = position.longitude.toStringAsFixed(6);
      });
      if (!_locationAddressEditedManually) {
        final address = await reverseGeocodeAddress(
          position.latitude,
          position.longitude,
        );
        if (!mounted) return;
        if (address != null && address.trim().isNotEmpty) {
          setState(() => _locationAddress.text = address);
        }
      }
      _showSnack('Current location set');
    } catch (error) {
      if (!mounted) return;
      _showSnack('$error');
    } finally {
      if (mounted) setState(() => _locationLocating = false);
    }
  }

  Future<void> _onWizardMapPositionChanged(LatLng position) async {
    setState(() {
      _locationLatitude.text = position.latitude.toStringAsFixed(6);
      _locationLongitude.text = position.longitude.toStringAsFixed(6);
    });
    if (_locationAddressEditedManually) return;
    final address = await reverseGeocodeAddress(
      position.latitude,
      position.longitude,
    );
    if (!mounted || address == null || address.trim().isEmpty) return;
    setState(() => _locationAddress.text = address);
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
      _showSnack('Setup finished');
      context.go('/owner/home');
    } on DioException catch (e) {
      final missing = _missingItemsFromError(e);
      _showSnack(missing ?? 'Please finish the required setup steps first');
      await _refreshSetupStatus();
    } catch (_) {
      _showSnack('Please finish the required setup steps first');
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
      } else if (_step == 5 &&
          !isSetupStepComplete(_setupStatus, 'location') &&
          _locationCanSave) {
        saved = await _saveLocation();
      }
      if (!mounted || !saved) {
        if (!saved) _showSnack('Please save this step before continuing.');
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

  void _goToMenu() {
    setState(() => _step = -1);
  }

  void _handleBack() {
    if (_step >= 0) {
      _goToMenu();
      return;
    }
    if (context.canPop()) {
      context.pop();
    } else {
      context.go('/owner/setup');
    }
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
      backgroundColor: SetupUi.scaffold,
      appBar: AppBar(
        backgroundColor: SetupUi.scaffold,
        elevation: 0,
        scrolledUnderElevation: 0,
        toolbarHeight: 56,
        leading: IconButton(
          tooltip: 'Back',
          onPressed: _handleBack,
          icon: const Icon(Icons.arrow_back_rounded),
        ),
        title: Text(
          setupWizardScreenTitle(_step),
          style: const TextStyle(
            fontWeight: FontWeight.w800,
            fontSize: 18,
            color: AppColors.textPrimary,
          ),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: SetupUi.navy))
          : _loadError != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SetupInfoBanner(_loadError!, tone: SetupBannerTone.danger),
                        const SizedBox(height: 14),
                        FilledButton(
                          onPressed: _loadAll,
                          style: SetupUi.primaryButton,
                          child: const Text('Retry'),
                        ),
                      ],
                    ),
                  ),
                )
              : Column(
                  children: [
                    Expanded(
                      child: ListView(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                        children: [
                          if (_step < 0) ...[
                            _buildTitleSection(),
                            const SizedBox(height: 14),
                            _buildSetupMenu(),
                          ] else
                            _buildStepCard(),
                        ],
                      ),
                    ),
                    if (_step >= 0) _buildFooter(),
                  ],
                ),
    );
  }

  InputDecoration _compactInput(String label, {String? hint}) =>
      SetupUi.input(label, hint: hint);

  ButtonStyle get _primaryButtonStyle => SetupUi.primaryButton;

  Widget _compactSwitch({
    required String title,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return SetupCompactSwitch(
      title: title,
      value: value,
      onChanged: onChanged,
    );
  }

  Widget _buildTitleSection() {
    return const SetupSurfaceCard(
      child: SetupSectionHeader(
        icon: Icons.storefront_outlined,
        title: 'Business Setup',
        subtitle:
            'Choose a section below to configure. Each card opens its settings.',
      ),
    );
  }

  Widget _buildSetupMenu() {
    return Column(
      children: [
        for (var i = 0; i < setupMenuEntries.length; i++) ...[
          if (i > 0) const SizedBox(height: 10),
          _buildSetupMenuCard(setupMenuEntries[i]),
        ],
        if (canCompleteSetup(_setupStatus)) ...[
          const SizedBox(height: 10),
          _buildSetupMenuCard(
            const SetupMenuEntry(
              label: 'Review Your Setup',
              subtitle:
                  'Check the required steps and finish setting up your business.',
              stepIndex: 7,
              statusKey: 'review',
              icon: Icons.task_alt_outlined,
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildSetupMenuCard(SetupMenuEntry entry) {
    final hasStatus = entry.statusKey != null;
    final complete = hasStatus &&
        (entry.statusKey == 'review'
            ? canCompleteSetup(_setupStatus)
            : isSetupStepComplete(_setupStatus, entry.statusKey!));

    return SetupMenuCard(
      label: entry.label,
      subtitle: entry.subtitle,
      icon: entry.icon,
      complete: complete,
      showStatus: hasStatus && entry.statusKey != 'review',
      onTap: () => setState(() => _step = entry.stepIndex),
    );
  }

  Widget _buildStepCard() {
    final icon = switch (_step) {
      setupWizardBusinessInfoStep => Icons.business_rounded,
      0 => Icons.schedule_rounded,
      1 => Icons.badge_outlined,
      2 => Icons.payments_outlined,
      3 => Icons.fact_check_outlined,
      4 => Icons.event_outlined,
      5 => Icons.location_on_outlined,
      6 => Icons.task_alt_outlined,
      _ => Icons.settings_outlined,
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SetupSurfaceCard(
          child: SetupSectionHeader(
            icon: icon,
            title: setupWizardScreenTitle(_step),
            subtitle: setupWizardStepHelp(_step),
          ),
        ),
        const SizedBox(height: 12),
        SetupSurfaceCard(
          padding: const EdgeInsets.all(_cardPadding),
          child: _buildStepContent(),
        ),
      ],
    );
  }

  Widget _buildStepContent() {
    switch (_step) {
      case setupWizardBusinessInfoStep:
        return _buildBusinessInfoStep();
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
        return _buildLocationStep();
      case 6:
        return _buildReviewStep();
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _buildShiftsStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SetupPanel(
          title: 'Add a work shift',
          icon: Icons.schedule_rounded,
          subtitle: 'Create the shift times your team usually follows.',
          children: [
            TextField(
              controller: _shiftName,
              style: const TextStyle(fontSize: 14),
              decoration: _compactInput('Shift name', hint: 'Morning Shift'),
            ),
            const SizedBox(height: _fieldGap),
            DropdownButtonFormField<String>(
              initialValue: _shiftType,
              isDense: true,
              decoration: _compactInput('Shift type'),
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
                    style: SetupUi.secondaryButton,
                    onPressed: () => _pickTime(
                      initial: _shiftStart,
                      onPicked: (value) => setState(() => _shiftStart = value),
                    ),
                    child: Text('Start ${formatApiTime(_shiftStart)}'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton(
                    style: SetupUi.secondaryButton,
                    onPressed: () => _pickTime(
                      initial: _shiftEnd,
                      onPicked: (value) => setState(() => _shiftEnd = value),
                    ),
                    child: Text('End ${formatApiTime(_shiftEnd)}'),
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
                    decoration: _compactInput('Break minutes'),
                    keyboardType: TextInputType.number,
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: TextField(
                    controller: _shiftCapacity,
                    style: const TextStyle(fontSize: 14),
                    decoration: _compactInput('Employees needed'),
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
                child: const Text('Add work shift'),
              ),
            ),
          ],
        ),
        if (_shifts.isNotEmpty) ...[
          const SizedBox(height: 14),
          const SetupListLabel('Added shifts'),
          ..._shifts.map(
            (shift) => SetupListTileCard(
              leadingIcon: Icons.schedule_rounded,
              title: '${shift['name']}',
              subtitle: '${shift['start_time']} – ${shift['end_time']}',
              trailing: TextButton(
                style: SetupUi.ghostButton.copyWith(
                  foregroundColor:
                      const WidgetStatePropertyAll(AppColors.danger),
                ),
                onPressed:
                    _busy ? null : () => _removeShift('${shift['id']}'),
                child: const Text('Remove'),
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
        SetupPanel(
          title: 'Add a job role',
          icon: Icons.badge_outlined,
          subtitle: 'Set the role name and daily pay for this position.',
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 3,
                  child: TextField(
                    controller: _positionTitle,
                    style: const TextStyle(fontSize: 14),
                    decoration: _compactInput('Job role name'),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  flex: 2,
                  child: TextField(
                    controller: _positionRate,
                    style: const TextStyle(fontSize: 14),
                    decoration: _compactInput('Daily pay (₱)'),
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
                child: const Text('Add job role'),
              ),
            ),
          ],
        ),
        if (_positions.isNotEmpty) ...[
          const SizedBox(height: 14),
          const SetupListLabel('Added roles'),
          ..._positions.map(
            (position) => SetupListTileCard(
              leadingIcon: Icons.badge_outlined,
              title: '${position['title']}',
              subtitle: '₱${position['daily_rate']}/day',
              trailing: TextButton(
                style: SetupUi.ghostButton.copyWith(
                  foregroundColor:
                      const WidgetStatePropertyAll(AppColors.danger),
                ),
                onPressed:
                    _busy ? null : () => _removePosition('${position['id']}'),
                child: const Text('Remove'),
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
        SetupPanel(
          title: 'Pay schedule',
          icon: Icons.calendar_month_outlined,
          subtitle: 'Choose how often employees get paid.',
          children: [
            DropdownButtonFormField<String>(
              initialValue: _payPeriodType,
              isDense: true,
              decoration: _compactInput('How often employees get paid'),
              items: const [
                DropdownMenuItem(value: 'weekly', child: Text('Weekly')),
                DropdownMenuItem(
                  value: 'semi_monthly',
                  child: Text('Twice a month'),
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
                style: SetupUi.secondaryButton,
                onPressed: _pickPayday,
                child: Text(
                  _nextPaydayDate == null
                      ? 'Choose next payday'
                      : 'Next payday: ${formatApiDate(_nextPaydayDate!)}',
                ),
              ),
            ),
            const SizedBox(height: 4),
            _compactSwitch(
              title: 'Start a new pay period after payday',
              value: _autoResetPayrollCycle,
              onChanged: (value) =>
                  setState(() => _autoResetPayrollCycle = value),
            ),
          ],
        ),
        const SizedBox(height: 10),
        SetupPanel(
          title: 'Holiday pay rules',
          icon: Icons.celebration_outlined,
          subtitle: 'Philippine labor rules or custom company policy.',
          children: [
            DropdownButtonFormField<String>(
              initialValue: _holidayRulesMode,
              isDense: true,
              decoration: _compactInput('Holiday rules'),
              items: const [
                DropdownMenuItem(
                  value: 'philippine_labor',
                  child: Text('Philippine labor rules'),
                ),
                DropdownMenuItem(
                  value: 'custom_company',
                  child: Text('Custom company rules'),
                ),
              ],
              onChanged: (value) {
                if (value != null) {
                  setState(() => _holidayRulesMode = value);
                }
              },
            ),
          ],
        ),
        const SizedBox(height: 10),
        SetupPanel(
          title: 'Pay rules',
          icon: Icons.rule_outlined,
          subtitle: 'Control late deductions and overtime pay.',
          children: [
            _compactSwitch(
              title: 'Pay less when late',
              value: _payrollLateDeductionEnabled,
              onChanged: (value) =>
                  setState(() => _payrollLateDeductionEnabled = value),
            ),
            TextField(
              controller: _payrollLateDeductionRate,
              enabled: _payrollLateDeductionEnabled,
              style: const TextStyle(fontSize: 14),
              decoration: _compactInput('Amount per late minute (₱)'),
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
            ),
            const SizedBox(height: 4),
            _compactSwitch(
              title: 'Pay for overtime',
              value: _payrollOvertimeEnabled,
              onChanged: (value) =>
                  setState(() => _payrollOvertimeEnabled = value),
            ),
            TextField(
              controller: _payrollOvertimeRate,
              enabled: _payrollOvertimeEnabled,
              style: const TextStyle(fontSize: 14),
              decoration: _compactInput('Extra pay per overtime minute (₱)'),
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
            ),
            const SizedBox(height: 4),
            _compactSwitch(
              title: 'Late–OT Balancing',
              value: _payrollLateOtBalancing && _payrollOvertimeEnabled,
              onChanged: (value) {
                if (!_payrollOvertimeEnabled) return;
                setState(() => _payrollLateOtBalancing = value);
              },
            ),
            Text(
              'When enabled, overtime minutes are first used to recover late '
              'arrival. Only the remaining overtime minutes are paid.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: const Color(0xFF6B7280),
                  ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        _buildRestDayFields(),
        const SizedBox(height: 10),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: _busy || !_payrollFormValid ? null : _savePayroll,
            style: _primaryButtonStyle,
            child: const Text('Save Pay Settings'),
          ),
        ),
      ],
    );
  }

  Widget _buildAttendanceStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SetupPanel(
          title: 'Clock-in rules',
          icon: Icons.fact_check_outlined,
          subtitle:
              'Configure early, late, absent, half-day, overtime, and incomplete cutoffs.',
          children: [
            Row(
              children: [
                Expanded(
                  child: _labeledNumberField(
                    'Early clock-in window (min)',
                    _attEarlyClockIn,
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: _labeledNumberField(
                    'Extra minutes before late',
                    _attOnTimeGrace,
                  ),
                ),
              ],
            ),
            const SizedBox(height: _fieldGap),
            Row(
              children: [
                Expanded(
                  child: _labeledNumberField(
                    'Absent if under (% of shift)',
                    _attAbsentPercent,
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: _labeledNumberField(
                    'Half-day if under (% of shift)',
                    _attHalfDayPercent,
                  ),
                ),
              ],
            ),
            const SizedBox(height: _fieldGap),
            Row(
              children: [
                Expanded(
                  child: _labeledNumberField(
                    'Payroll half-day cutoff (min)',
                    _attHalfDay,
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: _labeledNumberField(
                    'Payroll absent cutoff (min)',
                    _attAbsent,
                  ),
                ),
              ],
            ),
            const SizedBox(height: _fieldGap),
            Row(
              children: [
                Expanded(
                  child: _labeledNumberField(
                    'Minimum overtime minutes',
                    _attOvertimeMinimum,
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: _labeledNumberField(
                    'Maximum overtime duration (min)',
                    _attMaximumOvertime,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Maximum overtime duration: how long an employee may stay '
              'clocked in after shift end before attendance becomes Incomplete.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: const Color(0xFF6B7280),
                  ),
            ),
          ],
        ),
        const SizedBox(height: _fieldGap),
        _infoBox(
          'Absent/half-day status use percent of each scheduled shift. '
          'Maximum overtime duration is an attendance cutoff only. '
          'Overtime pay uses ₱${_payrollOvertimeRate.text} per minute '
          '(${_payrollOvertimeEnabled ? 'turned on' : 'turned off'} in pay settings).',
        ),
        const SizedBox(height: 10),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: _busy ? null : _saveAttendance,
            style: _primaryButtonStyle,
            child: const Text('Save Clock-In Settings'),
          ),
        ),
      ],
    );
  }

  Widget _buildRestDayFields() {
    return SetupPanel(
      title: 'Extra pay on rest days',
      icon: Icons.weekend_outlined,
      subtitle:
          'Set the extra pay when an employee works on an approved rest day.',
      children: [
        TextField(
          controller: _restPremiumPercent,
          style: const TextStyle(fontSize: 14),
          decoration: _compactInput('Extra pay (%)'),
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
        ),
      ],
    );
  }

  Widget _buildLocationStep() {
    final latitude = double.tryParse(_locationLatitude.text.trim());
    final longitude = double.tryParse(_locationLongitude.text.trim());

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SetupInfoBanner(
          'Set your workplace on the map and choose how close employees must '
          'be before they can clock in or clock out.',
        ),
        const SizedBox(height: _fieldGap),
        SetupPanel(
          title: 'Workplace on map',
          icon: Icons.location_on_outlined,
          subtitle: 'Pin your business and set the attendance distance.',
          children: [
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                style: SetupUi.secondaryButton,
                onPressed: _locationLocating || _busy
                    ? null
                    : _useWizardCurrentLocation,
                icon: _locationLocating
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: SetupUi.navy,
                        ),
                      )
                    : const Icon(Icons.my_location_rounded, size: 18),
                label: const Text('Use my current location'),
              ),
            ),
            const SizedBox(height: _fieldGap),
            ClipRRect(
              borderRadius: BorderRadius.circular(SetupUi.panelRadius),
              child: BusinessLocationMapPicker(
                latitude: latitude,
                longitude: longitude,
                geofenceRadiusM: _locationGeofence.round(),
                onPositionChanged: _onWizardMapPositionChanged,
                height: 220,
              ),
            ),
            const SizedBox(height: _fieldGap),
            TextField(
              controller: _locationAddress,
              style: const TextStyle(fontSize: 14),
              decoration:
                  _compactInput('Address', hint: '123 Main St, Manila'),
              onChanged: (_) => setState(() {
                _locationAddressEditedManually = true;
              }),
            ),
            const SizedBox(height: 8),
            Text(
              'Allowed work area: ${_locationGeofence.round()}m',
              style: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
            ),
            SliderTheme(
              data: SliderTheme.of(context).copyWith(
                activeTrackColor: SetupUi.navy,
                inactiveTrackColor: const Color(0xFFE8EEF4),
                thumbColor: SetupUi.navy,
                overlayColor: SetupUi.navy.withValues(alpha: 0.12),
                valueIndicatorColor: SetupUi.navy,
              ),
              child: Slider(
                value: _locationGeofence,
                min: kMinGeofenceRadiusM.toDouble(),
                max: kMaxGeofenceRadiusM.toDouble(),
                divisions: kMaxGeofenceRadiusM - kMinGeofenceRadiusM,
                label: '${_locationGeofence.round()}m',
                onChanged: (value) =>
                    setState(() => _locationGeofence = value),
              ),
            ),
            Text(
              'Allowed distance: ${kMinGeofenceRadiusM}m – ${kMaxGeofenceRadiusM}m',
              style: appMutedStyle().copyWith(fontSize: 11.5),
            ),
            if (isSmallGeofenceRadius(_locationGeofence)) ...[
              const SizedBox(height: 8),
              const SetupInfoBanner(
                'Tip: A very small work area (under 20 m) can be hard for phones '
                'to match because location can drift. Place the pin outdoors when '
                'possible. 25–50 m is usually more reliable.',
                tone: SetupBannerTone.warning,
              ),
            ],
          ],
        ),
        const SizedBox(height: 10),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: _busy || !_locationCanSave ? null : _saveLocation,
            style: _primaryButtonStyle,
            child: const Text('Save Workplace Location'),
          ),
        ),
      ],
    );
  }

  Widget _buildBusinessInfoStep() {
    final data = _businessSettings ?? const {};
    final fields = [
      ('Business Name', data['business_name'], Icons.store_outlined),
      ('Business Code', data['business_code'], Icons.qr_code_2_rounded),
      ('Business Type', data['business_type'], Icons.category_outlined),
      ('Address', data['address'], Icons.place_outlined),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final field in fields)
          SetupListTileCard(
            leadingIcon: field.$3,
            title: field.$1,
            subtitle: field.$2 == null || '${field.$2}'.trim().isEmpty
                ? 'Not set'
                : '${field.$2}',
          ),
        const SetupInfoBanner(
          'Your business details were set during registration. '
          'Use Settings anytime to update your account or pay preferences.',
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
        const SetupInfoBanner(
          'Review your setup and finish when the required steps are done.',
        ),
        const SizedBox(height: _fieldGap),
        ...steps.map(
          (step) {
            final complete = step['complete'] == true;
            return SetupListTileCard(
              leadingIcon: complete
                  ? Icons.check_circle_rounded
                  : Icons.radio_button_unchecked_rounded,
              iconColor: complete
                  ? const Color(0xFF059669)
                  : const Color(0xFFC2410C),
              iconBackground: complete
                  ? const Color(0xFFECFDF5)
                  : const Color(0xFFFFF7ED),
              title: '${step['label']}',
              subtitle: complete ? 'Completed' : 'Incomplete',
            );
          },
        ),
        if (!ready && missingItems.isNotEmpty) ...[
          const SizedBox(height: 4),
          SetupInfoBanner(
            'Still needed: ${missingItems.join(', ')}',
            tone: SetupBannerTone.warning,
          ),
        ],
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: _busy || !ready ? null : _finishSetup,
            style: _primaryButtonStyle,
            child: const Text('Finish Setup'),
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton(
            style: SetupUi.secondaryButton,
            onPressed: () => context.go('/owner/home'),
            child: const Text('Go to Dashboard'),
          ),
        ),
      ],
    );
  }

  Widget _buildFooter() {
    if (_step >= setupWizardStepLabels.length - 1 ||
        _step == setupWizardBusinessInfoStep) {
      return const SizedBox.shrink();
    }

    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
        decoration: const BoxDecoration(
          color: Colors.white,
          border: Border(top: BorderSide(color: AppColors.border)),
          boxShadow: [
            BoxShadow(
              color: Color(0x0A000000),
              blurRadius: 10,
              offset: Offset(0, -2),
            ),
          ],
        ),
        child: Row(
          children: [
            const Spacer(),
            TextButton(
              style: SetupUi.ghostButton,
              onPressed: _busy
                  ? null
                  : () => setState(
                        () => _step = clampSetupStep(_step + 1),
                      ),
              child: const Text('Skip for Now'),
            ),
            if (_currentStepCanContinue()) ...[
              const SizedBox(width: 8),
              FilledButton(
                onPressed: _busy ? null : _handleContinue,
                style: SetupUi.primaryButton.copyWith(
                  minimumSize: const WidgetStatePropertyAll(Size(0, 40)),
                ),
                child: const Text('Continue'),
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

  Widget _infoBox(String text) => SetupInfoBanner(text);
}
