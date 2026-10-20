import 'package:aroll_mobile/core/app_state.dart';
import 'package:aroll_mobile/core/di/injection.dart';
import 'package:aroll_mobile/core/location/business_location_defaults.dart';
import 'package:aroll_mobile/core/location/business_location_geocoding.dart';
import 'package:aroll_mobile/core/location/employee_location_service.dart';
import 'package:aroll_mobile/data/repositories/owner_repository.dart';
import 'package:aroll_mobile/presentation/owner/owner_leave_allowances_section.dart';
import 'package:aroll_mobile/presentation/owner/owner_shell.dart';
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
  final _positionDailyRate = TextEditingController();
  final _positionHourlyRate = TextEditingController();
  final _positionDescription = TextEditingController();
  String _positionEmploymentType = 'full_time';
  bool _positionEnableDaily = true;
  bool _positionEnableHourly = false;

  String _payPeriodType = 'monthly';
  DateTime? _nextPaydayDate;
  bool _autoResetPayrollCycle = true;
  String _holidayRulesMode = 'philippine_labor';
  bool _payrollLateDeductionEnabled = true;
  final _payrollLateDeductionRate = TextEditingController(text: '1');
  bool _payrollOvertimeEnabled = true;
  String _payrollOvertimeMethod = 'flat_per_minute';
  final _payrollOvertimeRate = TextEditingController(text: '1');
  bool _payrollLateOtBalancing = false;
  bool _payrollOtApprovalRequired = false;

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
  bool _breaktimeIsPaid = false;

  final _restPremiumPercent = TextEditingController(text: '30');
  final _leaveNotice = TextEditingController(text: '0');
  List<Map<String, dynamic>> _leaveItems = const [];
  Map<String, bool> _leaveDraft = {};
  Map<String, bool> _leaveSaved = {};
  int _leaveSavedNotice = 0;

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
    _positionDailyRate.dispose();
    _positionHourlyRate.dispose();
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
    _leaveNotice.dispose();
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
      final required = await Future.wait([
        _repo.setupStatus(),
        _repo.shifts(),
        _repo.positions(),
      ]);
      final payroll = await _tryLoad(_repo.payrollConfig);
      final attendance = await _tryLoad(_repo.attendancePolicy);
      final location = await _tryLoad(_repo.location);
      final restDay = await _tryLoad(_repo.restDayPolicy);
      final settings = await _tryLoad(_repo.businessSettings);
      final leave = await _tryLoad(_repo.leavePolicy);
      if (!mounted) return;
      if (payroll != null) _applyPayroll(payroll);
      if (attendance != null) _applyAttendance(attendance);
      if (location != null) _applyLocation(location);
      if (restDay != null) _applyRestDay(restDay);
      if (leave != null) _applyLeavePolicy(leave);

      setState(() {
        _setupStatus = required[0] as Map<String, dynamic>;
        _shifts = required[1] as List<Map<String, dynamic>>;
        _positions = required[2] as List<Map<String, dynamic>>;
        _businessSettings = settings;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadError = error is DioException
            ? _errorMessageFromDio(
                error,
                fallback: 'Unable to load setup. Please try again.',
              )
            : 'Unable to load setup. Please try again.';
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
    _payrollOvertimeMethod =
        payroll['overtime_calculation_method'] == 'hourly_statutory'
            ? 'hourly_statutory'
            : 'flat_per_minute';
    _payrollOvertimeRate.text = '${payroll['overtime_per_minute'] ?? 1}';
    _payrollLateOtBalancing =
        payroll['enable_late_overtime_balancing'] == true;
    _payrollOtApprovalRequired =
        payroll['overtime_approval_required'] == true;
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
    _breaktimeIsPaid = attendance['breaktime_is_paid'] == true;
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

  Future<T?> _tryLoad<T>(Future<T> Function() load) async {
    try {
      return await load();
    } catch (_) {
      return null;
    }
  }

  void _applyLeavePolicy(Map<String, dynamic> data) {
    final items = (data['items'] as List? ?? const [])
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
    final next = <String, bool>{};
    for (final item in items) {
      next['${item['leave_type']}'] = item['is_paid'] == true;
    }
    _leaveItems = items;
    _leaveDraft = Map<String, bool>.from(next);
    _leaveSaved = Map<String, bool>.from(next);
    final notice = data['minimum_advance_notice_days'] as int? ?? 0;
    _leaveSavedNotice = notice;
    _leaveNotice.text = '$notice';
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

  bool get _positionDraftValid {
    if (_positionTitle.text.trim().isEmpty) return false;
    if (!_positionEnableDaily && !_positionEnableHourly) return false;
    if (_positionEnableDaily &&
        (double.tryParse(_positionDailyRate.text) ?? 0) <= 0) {
      return false;
    }
    if (_positionEnableHourly &&
        (double.tryParse(_positionHourlyRate.text) ?? 0) <= 0) {
      return false;
    }
    return true;
  }

  List<Map<String, dynamic>> _buildPayConfigs({
    required bool enableDaily,
    required String dailyRate,
    required bool enableHourly,
    required String hourlyRate,
  }) {
    final configs = <Map<String, dynamic>>[];
    if (enableDaily) {
      configs.add({
        'pay_basis': 'daily',
        'rate': double.parse(dailyRate.trim()),
      });
    }
    if (enableHourly) {
      configs.add({
        'pay_basis': 'hourly',
        'rate': double.parse(hourlyRate.trim()),
      });
    }
    return configs;
  }

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
      case setupWizardLeavePolicyStep:
        return true;
      case setupWizardLocationStep:
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

  String _shiftTimeRangeLabel(Map<String, dynamic> shift) {
    final start = parseApiTime('${shift['start_time']}');
    final end = parseApiTime('${shift['end_time']}');
    if (start == null || end == null) {
      return '${shift['start_time']} – ${shift['end_time']}';
    }
    return '${start.format(context)} – ${end.format(context)}';
  }

  Future<void> _editShiftTimes(Map<String, dynamic> shift) async {
    final initialStart = parseApiTime('${shift['start_time']}') ??
        const TimeOfDay(hour: 8, minute: 30);
    final initialEnd = parseApiTime('${shift['end_time']}') ??
        const TimeOfDay(hour: 12, minute: 30);
    final timesLocked = shift['has_in_progress_today'] == true;
    final result = await showDialog<_EditShiftTimesDialogResult>(
      context: context,
      builder: (dialogContext) {
        return _EditShiftTimesDialog(
          shiftName: '${shift['name']}',
          initialStart: initialStart,
          initialEnd: initialEnd,
          initialCapacityText: '${shift['employee_capacity'] ?? 1}',
          capacityDecoration: _compactInput('Employee Capacity'),
          timesLocked: timesLocked,
        );
      },
    );
    if (result == null) return;
    if (result.capacity < 1) {
      _showSnack('Employee capacity must be a whole number of at least 1');
      return;
    }

    setState(() => _busy = true);
    try {
      if (timesLocked) {
        await _repo.updateShift(
          shiftId: '${shift['id']}',
          employeeCapacity: result.capacity,
        );
      } else {
        await _repo.updateShift(
          shiftId: '${shift['id']}',
          startTime: formatApiTime(result.start),
          endTime: formatApiTime(result.end),
          employeeCapacity: result.capacity,
        );
      }
      _shifts = await _repo.shifts();
      _showSnack('Shift updated');
    } on DioException catch (error) {
      _showSnack(
        _errorMessageFromDio(error, fallback: 'Could not update shift'),
      );
    } catch (_) {
      _showSnack('Could not update shift');
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
        employmentType: _positionEmploymentType,
        payConfigs: _buildPayConfigs(
          enableDaily: _positionEnableDaily,
          dailyRate: _positionDailyRate.text,
          enableHourly: _positionEnableHourly,
          hourlyRate: _positionHourlyRate.text,
        ),
        description: _positionDescription.text.trim(),
      );
      _positionTitle.clear();
      _positionDailyRate.clear();
      _positionHourlyRate.clear();
      _positionDescription.clear();
      setState(() {
        _positionEnableDaily = true;
        _positionEnableHourly = false;
      });
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

  Future<void> _editPositionPayConfigs(Map<String, dynamic> position) async {
    final configs = (position['pay_configs'] as List?) ?? const [];
    var enableDaily = false;
    var enableHourly = false;
    final dailyCtrl = TextEditingController();
    final hourlyCtrl = TextEditingController();
    for (final raw in configs) {
      if (raw is! Map) continue;
      final basis = '${raw['pay_basis']}';
      if (basis == 'daily') {
        enableDaily = true;
        dailyCtrl.text = '${raw['rate'] ?? ''}';
      }
      if (basis == 'hourly') {
        enableHourly = true;
        hourlyCtrl.text = '${raw['rate'] ?? ''}';
      }
    }
    if (!enableDaily && !enableHourly) {
      if (position['daily_rate'] != null) {
        enableDaily = true;
        dailyCtrl.text = '${position['daily_rate']}';
      }
      if (position['hourly_rate'] != null) {
        enableHourly = true;
        hourlyCtrl.text = '${position['hourly_rate']}';
      }
    }
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setLocal) {
            final valid = (enableDaily || enableHourly) &&
                (!enableDaily ||
                    (double.tryParse(dailyCtrl.text) ?? 0) > 0) &&
                (!enableHourly ||
                    (double.tryParse(hourlyCtrl.text) ?? 0) > 0);
            return AlertDialog(
              title: Text('Edit rates · ${position['title']}'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Daily'),
                      value: enableDaily,
                      onChanged: (v) =>
                          setLocal(() => enableDaily = v ?? false),
                    ),
                    if (enableDaily)
                      TextField(
                        controller: dailyCtrl,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: const InputDecoration(
                          labelText: 'Daily amount (₱)',
                        ),
                        onChanged: (_) => setLocal(() {}),
                      ),
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Hourly'),
                      value: enableHourly,
                      onChanged: (v) =>
                          setLocal(() => enableHourly = v ?? false),
                    ),
                    if (enableHourly)
                      TextField(
                        controller: hourlyCtrl,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: const InputDecoration(
                          labelText: 'Hourly amount (₱)',
                        ),
                        onChanged: (_) => setLocal(() {}),
                      ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: !valid
                      ? null
                      : () => Navigator.pop(context, true),
                  child: const Text('Save'),
                ),
              ],
            );
          },
        );
      },
    );
    final dailyText = dailyCtrl.text;
    final hourlyText = hourlyCtrl.text;
    final keepDaily = enableDaily;
    final keepHourly = enableHourly;
    dailyCtrl.dispose();
    hourlyCtrl.dispose();
    if (saved != true) return;
    setState(() => _busy = true);
    try {
      await _repo.updatePosition(
        positionId: '${position['id']}',
        payConfigs: _buildPayConfigs(
          enableDaily: keepDaily,
          dailyRate: dailyText,
          enableHourly: keepHourly,
          hourlyRate: hourlyText,
        ),
      );
      _positions = await _repo.positions();
      _showSnack('Pay configurations updated');
      await _refreshSetupStatus();
    } on DioException catch (e) {
      _showSnack(
        _errorMessageFromDio(e, fallback: 'Could not update pay configurations'),
      );
    } catch (_) {
      _showSnack('Could not update pay configurations');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _classifyPosition(String id, String employmentType) async {
    setState(() => _busy = true);
    try {
      await _repo.updatePosition(
        positionId: id,
        employmentType: employmentType,
      );
      _positions = await _repo.positions();
      _showSnack('Job role classified');
      await _refreshSetupStatus();
    } on DioException catch (e) {
      _showSnack(_errorMessageFromDio(e, fallback: 'Could not update job role'));
    } catch (_) {
      _showSnack('Could not update job role');
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
        'overtime_calculation_method': _payrollOvertimeMethod,
        'enable_late_overtime_balancing': _payrollLateOtBalancing,
        'overtime_approval_required': _payrollOtApprovalRequired,
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

  bool get _leavePolicyDirty {
    if (_leaveDraft.length != _leaveSaved.length) return true;
    for (final entry in _leaveDraft.entries) {
      if (_leaveSaved[entry.key] != entry.value) return true;
    }
    return int.tryParse(_leaveNotice.text.trim()) != _leaveSavedNotice;
  }

  Future<bool> _saveLeavePolicy() async {
    final notice = int.tryParse(_leaveNotice.text.trim());
    if (notice == null || notice < 0 || notice > 365) {
      _showSnack('Advance notice must be a whole number from 0 to 365.');
      return false;
    }
    setState(() => _busy = true);
    try {
      final data = await _repo.updateLeavePolicy({
        'treatments': {
          for (final entry in _leaveDraft.entries)
            if (entry.key != 'unpaid') entry.key: entry.value,
        },
        'minimum_advance_notice_days': notice,
      });
      _applyLeavePolicy(data);
      _showSnack('Leave Policy saved');
      await _refreshSetupStatus();
      return true;
    } on DioException catch (e) {
      _showSnack(
        _errorMessageFromDio(e, fallback: 'Could not save Leave Policy'),
      );
      return false;
    } catch (_) {
      _showSnack('Could not save Leave Policy');
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
        // early_out_deduction_* is compatibility-only; undertime uses wage minute rate.
        'overtime_enabled': _attOvertimeEnabled,
        'overtime_minimum_minutes': int.parse(_attOvertimeMinimum.text),
        'maximum_overtime_minutes': int.parse(_attMaximumOvertime.text),
        'missing_clock_out_policy': _attMissingClockOutPolicy,
        'attendance_based_salary_enabled': _attAttendanceBasedSalaryEnabled,
        'breaktime_is_paid': _breaktimeIsPaid,
      });
      _showSnack('Time-in settings saved');
      await _refreshSetupStatus();
    } catch (_) {
      _showSnack('Could not save time-in settings');
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
      _showSnack(
        missing ??
            _errorMessageFromDio(
              e,
              fallback: 'Please finish the required setup steps first',
            ),
      );
      await _refreshSetupStatus();
    } catch (_) {
      _showSnack('Could not finish setup. Please try again.');
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
      if (detail is Map) {
        final title = detail['title']?.toString();
        final message = detail['message']?.toString();
        if (title != null && message != null) return '$title: $message';
        if (message != null && message.trim().isNotEmpty) return message;
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
      } else if (_step == setupWizardLocationStep &&
          !isSetupStepComplete(_setupStatus, 'location') &&
          _locationCanSave) {
        saved = await _saveLocation();
      } else if (_step == setupWizardLeavePolicyStep && _leavePolicyDirty) {
        saved = await _saveLeavePolicy();
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
      // Deep-linked onto this step (e.g. Schedule → New Shift → Work Shifts)
      // and still on that same step: pop back to the previous route instead of
      // switching to the in-wizard "Set Up Your Business" menu.
      if (widget.initialStep >= 0 &&
          _step == widget.initialStep &&
          context.canPop()) {
        context.pop();
        return;
      }
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

  bool get _showsWizardFooter {
    if (_loading || _loadError != null || _step < 0) return false;
    if (_step >= setupWizardStepLabels.length - 1) return false;
    if (_step == setupWizardBusinessInfoStep) return false;
    return true;
  }

  @override
  Widget build(BuildContext context) {
    return OwnerShell(
      selectedIndex: 2,
      title: setupWizardScreenTitle(_step),
      showBackButton: true,
      onBack: _handleBack,
      backgroundColor: SetupUi.scaffold,
      footer: _showsWizardFooter ? _buildFooter() : null,
      child: _loading
          ? Center(child: CircularProgressIndicator(color: SetupUi.navyOf(context)))
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
                          style: SetupUi.primaryButtonOf(context),
                          child: const Text('Retry'),
                        ),
                      ],
                    ),
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
                  children: [
                    if (_step < 0) ...[
                      const SizedBox(height: 14),
                      _buildSetupMenu(),
                    ] else
                      _buildStepCard(),
                  ],
                ),
    );
  }

  InputDecoration _compactInput(String label, {String? hint}) =>
      SetupUi.input(label, hint: hint);

  ButtonStyle get _primaryButtonStyle => SetupUi.primaryButtonOf(context);

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
              stepIndex: setupWizardReviewStep,
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
    final help = setupWizardStepHelp(_step);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (help.isNotEmpty) ...[
          SetupWizardStepIntro(help),
          const SizedBox(height: 12),
        ],
        SetupSurfaceCard(
          padding: const EdgeInsets.all(_cardPadding),
          child: _buildStepContent(),
        ),
        if (_step == setupWizardLeavePolicyStep) ...[
          const SizedBox(height: 12),
          const BusinessLeaveAllowancesSection(),
        ],
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
      case setupWizardLeavePolicyStep:
        return _buildLeavePolicyStep();
      case setupWizardLocationStep:
        return _buildLocationStep();
      case setupWizardReviewStep:
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
                    style: SetupUi.secondaryButtonOf(context),
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
                    style: SetupUi.secondaryButtonOf(context),
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
            SetupCompactSwitch(
              title: 'Breaktime is paid',
              subtitle:
                  'ON: Include breaktime in paid working hours. OFF: Breaktime is unpaid.',
              value: _breaktimeIsPaid,
              onChanged: _busy
                  ? null
                  : (value) async {
                      setState(() => _breaktimeIsPaid = value);
                      try {
                        await _repo.updateAttendancePolicy({
                          'breaktime_is_paid': value,
                        });
                      } catch (_) {
                        if (!mounted) return;
                        setState(() => _breaktimeIsPaid = !value);
                        _showSnack('Could not save breaktime setting');
                      }
                    },
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
            (shift) => SetupSurfaceCard(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: SetupUi.wellOf(context),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(
                          Icons.schedule_rounded,
                          size: 18,
                          color: SetupUi.navyOf(context),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${shift['name']}',
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                color: AppColors.textPrimary,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '${_shiftTimeRangeLabel(shift)} · Capacity ${shift['employee_capacity'] ?? '—'}',
                              style: const TextStyle(
                                fontSize: 13,
                                height: 1.35,
                                color: AppColors.textMuted,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    children: [
                      TextButton(
                        style: SetupUi.ghostButtonOf(context),
                        onPressed:
                            _busy ? null : () => _editShiftTimes(shift),
                        child: const Text('Edit shift'),
                      ),
                      TextButton(
                        style: SetupUi.ghostButtonOf(context).copyWith(
                          foregroundColor: const WidgetStatePropertyAll(
                            AppColors.danger,
                          ),
                        ),
                        onPressed: _busy
                            ? null
                            : () => _removeShift('${shift['id']}'),
                        child: const Text('Remove'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildPositionsStep() {
    final unclassified = _positions
        .where((p) => p['employment_type'] == null)
        .toList(growable: false);
    final fullTime = _positions
        .where((p) => p['employment_type'] == 'full_time')
        .toList(growable: false);
    final partTime = _positions
        .where((p) => p['employment_type'] == 'part_time')
        .toList(growable: false);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SetupPanel(
          title: 'Add a job role',
          icon: Icons.badge_outlined,
          subtitle:
              'Employment type → role → Daily and/or Hourly amounts. Configure once, reuse when adding employees.',
          children: [
            DropdownButtonFormField<String>(
              initialValue: _positionEmploymentType,
              isDense: true,
              decoration: _compactInput('1. Employment type'),
              items: const [
                DropdownMenuItem(value: 'full_time', child: Text('Full-time')),
                DropdownMenuItem(value: 'part_time', child: Text('Part-time')),
              ],
              onChanged: (value) => setState(
                () => _positionEmploymentType = value ?? 'full_time',
              ),
            ),
            const SizedBox(height: _fieldGap),
            TextField(
              controller: _positionTitle,
              style: const TextStyle(fontSize: 14),
              decoration: _compactInput('2. Role / position name'),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: _fieldGap),
            const Text(
              '3. Pay configurations',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: Color(0xFF6B7280),
              ),
            ),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              title: const Text('Daily'),
              value: _positionEnableDaily,
              onChanged: (v) =>
                  setState(() => _positionEnableDaily = v ?? false),
            ),
            if (_positionEnableDaily)
              TextField(
                controller: _positionDailyRate,
                style: const TextStyle(fontSize: 14),
                decoration: _compactInput('Daily amount (₱)'),
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                onChanged: (_) => setState(() {}),
              ),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              title: const Text('Hourly'),
              value: _positionEnableHourly,
              onChanged: (v) =>
                  setState(() => _positionEnableHourly = v ?? false),
            ),
            if (_positionEnableHourly)
              TextField(
                controller: _positionHourlyRate,
                style: const TextStyle(fontSize: 14),
                decoration: _compactInput('Hourly amount (₱)'),
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                onChanged: (_) => setState(() {}),
              ),
            const SizedBox(height: _fieldGap),
            TextField(
              controller: _positionDescription,
              style: const TextStyle(fontSize: 14),
              decoration: _compactInput('Description (optional)'),
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
        if (unclassified.isNotEmpty) ...[
          const SizedBox(height: 14),
          SetupPanel(
            title: 'Unclassified existing roles',
            icon: Icons.warning_amber_rounded,
            subtitle:
                'Still usable for current employees. Assign Full-time or Part-time before using them in Add Employee.',
            children: [
              for (final position in unclassified)
                SetupListTileCard(
                  leadingIcon: Icons.badge_outlined,
                  title: '${position['title']}',
                  subtitle: _positionRateSubtitle(position),
                  actions: [
                    TextButton(
                      onPressed: _busy
                          ? null
                          : () => _classifyPosition(
                                '${position['id']}',
                                'full_time',
                              ),
                      child: const Text('Full-time'),
                    ),
                    TextButton(
                      onPressed: _busy
                          ? null
                          : () => _classifyPosition(
                                '${position['id']}',
                                'part_time',
                              ),
                      child: const Text('Part-time'),
                    ),
                  ],
                ),
            ],
          ),
        ],
        if (fullTime.isNotEmpty || partTime.isNotEmpty) ...[
          const SizedBox(height: 14),
          if (fullTime.isNotEmpty) ...[
            const SetupListLabel('Full-time roles'),
            ...fullTime.map(
              (position) => SetupListTileCard(
                leadingIcon: Icons.badge_outlined,
                title: '${position['title']}',
                subtitle: _positionRateSubtitle(position),
                actions: [
                  TextButton(
                    onPressed: _busy
                        ? null
                        : () => _editPositionPayConfigs(position),
                    child: const Text('Edit rates'),
                  ),
                  TextButton(
                    style: SetupUi.ghostButtonOf(context).copyWith(
                      foregroundColor:
                          const WidgetStatePropertyAll(AppColors.danger),
                    ),
                    onPressed: _busy
                        ? null
                        : () => _removePosition('${position['id']}'),
                    child: const Text('Remove'),
                  ),
                ],
              ),
            ),
          ],
          if (partTime.isNotEmpty) ...[
            const SetupListLabel('Part-time roles'),
            ...partTime.map(
              (position) => SetupListTileCard(
                leadingIcon: Icons.badge_outlined,
                title: '${position['title']}',
                subtitle: _positionRateSubtitle(position),
                actions: [
                  TextButton(
                    onPressed: _busy
                        ? null
                        : () => _editPositionPayConfigs(position),
                    child: const Text('Edit rates'),
                  ),
                  TextButton(
                    style: SetupUi.ghostButtonOf(context).copyWith(
                      foregroundColor:
                          const WidgetStatePropertyAll(AppColors.danger),
                    ),
                    onPressed: _busy
                        ? null
                        : () => _removePosition('${position['id']}'),
                    child: const Text('Remove'),
                  ),
                ],
              ),
            ),
          ],
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
                style: SetupUi.secondaryButtonOf(context),
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
          title: 'Holiday Rules',
          icon: Icons.celebration_outlined,
          subtitle:
              'How Aroll+ interprets holiday types for worked and unworked days.',
          children: [
            DropdownButtonFormField<String>(
              initialValue: _holidayRulesMode,
              isDense: true,
              decoration: _compactInput('Holiday Rules'),
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
            OvertimeCalculationMethodField(
              value: _payrollOvertimeMethod,
              enabled: _payrollOvertimeEnabled,
              decoration: _compactInput('How overtime is calculated'),
              onChanged: (value) =>
                  setState(() => _payrollOvertimeMethod = value),
            ),
            Text(
              _payrollOvertimeMethod == 'hourly_statutory'
                  ? 'Uses the basic hourly rate, or the daily rate divided by that shift\'s scheduled hours, then the day factor. This is not proof of Labor Code coverage.'
                  : 'Uses the saved peso amount per overtime minute. A flat amount can be below what a covered employee is entitled to, and saving it does not make the rate compliant.',
              softWrap: true,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: const Color(0xFF6B7280),
                  ),
            ),
            if (_payrollOvertimeMethod == 'flat_per_minute')
              TextField(
                controller: _payrollOvertimeRate,
                enabled: _payrollOvertimeEnabled,
                style: const TextStyle(fontSize: 14),
                decoration: _compactInput('Extra Pay per Overtime Minute (₱)'),
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
              'Employees who arrive late may offset the late time by working '
              'beyond their scheduled end time.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: const Color(0xFF6B7280),
                  ),
            ),
            const SizedBox(height: 4),
            _compactSwitch(
              title: 'OT Approval Required',
              value: _payrollOtApprovalRequired && _payrollOvertimeEnabled,
              onChanged: (value) {
                if (!_payrollOvertimeEnabled) return;
                setState(() => _payrollOtApprovalRequired = value);
              },
            ),
            Text(
              'When enabled, overtime must be approved before it is included '
              'as payable additional pay.',
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
          title: 'Time-in rules',
          icon: Icons.fact_check_outlined,
          subtitle:
              'Configure early, late, absent, half-day, overtime, and incomplete cutoffs.',
          children: [
            SetupLabeledSetting(
              title: 'Early time-in window (min)',
              description:
                  'How early employees may time in before shift start.',
              controller: _attEarlyClockIn,
              inputHint: 'Minutes',
            ),
            SetupLabeledSetting(
              title: 'Extra minutes before late',
              description:
                  'Grace after shift start before status becomes Late.',
              controller: _attOnTimeGrace,
              inputHint: 'Minutes',
            ),
            SetupLabeledSetting(
              title: 'Minimum Worked Shift (%)',
              description:
                  'Employees must work at least the configured percentage of their scheduled shift to avoid being marked Absent.',
              controller: _attAbsentPercent,
              inputHint: 'Percent',
            ),
            SetupLabeledSetting(
              title: 'Half-day if under (% of shift)',
              description:
                  'Status cutoff as percent of scheduled shift length.',
              controller: _attHalfDayPercent,
              inputHint: 'Percent',
            ),
            SetupLabeledSetting(
              title: 'Payroll half-day cutoff (min)',
              description:
                  'Used for payslip half-day math (minutes).',
              controller: _attHalfDay,
              inputHint: 'Minutes',
            ),
            SetupLabeledSetting(
              title: 'Payroll absent cutoff (min)',
              description:
                  'Fallback minute cutoff when shift length is unavailable.',
              controller: _attAbsent,
              inputHint: 'Minutes',
            ),
            SetupLabeledSetting(
              title: 'Minimum overtime minutes',
              description:
                  'OT pay starts only after this many minutes past shift end.',
              controller: _attOvertimeMinimum,
              inputHint: 'Minutes',
            ),
            SetupLabeledSetting(
              title: 'Maximum overtime duration (min)',
              description:
                  'How long an employee may stay timed in after shift end '
                  'before attendance becomes Incomplete.',
              controller: _attMaximumOvertime,
              inputHint: 'Minutes',
            ),
          ],
        ),
        const SizedBox(height: _fieldGap),
        _infoBox(
          'Minimum Worked Shift (%) and half-day cutoffs use percent of each '
          'scheduled shift. '
          'Maximum overtime duration is an attendance cutoff only. '
          'Overtime pay follows the method in pay settings '
          '(${_payrollOvertimeEnabled ? 'turned on' : 'turned off'}'
          '${_payrollOvertimeMethod == 'hourly_statutory' ? ', hourly-based' : ', ₱${_payrollOvertimeRate.text} per minute'}).',
        ),
        const SizedBox(height: 10),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: _busy ? null : _saveAttendance,
            style: _primaryButtonStyle,
            child: const Text('Save Time-In Settings'),
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

  Widget _buildLeavePolicyStep() {
    final items = _leaveItems
        .where((item) => item['leave_type'] != 'unpaid')
        .toList(growable: false);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SetupInfoBanner(
          'Set which leave types are paid or unpaid. You can skip this and '
          'change it later in settings. Skipping does not overwrite a saved policy.',
        ),
        const SizedBox(height: 12),
        if (items.isEmpty)
          const SetupInfoBanner(
            'Leave policy will load after the business is ready. You can skip for now.',
            tone: SetupBannerTone.warning,
          )
        else
          SetupPanel(
            title: 'Leave types',
            icon: Icons.event_busy_outlined,
            subtitle: 'Employees pick the leave type. Payroll uses this policy.',
            children: [
              for (final item in items)
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  title: Text('${item['leave_type_label']}'),
                  subtitle: Text(
                    _leaveDraft['${item['leave_type']}'] == true
                        ? 'Counts as paid leave'
                        : 'Counts as unpaid leave',
                  ),
                  value: _leaveDraft['${item['leave_type']}'] == true,
                  onChanged: (value) => setState(() {
                    _leaveDraft['${item['leave_type']}'] = value;
                  }),
                ),
              const SizedBox(height: 8),
              TextField(
                controller: _leaveNotice,
                keyboardType: TextInputType.number,
                style: const TextStyle(fontSize: 14),
                decoration: _compactInput(
                  'Minimum advance notice (days)',
                  hint: '0 means no minimum',
                ),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _busy || !_leavePolicyDirty
                      ? null
                      : () {
                          _saveLeavePolicy();
                        },
                  style: _primaryButtonStyle,
                  child: const Text('Save Leave Policy'),
                ),
              ),
            ],
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
          'be before they can time in or time out.',
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
                style: SetupUi.secondaryButtonOf(context),
                onPressed: _locationLocating || _busy
                    ? null
                    : _useWizardCurrentLocation,
                icon: _locationLocating
                    ? SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: SetupUi.navyOf(context),
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
                activeTrackColor: SetupUi.navyOf(context),
                inactiveTrackColor: const Color(0xFFE8EEF4),
                thumbColor: SetupUi.navyOf(context),
                overlayColor: SetupUi.navyOf(context).withValues(alpha: 0.12),
                valueIndicatorColor: SetupUi.navyOf(context),
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
            style: SetupUi.secondaryButtonOf(context),
            onPressed: () => context.go('/owner/home'),
            child: const Text('Go to Dashboard'),
          ),
        ),
      ],
    );
  }

  Widget _buildFooter() {
    return Container(
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
            style: SetupUi.ghostButtonOf(context),
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
              style: SetupUi.primaryButtonOf(context).copyWith(
                minimumSize: const WidgetStatePropertyAll(Size(0, 40)),
              ),
              child: const Text('Continue'),
            ),
          ],
        ],
      ),
    );
  }

  Widget _infoBox(String text) => SetupInfoBanner(text);
}

