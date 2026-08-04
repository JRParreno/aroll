import 'package:aroll_mobile/core/di/injection.dart';
import 'package:aroll_mobile/data/repositories/owner_repository.dart';
import 'package:aroll_mobile/presentation/employee/employee_ui.dart';
import 'package:aroll_mobile/presentation/owner/owner_shell.dart';
import 'package:aroll_mobile/presentation/owner/owner_schedule_utils.dart';
import 'package:aroll_mobile/presentation/shared/app_ui.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

class OwnerEmployeesScreen extends StatefulWidget {
  const OwnerEmployeesScreen({super.key});

  @override
  State<OwnerEmployeesScreen> createState() => _OwnerEmployeesScreenState();
}

class _OwnerEmployeesScreenState extends State<OwnerEmployeesScreen> {
  final _repo = sl<OwnerRepository>();
  final _searchController = TextEditingController();

  bool _loading = true;
  String? _error;
  String _query = '';
  String _employmentFilter = 'all';
  String _statusFilter = 'all';
  String _positionFilter = 'all';

  List<Map<String, dynamic>> _employees = const [];
  List<Map<String, dynamic>> _positions = const [];
  Map<String, Set<String>> _assignedWorkdays = const {};

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() {
      setState(() => _query = _searchController.text);
    });
    _loadData();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final weekStart = ownerWeekStart(DateTime.now());
      final results = await Future.wait([
        _repo.employees(includeInactive: true),
        _repo.positions(),
        _repo.weeklySchedule(weekStart),
      ]);
      if (!mounted) return;
      final assignments = ((results[2] as Map<String, dynamic>)['assignments']
                  as List<dynamic>? ??
              const [])
          .whereType<Map<String, dynamic>>();
      final workdays = <String, Set<String>>{};
      for (final assignment in assignments) {
        final employeeId = '${assignment['employee_id']}';
        workdays.putIfAbsent(employeeId, () => {}).add(
              _shortWeekday('${assignment['work_date']}'),
            );
      }
      setState(() {
        _employees = results[0] as List<Map<String, dynamic>>;
        _positions = results[1] as List<Map<String, dynamic>>;
        _assignedWorkdays = workdays;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Unable to load employees. Please try again.';
      });
    }
  }

  List<Map<String, dynamic>> get _filteredEmployees {
    final search = _query.trim().toLowerCase();
    return _employees.where((employee) {
      if (_employmentFilter != 'all' &&
          employee['employment_type'] != _employmentFilter) {
        return false;
      }
      if (_statusFilter != 'all' && employee['status'] != _statusFilter) {
        return false;
      }
      if (_positionFilter != 'all' &&
          (employee['position_title'] ?? '') != _positionFilter) {
        return false;
      }
      if (search.isEmpty) return true;
      final haystack = [
        employee['full_name'],
        employee['phone'] ?? '',
        employee['position_title'] ?? '',
        employee['employment_type'],
        employee['username'],
        employee['id'],
      ].join(' ').toLowerCase();
      return haystack.contains(search);
    }).toList(growable: false);
  }

  void _openAddEmployee() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (context) => _EmployeeFormSheet(
        positions: _positions,
        onSubmit: (form) async {
          final employee = await _repo.createEmployee(
            fullName: form.fullName,
            positionTitle: form.positionTitle,
            positionId: form.positionId,
            employmentType: form.employmentType,
            phone: form.phone,
            payBasis: form.payBasis,
            dailyRate: form.dailyRate,
            hourlyRate: form.hourlyRate,
            monthlySalary: form.monthlySalary,
          );
          if (!context.mounted) return;
          Navigator.pop(context);
          await _loadData();
          if (!mounted) return;
          _showCredentialsDialog(employee);
          _showMessage('Employee added');
        },
      ),
    );
  }

  void _openEditEmployee(Map<String, dynamic> employee) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (context) => _EmployeeFormSheet(
        positions: _positions,
        editing: true,
        employee: employee,
        initial: _EmployeeForm.fromEmployee(employee),
        onSubmit: (form) async {
          await _repo.updateEmployee(
            employeeId: '${employee['id']}',
            fullName: form.fullName,
            positionTitle: form.positionTitle,
            positionId: form.positionId,
            employmentType: form.employmentType,
            phone: form.phone.isEmpty ? null : form.phone,
            payBasis: form.payBasis,
            dailyRate: form.dailyRate,
            hourlyRate: form.hourlyRate,
            monthlySalary: form.monthlySalary,
          );
          if (!context.mounted) return;
          Navigator.pop(context);
          await _loadData();
          if (!mounted) return;
          _showMessage('Employee updated');
        },
      ),
    );
  }

  Future<void> _restoreEmployee(Map<String, dynamic> employee) async {
    final navigator = Navigator.of(context);
    try {
      await _repo.reactivateEmployee('${employee['id']}');
      if (!mounted) return;
      navigator.pop();
      await _loadData();
      _showMessage('Employee restored');
    } on DioException catch (_) {
      if (!mounted) return;
      _showMessage('Failed to restore employee');
    }
  }

  void _openDetails(Map<String, dynamic> employee) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (context) => _EmployeeDetailsSheet(
        employee: employee,
        workdays: _assignedWorkdays['${employee['id']}']?.join(', ') ??
            'No assigned workdays this week',
        onEdit: () {
          Navigator.pop(context);
          _openEditEmployee(employee);
        },
        onDelete: () async {
          Navigator.pop(context);
          await _confirmDelete(employee);
        },
        onRestore: () => _restoreEmployee(employee),
      ),
    );
  }

  Future<void> _confirmDelete(Map<String, dynamic> employee) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Employee'),
        content: const Text(
          'Are you sure you want to delete this employee? '
          'This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await _repo.deleteEmployee('${employee['id']}');
      await _loadData();
      _showMessage('Employee deleted successfully.');
    } on DioException catch (error) {
      _showMessage(_dioMessage(error) ?? 'Failed to delete employee.');
    }
  }

  void _showCredentialsDialog(Map<String, dynamic> employee) {
    showDialog<void>(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.white,
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Employee Login Credentials',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF111827),
                ),
              ),
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFF1F456B), Color(0xFF2A5A84)],
                  ),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.15),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: const Color(0xFFB9D8EE).withValues(alpha: 0.5),
                        ),
                      ),
                      child: const Icon(
                        Icons.key_rounded,
                        color: Colors.white,
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${employee['full_name'] ?? 'Employee'}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                              fontSize: 15,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Ready to share login details',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.8),
                              fontSize: 12.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFFFAFBFC),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: const Color(0xFFE5E7EB)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      'Share these credentials with the employee so they can '
                      'activate their account.',
                      style: TextStyle(
                        fontSize: 13,
                        height: 1.35,
                        color: Color(0xFF6B7280),
                      ),
                    ),
                    const SizedBox(height: 12),
                    _CredentialTile(
                      label: 'Username',
                      value:
                          '${employee['generated_username'] ?? employee['username']}',
                    ),
                    const SizedBox(height: 8),
                    _CredentialTile(
                      label: 'Temporary Password',
                      value: '${employee['temporary_password'] ?? 'Hidden'}',
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF1F456B),
                  foregroundColor: Colors.white,
                  minimumSize: const Size.fromHeight(48),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                onPressed: () => Navigator.pop(context),
                child: const Text(
                  'Done',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _openFilters() {
    showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      builder: (context) => _EmployeeFilterSheet(
        employmentFilter: _employmentFilter,
        statusFilter: _statusFilter,
        positionFilter: _positionFilter,
        positions: _positions,
        onApply: (employment, status, position) {
          setState(() {
            _employmentFilter = employment;
            _statusFilter = status;
            _positionFilter = position;
          });
          Navigator.pop(context);
        },
      ),
    );
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  String? _dioMessage(DioException error) {
    final data = error.response?.data;
    if (data is Map && data['detail'] is String) {
      return data['detail'] as String;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return OwnerShell(
      selectedIndex: 0,
      showBackButton: true,
      title: 'Employees',
      actions: [
        IconButton(
          tooltip: 'Add Employee',
          onPressed: _openAddEmployee,
          icon: const Icon(Icons.person_add_outlined),
        ),
      ],
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Row(
              children: [
                Expanded(
                  child: Container(
                    height: 48,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: const Color(0xFFE5E7EB)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.search, color: Color(0xFF777777)),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextField(
                            controller: _searchController,
                            decoration: const InputDecoration(
                              hintText: 'Search employees...',
                              border: InputBorder.none,
                              isDense: true,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Material(
                  color: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: const BorderSide(color: Color(0xFFE5E7EB)),
                  ),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: _openFilters,
                    child: const SizedBox(
                      width: 48,
                      height: 48,
                      child: Icon(Icons.filter_list_rounded),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: _loading
                ? appLoadingView(cardCount: 4)
                : _error != null
                    ? OwnerErrorState(onRetry: _loadData)
                    : RefreshIndicator(
                        onRefresh: _loadData,
                        child: _filteredEmployees.isEmpty
                            ? ListView(
                                children: const [
                                  SizedBox(height: 48),
                                  OwnerEmptyState(
                                    'No employees yet',
                                    description:
                                        'Add your first team member to start scheduling and tracking attendance.',
                                    icon: Icons.groups_outlined,
                                  ),
                                ],
                              )
                            : ListView.separated(
                                padding:
                                    const EdgeInsets.fromLTRB(16, 0, 16, 16),
                                itemCount: _filteredEmployees.length,
                                separatorBuilder: (_, __) =>
                                    const SizedBox(height: 12),
                                itemBuilder: (context, index) {
                                  final employee = _filteredEmployees[index];
                                  return _EmployeeCard(
                                    employee: employee,
                                    workdays:
                                        _assignedWorkdays['${employee['id']}']
                                                ?.join(', ') ??
                                            'No assigned workdays this week',
                                    onTap: () => _openDetails(employee),
                                  );
                                },
                              ),
                      ),
          ),
        ],
      ),
    );
  }
}

class _EmployeeCard extends StatelessWidget {
  const _EmployeeCard({
    required this.employee,
    required this.workdays,
    required this.onTap,
  });

  final Map<String, dynamic> employee;
  final String workdays;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final fullTime = employee['employment_type'] == 'full_time';
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFE5E7EB)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    EmployeeAvatar(
                      imageUrl: employee['profile_image_url'] as String?,
                      name: '${employee['full_name'] ?? 'Employee'}',
                      size: 56,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${employee['full_name'] ?? 'Employee'}',
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 15,
                            ),
                          ),
                          const SizedBox(height: 8),
                          _InfoRow(
                            icon: Icons.phone_outlined,
                            text: (employee['phone'] as String?)?.isNotEmpty ==
                                    true
                                ? '${employee['phone']}'
                                : 'No contact number',
                          ),
                          const SizedBox(height: 4),
                          _InfoRow(
                            icon: Icons.calendar_today_outlined,
                            text: workdays,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: const BoxDecoration(
                  border: Border(top: BorderSide(color: Color(0xFFE5E7EB))),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${employee['position_title'] ?? 'No role'}',
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF5E5E5E),
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: fullTime
                            ? const Color(0xFFB7FA84)
                            : const Color(0xFFFFE27C),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        fullTime ? 'Full timer' : 'Part timer',
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 14, color: const Color(0xFF4F4F4F)),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: Color(0xFF4F4F4F),
            ),
          ),
        ),
      ],
    );
  }
}

class _EmployeeForm {
  const _EmployeeForm({
    required this.fullName,
    required this.positionTitle,
    required this.positionId,
    required this.employmentType,
    required this.phone,
    required this.payBasis,
    this.dailyRate,
    this.hourlyRate,
    this.monthlySalary,
  });

  final String fullName;
  final String positionTitle;
  final String positionId;
  final String employmentType;
  final String phone;
  final String payBasis;
  final double? dailyRate;
  final double? hourlyRate;
  final double? monthlySalary;

  factory _EmployeeForm.fromEmployee(Map<String, dynamic> employee) {
    double? asDouble(dynamic value) {
      if (value == null) return null;
      if (value is num) return value.toDouble();
      return double.tryParse('$value');
    }

    return _EmployeeForm(
      fullName: '${employee['full_name'] ?? ''}',
      positionTitle: '${employee['position_title'] ?? ''}',
      positionId: '${employee['position_id'] ?? ''}',
      employmentType: '${employee['employment_type'] ?? 'full_time'}',
      phone: '${employee['phone'] ?? ''}',
      payBasis: '${employee['pay_basis'] ?? 'daily'}',
      dailyRate: asDouble(employee['daily_rate']),
      hourlyRate: asDouble(employee['hourly_rate']),
      monthlySalary: asDouble(employee['monthly_salary']),
    );
  }
}