class _EditShiftTimesDialogResult {
  const _EditShiftTimesDialogResult({
    required this.start,
    required this.end,
    required this.capacity,
  });

  final TimeOfDay start;
  final TimeOfDay end;
  final int capacity;
}

/// Owns the Employee Capacity [TextEditingController] for the setup-wizard
/// edit-shift dialog so dispose runs only after this [State] leaves the tree.
class _EditShiftTimesDialog extends StatefulWidget {
  const _EditShiftTimesDialog({
    required this.shiftName,
    required this.initialStart,
    required this.initialEnd,
    required this.initialCapacityText,
    required this.capacityDecoration,
    this.timesLocked = false,
  });

  final String shiftName;
  final TimeOfDay initialStart;
  final TimeOfDay initialEnd;
  final String initialCapacityText;
  final InputDecoration capacityDecoration;
  final bool timesLocked;

  @override
  State<_EditShiftTimesDialog> createState() => _EditShiftTimesDialogState();
}

class _EditShiftTimesDialogState extends State<_EditShiftTimesDialog> {
  late TimeOfDay _start;
  late TimeOfDay _end;
  late final TextEditingController _capacityController;

  @override
  void initState() {
    super.initState();
    _start = widget.initialStart;
    _end = widget.initialEnd;
    _capacityController = TextEditingController(text: widget.initialCapacityText);
  }