class _EmployeeFormSheet extends StatefulWidget {
  const _EmployeeFormSheet({
    required this.positions,
    required this.onSubmit,
    this.editing = false,
    this.initial,
    this.employee,
  });

  final List<Map<String, dynamic>> positions;
  final Future<void> Function(_EmployeeForm form) onSubmit;
  final bool editing;
  final _EmployeeForm? initial;
  final Map<String, dynamic>? employee;

  @override
  State<_EmployeeFormSheet> createState() => _EmployeeFormSheetState();
}

class _EmployeeFormSheetState extends State<_EmployeeFormSheet> {
  static const _navy = Color(0xFF1F456B);
  static const _softBlue = Color(0xFFB9D8EE);

  late final TextEditingController _fullName;
  late final TextEditingController _phone;
  late final TextEditingController _positionTitle;
  late final TextEditingController _dailyRate;
  late final TextEditingController _hourlyRate;
  late final TextEditingController _monthlySalary;
  late String _positionId;
  late String _employmentType;
  late String _payBasis;
  bool _submitting = false;

  InputDecoration _fieldDecoration(String label) {
    return InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w600,
        color: Color(0xFF6B7280),
      ),
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: _navy, width: 1.4),
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    final initial = widget.initial ??
        const _EmployeeForm(
          fullName: '',
          positionTitle: '',
          positionId: '',
          employmentType: 'full_time',
          phone: '',
          payBasis: 'daily',
        );
    _fullName = TextEditingController(text: initial.fullName);
    _phone = TextEditingController(text: initial.phone);
    _positionTitle = TextEditingController(text: initial.positionTitle);
    _dailyRate = TextEditingController(
      text: initial.dailyRate?.toString() ?? '',
    );
    _hourlyRate = TextEditingController(
      text: initial.hourlyRate?.toString() ?? '',
    );
    _monthlySalary = TextEditingController(
      text: initial.monthlySalary?.toString() ?? '',
    );
    _positionId = initial.positionId;
    _employmentType = initial.employmentType;
    _payBasis = initial.payBasis;
    if (widget.editing &&
        widget.positions.isNotEmpty &&
        _positionId.isEmpty &&
        initial.positionTitle.isNotEmpty) {
      for (final position in widget.positions) {
        if ('${position['title']}' == initial.positionTitle) {
          _positionId = '${position['id']}';
          break;
        }
      }
    }
    if (!widget.editing &&
        _payBasis == 'daily' &&
        _dailyRate.text.isEmpty &&
        _positionId.isNotEmpty) {
      for (final position in widget.positions) {
        if ('${position['id']}' == _positionId) {
          _dailyRate.text = '${position['daily_rate'] ?? ''}';
          break;
        }
      }
    }
    _fullName.addListener(() => setState(() {}));
    _positionTitle.addListener(() => setState(() {}));
    _dailyRate.addListener(() => setState(() {}));
    _hourlyRate.addListener(() => setState(() {}));
    _monthlySalary.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _fullName.dispose();
    _phone.dispose();
    _positionTitle.dispose();
    _dailyRate.dispose();
    _hourlyRate.dispose();
    _monthlySalary.dispose();
    super.dispose();
  }

  bool get _payReady {
    if (_payBasis == 'daily') {
      return (double.tryParse(_dailyRate.text.trim()) ?? 0) > 0;
    }
    if (_payBasis == 'hourly') {
      return (double.tryParse(_hourlyRate.text.trim()) ?? 0) > 0;
    }
    return (double.tryParse(_monthlySalary.text.trim()) ?? 0) > 0;
  }

  bool get _ready =>
      _fullName.text.trim().isNotEmpty &&
      (widget.positions.isNotEmpty
          ? _positionId.isNotEmpty || _positionTitle.text.trim().isNotEmpty
          : _positionTitle.text.trim().isNotEmpty) &&
      _payReady;

  Future<void> _submit() async {
    if (!_ready || _submitting) return;
    setState(() => _submitting = true);
    try {
      final selectedPosition =
          widget.positions.cast<Map<String, dynamic>?>().firstWhere(
                (position) => position?['id'] == _positionId,
                orElse: () => null,
              );
      await widget.onSubmit(
        _EmployeeForm(
          fullName: _fullName.text.trim(),
          positionTitle: selectedPosition?['title'] as String? ??
              _positionTitle.text.trim(),
          positionId: _positionId,
          employmentType: _employmentType,
          phone: _phone.text.trim(),
          payBasis: _payBasis,
          dailyRate: _payBasis == 'daily'
              ? double.tryParse(_dailyRate.text.trim())
              : null,
          hourlyRate: _payBasis == 'hourly'
              ? double.tryParse(_hourlyRate.text.trim())
              : null,
          monthlySalary: _payBasis == 'monthly'
              ? double.tryParse(_monthlySalary.text.trim())
              : null,
        ),
      );
    } on DioException catch (error) {
      if (!mounted) return;
      final detail = error.response?.data is Map
          ? (error.response?.data as Map)['detail'] as String?
          : null;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(detail ?? 'Failed to save employee')),
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Widget _buildFields() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!widget.editing) ...[
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFF3F8FD),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFFD7E6F5)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(10),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.04),
                        blurRadius: 6,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.key_rounded,
                    size: 16,
                    color: _navy,
                  ),
                ),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text(
                    'Username and temporary password are generated automatically '
                    'after enrollment. You’ll get them to share once the employee '
                    'is added.',
                    style: TextStyle(
                      color: Color(0xFF334155),
                      fontSize: 13,
                      height: 1.35,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
        ],
        if (widget.editing) ...[
          const Text(
            'Update the employee’s profile details below. Login credentials '
            'stay the same.',
            style: TextStyle(fontSize: 13, color: Color(0xFF6B7280), height: 1.35),
          ),
          const SizedBox(height: 14),
        ],
        TextField(
          controller: _fullName,
          textCapitalization: TextCapitalization.words,
          decoration: _fieldDecoration('Full Name'),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _phone,
          keyboardType: TextInputType.phone,
          decoration: _fieldDecoration('Contact Number'),
        ),
        const SizedBox(height: 12),
        if (widget.positions.isNotEmpty)
          DropdownButtonFormField<String>(
            initialValue: _positionId.isEmpty ? null : _positionId,
            decoration: _fieldDecoration('Position/Role'),
            items: [
              for (final position in widget.positions)
                DropdownMenuItem(
                  value: '${position['id']}',
                  child: Text('${position['title']}'),
                ),
            ],
            onChanged: (value) {
              setState(() {
                _positionId = value ?? '';
                final selected = widget.positions.firstWhere(
                  (position) => '${position['id']}' == value,
                  orElse: () => const {},
                );
                if (selected.isNotEmpty) {
                  _positionTitle.text = '${selected['title']}';
                  final positionRate = '${selected['daily_rate'] ?? ''}';
                  if (_payBasis == 'daily') {
                    final previous = widget.positions.cast<Map<String, dynamic>?>().firstWhere(
                          (p) =>
                              p != null &&
                              '${p['id']}' != value &&
                              _dailyRate.text.trim() ==
                                  '${p['daily_rate'] ?? ''}',
                          orElse: () => null,
                        );
                    // Prefill on create, or when rate still matches prior
                    // position default — never overwrite a custom rate.
                    if (!widget.editing ||
                        _dailyRate.text.trim().isEmpty ||
                        previous != null) {
                      _dailyRate.text = positionRate;
                    }
                  }
                }
              });
            },
          )
        else
          TextField(
            controller: _positionTitle,
            decoration: _fieldDecoration('Position/Role'),
          ),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          initialValue: _employmentType,
          decoration: _fieldDecoration('Employment Type'),
          items: const [
            DropdownMenuItem(value: 'full_time', child: Text('Full-Time')),
            DropdownMenuItem(value: 'part_time', child: Text('Part-Time')),
          ],
          onChanged: (value) =>
              setState(() => _employmentType = value ?? 'full_time'),
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          initialValue: _payBasis,
          decoration: _fieldDecoration('Pay Basis'),
          items: const [
            DropdownMenuItem(value: 'daily', child: Text('Daily')),
            DropdownMenuItem(value: 'hourly', child: Text('Hourly')),
            DropdownMenuItem(value: 'monthly', child: Text('Monthly')),
          ],
          onChanged: (value) {
            setState(() {
              _payBasis = value ?? 'daily';
              if (_payBasis == 'daily' &&
                  _dailyRate.text.trim().isEmpty &&
                  _positionId.isNotEmpty) {
                for (final position in widget.positions) {
                  if ('${position['id']}' == _positionId) {
                    _dailyRate.text = '${position['daily_rate'] ?? ''}';
                    break;
                  }
                }
              }
            });
          },
        ),
        const SizedBox(height: 12),
        if (_payBasis == 'daily')
          TextField(
            controller: _dailyRate,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: _fieldDecoration('Daily Rate (₱)'),
          ),
        if (_payBasis == 'hourly')
          TextField(
            controller: _hourlyRate,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: _fieldDecoration('Hourly Rate (₱)'),
          ),
        if (_payBasis == 'monthly')
          TextField(
            controller: _monthlySalary,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: _fieldDecoration('Monthly Salary (₱)'),
          ),
      ],
    );
  }

  Widget _buildActions() {
    return Row(
      children: [
        Expanded(
          child: OutlinedButton(
            style: OutlinedButton.styleFrom(
              foregroundColor: _navy,
              side: const BorderSide(color: Color(0xFFD1D5DB)),
              minimumSize: const Size.fromHeight(48),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            onPressed: _submitting ? null : () => Navigator.pop(context),
            child: const Text(
              'Cancel',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: _navy,
              foregroundColor: Colors.white,
              disabledBackgroundColor: _navy.withValues(alpha: 0.4),
              minimumSize: const Size.fromHeight(48),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            onPressed: !_ready || _submitting ? null : _submit,
            child: Text(
              _submitting
                  ? 'Saving...'
                  : widget.editing
                      ? 'Save Changes'
                      : 'Add Employee',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    final employee = widget.employee ?? const <String, dynamic>{};
    final displayName = _fullName.text.trim().isEmpty
        ? (widget.editing
            ? '${employee['full_name'] ?? 'Employee'}'
            : 'New team member')
        : _fullName.text.trim();
    final displayRole = _positionTitle.text.trim().isEmpty
        ? (widget.editing
            ? '${employee['position_title'] ?? 'No role'}'
            : 'Choose a role to continue')
        : _positionTitle.text.trim();
    final fullTime = _employmentType == 'full_time';
    final maxHeight = MediaQuery.sizeOf(context).height * 0.88;

    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxHeight),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 10),
            Container(
              width: 42,
              height: 4,
              decoration: BoxDecoration(
                color: const Color(0xFFD1D5DB),
                borderRadius: BorderRadius.circular(999),
              ),
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      widget.editing ? 'Edit Employee' : 'Add Employee',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF111827),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [_navy, Color(0xFF2A5A84)],
                        ),
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [
                          BoxShadow(
                            color: _navy.withValues(alpha: 0.18),
                            blurRadius: 18,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                      child: Row(
                        children: [
                          Container(
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(color: _softBlue, width: 2),
                            ),
                            child: EmployeeAvatar(
                              imageUrl: widget.editing
                                  ? employee['profile_image_url'] as String?
                                  : null,
                              name: displayName,
                              size: 72,
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  displayName,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 18,
                                    color: Colors.white,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  displayRole,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: Colors.white.withValues(alpha: 0.82),
                                  ),
                                ),
                                const SizedBox(height: 10),
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  children: [
                                    _Chip(
                                      label: fullTime
                                          ? 'Full Timer'
                                          : 'Part Timer',
                                      background: fullTime
                                          ? const Color(0xFFB7FA84)
                                          : const Color(0xFFFFE27C),
                                      foreground: const Color(0xFF111827),
                                    ),
                                    _Chip(
                                      label: widget.editing
                                          ? 'Editing profile'
                                          : 'Enrolling',
                                      background: const Color(0x33FFFFFF),
                                      foreground: Colors.white,
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFAFBFC),
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: const Color(0xFFE5E7EB)),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.03),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: _buildFields(),
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
              child: _buildActions(),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmployeeDetailsSheet extends StatefulWidget {
  const _EmployeeDetailsSheet({
    required this.employee,
    required this.workdays,
    required this.onEdit,
    required this.onDelete,
    required this.onRestore,
  });

  final Map<String, dynamic> employee;
  final String workdays;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final Future<void> Function() onRestore;

  @override
  State<_EmployeeDetailsSheet> createState() => _EmployeeDetailsSheetState();
}

class _EmployeeDetailsSheetState extends State<_EmployeeDetailsSheet> {
  static const _navy = Color(0xFF1F456B);
  static const _softBlue = Color(0xFFB9D8EE);

  bool _showPassword = false;

  Future<void> _copy(String value, String message) async {
    await Clipboard.setData(ClipboardData(text: value));
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  String get _accountStatus {
    if (widget.employee['status'] == 'inactive') return 'Disabled';
    if (widget.employee['must_change_password'] == true) {
      return 'Pending Activation';
    }
    return 'Active';
  }

  Color _statusBg(String status) {
    switch (status) {
      case 'Active':
        return const Color(0xFFD1FAE5);
      case 'Pending Activation':
        return const Color(0xFFFEF3C7);
      default:
        return const Color(0xFFE5E7EB);
    }
  }

  Color _statusFg(String status) {
    switch (status) {
      case 'Active':
        return const Color(0xFF065F46);
      case 'Pending Activation':
        return const Color(0xFF92400E);
      default:
        return const Color(0xFF374151);
    }
  }

  @override
  Widget build(BuildContext context) {
    final employee = widget.employee;
    final fullTime = employee['employment_type'] == 'full_time';
    final tempPassword = employee['temporary_password'] as String?;
    final statusLabel = _accountStatus;
    final maxHeight = MediaQuery.sizeOf(context).height * 0.88;

    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxHeight),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 10),
          Container(
            width: 42,
            height: 4,
            decoration: BoxDecoration(
              color: const Color(0xFFD1D5DB),
              borderRadius: BorderRadius.circular(999),
            ),
          ),
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'Employee Details',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF111827),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [_navy, Color(0xFF2A5A84)],
                      ),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      children: [
                        Container(
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(color: _softBlue, width: 2),
                          ),
                          child: EmployeeAvatar(
                            imageUrl:
                                employee['profile_image_url'] as String?,
                            name: '${employee['full_name'] ?? 'Employee'}',
                            size: 72,
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${employee['full_name'] ?? 'Employee'}',
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 18,
                                  color: Colors.white,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                '${employee['position_title'] ?? 'No role'}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 13,
                                  color: Colors.white.withValues(alpha: 0.82),
                                ),
                              ),
                              const SizedBox(height: 10),
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: [
                                  _Chip(
                                    label: fullTime
                                        ? 'Full Timer'
                                        : 'Part Timer',
                                    background: fullTime
                                        ? const Color(0xFFB7FA84)
                                        : const Color(0xFFFFE27C),
                                    foreground: const Color(0xFF111827),
                                  ),
                                  _Chip(
                                    label: statusLabel,
                                    background: _statusBg(statusLabel),
                                    foreground: _statusFg(statusLabel),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFAFBFC),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: const Color(0xFFE5E7EB)),
                    ),
                    child: Column(
                      children: [
                        _DetailInfoRow(
                          icon: Icons.phone_outlined,
                          label: 'Contact',
                          value:
                              '${employee['phone'] ?? 'No contact number'}',
                        ),
                        const Divider(height: 1, color: Color(0xFFF3F4F6)),
                        _DetailInfoRow(
                          icon: Icons.work_outline_rounded,
                          label: 'Role',
                          value:
                              '${employee['position_title'] ?? 'No role'}',
                        ),
                        const Divider(height: 1, color: Color(0xFFF3F4F6)),
                        _DetailInfoRow(
                          icon: Icons.badge_outlined,
                          label: 'Employment',
                          value: fullTime ? 'Full Timer' : 'Part Timer',
                        ),
                        const Divider(height: 1, color: Color(0xFFF3F4F6)),
                        _DetailInfoRow(
                          icon: Icons.calendar_today_outlined,
                          label: 'Work days',
                          value: widget.workdays,
                        ),
                        const Divider(height: 1, color: Color(0xFFF3F4F6)),
                        _DetailInfoRow(
                          icon: Icons.key_outlined,
                          label: 'Username',
                          value: '${employee['username']}',
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Login Credentials',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                      color: Color(0xFF111827),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: const Color(0xFFE5E7EB)),
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0x0F000000),
                          blurRadius: 8,
                          offset: Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Column(
                      children: [
                        _CredentialTile(
                          label: 'Username',
                          value: '${employee['username']}',
                          onCopy: () => _copy(
                            '${employee['username']}',
                            'Username copied',
                          ),
                        ),
                        const SizedBox(height: 10),
                        _CredentialTile(
                          label: 'Temporary Password',
                          value: tempPassword == null
                              ? 'Not available'
                              : _showPassword
                                  ? tempPassword
                                  : '********',
                          onCopy: tempPassword == null
                              ? null
                              : () =>
                                  _copy(tempPassword, 'Password copied'),
                          trailing: tempPassword == null
                              ? null
                              : IconButton(
                                  visualDensity: VisualDensity.compact,
                                  onPressed: () => setState(
                                    () => _showPassword = !_showPassword,
                                  ),
                                  icon: Icon(
                                    _showPassword
                                        ? Icons.visibility_off_outlined
                                        : Icons.visibility_outlined,
                                    size: 20,
                                    color: const Color(0xFF6B7280),
                                  ),
                                ),
                        ),
                        const SizedBox(height: 10),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF8FAFC),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            children: [
                              const Expanded(
                                child: Text(
                                  'Account Status',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w500,
                                    color: Color(0xFF6B7280),
                                  ),
                                ),
                              ),
                              _Chip(
                                label: statusLabel,
                                background: _statusBg(statusLabel),
                                foreground: _statusFg(statusLabel),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: _navy,
                      side: const BorderSide(color: Color(0xFFD1D5DB)),
                      minimumSize: const Size.fromHeight(48),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    onPressed: widget.onEdit,
                    child: const Text(
                      'Edit',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: employee['status'] == 'inactive'
                          ? _navy
                          : const Color(0xFFDC2626),
                      foregroundColor: Colors.white,
                      minimumSize: const Size.fromHeight(48),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    onPressed: employee['status'] == 'inactive'
                        ? () => widget.onRestore()
                        : widget.onDelete,
                    child: Text(
                      employee['status'] == 'inactive' ? 'Restore' : 'Delete',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({
    required this.label,
    required this.background,
    required this.foreground,
  });

  final String label;
  final Color background;
  final Color foreground;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: foreground,
        ),
      ),
    );
  }
}

class _DetailInfoRow extends StatelessWidget {
  const _DetailInfoRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: const Color(0xFFEEF3F8),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, size: 18, color: const Color(0xFF1F456B)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label.toUpperCase(),
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.4,
                    color: Color(0xFF9CA3AF),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF111827),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CredentialTile extends StatelessWidget {
  const _CredentialTile({
    required this.label,
    required this.value,
    this.onCopy,
    this.trailing,
  });

  final String label;
  final String value;
  final VoidCallback? onCopy;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 12, color: Color(0xFF6B7280)),
        ),
        const SizedBox(height: 4),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: const Color(0xFFFAFBFC),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFE5E7EB)),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  value,
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: Color(0xFF1F2937),
                  ),
                ),
              ),
              if (trailing != null) trailing!,
              if (onCopy != null)
                IconButton(
                  visualDensity: VisualDensity.compact,
                  onPressed: onCopy,
                  icon: const Icon(
                    Icons.copy_rounded,
                    size: 18,
                    color: Color(0xFF6B7280),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _EmployeeFilterSheet extends StatelessWidget {
  const _EmployeeFilterSheet({
    required this.employmentFilter,
    required this.statusFilter,
    required this.positionFilter,
    required this.positions,
    required this.onApply,
  });

  final String employmentFilter;
  final String statusFilter;
  final String positionFilter;
  final List<Map<String, dynamic>> positions;
  final void Function(String employment, String status, String position)
      onApply;

  @override
  Widget build(BuildContext context) {
    var employment = employmentFilter;
    var status = statusFilter;
    var position = positionFilter;

    return StatefulBuilder(
      builder: (context, setLocalState) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Filter Employees',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                initialValue: employment,
                decoration: const InputDecoration(labelText: 'Employment Type'),
                items: const [
                  DropdownMenuItem(value: 'all', child: Text('All types')),
                  DropdownMenuItem(
                      value: 'full_time', child: Text('Full-Time')),
                  DropdownMenuItem(
                      value: 'part_time', child: Text('Part-Time')),
                ],
                onChanged: (value) =>
                    setLocalState(() => employment = value ?? 'all'),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: status,
                decoration: const InputDecoration(labelText: 'Status'),
                items: const [
                  DropdownMenuItem(value: 'all', child: Text('All statuses')),
                  DropdownMenuItem(value: 'active', child: Text('Active')),
                  DropdownMenuItem(value: 'invited', child: Text('Invited')),
                  DropdownMenuItem(value: 'inactive', child: Text('Inactive')),
                ],
                onChanged: (value) =>
                    setLocalState(() => status = value ?? 'all'),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: position,
                decoration:
                    const InputDecoration(labelText: 'Role / Department'),
                items: [
                  const DropdownMenuItem(
                      value: 'all', child: Text('All roles')),
                  ...positions.map(
                    (item) => DropdownMenuItem(
                      value: '${item['title']}',
                      child: Text('${item['title']}'),
                    ),
                  ),
                ],
                onChanged: (value) =>
                    setLocalState(() => position = value ?? 'all'),
              ),
              const SizedBox(height: 20),
              FilledButton(
                onPressed: () => onApply(employment, status, position),
                child: const Text('Apply Filters'),
              ),
            ],
          ),
        );
      },
    );
  }
}

String _shortWeekday(String dateKey) {
  final date = DateTime.parse(dateKey);
  switch (date.weekday) {
    case DateTime.monday:
      return 'M';
    case DateTime.tuesday:
      return 'T';
    case DateTime.wednesday:
      return 'W';
    case DateTime.thursday:
      return 'Th';
    case DateTime.friday:
      return 'F';
    case DateTime.saturday:
      return 'S';
    case DateTime.sunday:
      return 'Su';
    default:
      return DateFormat('EEE').format(date);
  }
}