  @override
  void dispose() {
    _capacityController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(
        widget.timesLocked ? 'Shift In Progress' : 'Edit ${widget.shiftName}',
        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (widget.timesLocked) ...[
            const Text(
              'This shift has already started and cannot be changed. '
              'Changes to an active shift could affect attendance and '
              'payroll records.',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: Color(0xFF6B7280),
                height: 1.45,
              ),
            ),
            const SizedBox(height: 14),
          ],
          OutlinedButton(
            style: SetupUi.secondaryButtonOf(context),
            onPressed: widget.timesLocked
                ? null
                : () async {
                    final picked = await showTimePicker(
                      context: context,
                      initialTime: _start,
                    );
                    if (picked != null) {
                      setState(() => _start = picked);
                    }
                  },
            child: Text('Start ${_start.format(context)}'),
          ),
          const SizedBox(height: 10),
          OutlinedButton(
            style: SetupUi.secondaryButtonOf(context),
            onPressed: widget.timesLocked
                ? null
                : () async {
                    final picked = await showTimePicker(
                      context: context,
                      initialTime: _end,
                    );
                    if (picked != null) {
                      setState(() => _end = picked);
                    }
                  },
            child: Text('End ${_end.format(context)}'),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _capacityController,
            style: const TextStyle(fontSize: 14),
            decoration: widget.capacityDecoration,
            keyboardType: TextInputType.number,
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          style: SetupUi.primaryButtonOf(context),
          onPressed: () {
            final capacity = int.tryParse(_capacityController.text.trim());
            if (capacity == null || capacity < 1) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text(
                    'Employee capacity must be a whole number of at least 1',
                  ),
                ),
              );
              return;
            }
            Navigator.pop(
              context,
              _EditShiftTimesDialogResult(
                start: _start,
                end: _end,
                capacity: capacity,
              ),
            );
          },
          child: const Text('Save'),
        ),
      ],
    );
  }
}

String _positionRateSubtitle(Map<String, dynamic> position) {
  final configs = (position['pay_configs'] as List?) ?? const [];
  if (configs.isNotEmpty) {
    final parts = <String>[];
    for (final raw in configs) {
      if (raw is! Map) continue;
      final basis = '${raw['pay_basis']}';
      final rate = raw['rate'];
      if (basis == 'hourly') {
        parts.add('Hourly · ₱$rate/hr');
      } else if (basis == 'daily') {
        parts.add('Daily · ₱$rate/day');
      }
    }
    if (parts.isNotEmpty) return parts.join(' · ');
  }
  final basis = '${position['pay_basis'] ?? 'daily'}';
  final daily = position['daily_rate'];
  final hourly = position['hourly_rate'];
  if (basis == 'hourly' && hourly != null) {
    return 'Hourly · ₱$hourly/hr';
  }
  if (daily != null) {
    return 'Daily · ₱$daily/day';
  }
  if (hourly != null) {
    return 'Hourly · ₱$hourly/hr';
  }
  return 'Rate not set';
}
