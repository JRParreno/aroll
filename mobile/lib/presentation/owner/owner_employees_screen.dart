import 'package:aroll_mobile/core/di/injection.dart';
import 'package:aroll_mobile/data/repositories/owner_repository.dart';
import 'package:aroll_mobile/presentation/employee/employee_ui.dart';
import 'package:aroll_mobile/presentation/owner/owner_mobile.dart';
import 'package:aroll_mobile/presentation/owner/owner_schedule_utils.dart';
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
      builder: (context) => _EmployeeFormSheet(
        positions: _positions,
        onSubmit: (form) async {
          final employee = await _repo.createEmployee(
            fullName: form.fullName,
            positionTitle: form.positionTitle,
            positionId: form.positionId,
            employmentType: form.employmentType,
            phone: form.phone,
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
      builder: (context) => _EmployeeFormSheet(
        positions: _positions,
        editing: true,
        initial: _EmployeeForm.fromEmployee(employee),
        onSubmit: (form) async {
          await _repo.updateEmployee(
            employeeId: '${employee['id']}',
            fullName: form.fullName,
            positionTitle: form.positionTitle,
            positionId: form.positionId,
            employmentType: form.employmentType,
            phone: form.phone.isEmpty ? null : form.phone,
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
      builder: (context) => AlertDialog(
        title: const Text('Employee Login Credentials'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Share these credentials with the employee so they can '
              'activate their account.',
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
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Done'),
          ),
        ],
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
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(_error!),
                            TextButton(
                              onPressed: _loadData,
                              child: const Text('Retry'),
                            ),
                          ],
                        ),
                      )
                    : RefreshIndicator(
                        onRefresh: _loadData,
                        child: _filteredEmployees.isEmpty
                            ? ListView(
                                children: const [
                                  SizedBox(height: 80),
                                  Center(
                                    child: Text('No employees found.'),
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
  });

  final String fullName;
  final String positionTitle;
  final String positionId;
  final String employmentType;
  final String phone;

  factory _EmployeeForm.fromEmployee(Map<String, dynamic> employee) {
    return _EmployeeForm(
      fullName: '${employee['full_name'] ?? ''}',
      positionTitle: '${employee['position_title'] ?? ''}',
      positionId: '',
      employmentType: '${employee['employment_type'] ?? 'full_time'}',
      phone: '${employee['phone'] ?? ''}',
    );
  }
}

class _EmployeeFormSheet extends StatefulWidget {
  const _EmployeeFormSheet({
    required this.positions,
    required this.onSubmit,
    this.editing = false,
    this.initial,
  });

  final List<Map<String, dynamic>> positions;
  final Future<void> Function(_EmployeeForm form) onSubmit;
  final bool editing;
  final _EmployeeForm? initial;

  @override
  State<_EmployeeFormSheet> createState() => _EmployeeFormSheetState();
}

class _EmployeeFormSheetState extends State<_EmployeeFormSheet> {
  late final TextEditingController _fullName;
  late final TextEditingController _phone;
  late final TextEditingController _positionTitle;
  late String _positionId;
  late String _employmentType;
  bool _submitting = false;

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
        );
    _fullName = TextEditingController(text: initial.fullName);
    _phone = TextEditingController(text: initial.phone);
    _positionTitle = TextEditingController(text: initial.positionTitle);
    _positionId = initial.positionId;
    _employmentType = initial.employmentType;
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
  }

  @override
  void dispose() {
    _fullName.dispose();
    _phone.dispose();
    _positionTitle.dispose();
    super.dispose();
  }

  bool get _ready =>
      _fullName.text.trim().isNotEmpty &&
      (widget.positions.isNotEmpty
          ? _positionId.isNotEmpty || _positionTitle.text.trim().isNotEmpty
          : _positionTitle.text.trim().isNotEmpty);

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

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + bottomInset),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            widget.editing ? 'Edit Employee' : 'Add Employee',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
          ),
          const SizedBox(height: 16),
          if (!widget.editing)
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFEFF6FF),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFBFDBFE)),
              ),
              child: const Text(
                'Username and temporary password are generated automatically '
                'after enrollment.',
                style: TextStyle(color: Color(0xFF1E40AF), fontSize: 13),
              ),
            ),
          if (!widget.editing) const SizedBox(height: 12),
          TextField(
            controller: _fullName,
            decoration: const InputDecoration(labelText: 'Full Name'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _phone,
            keyboardType: TextInputType.phone,
            decoration: const InputDecoration(labelText: 'Contact Number'),
          ),
          const SizedBox(height: 12),
          if (widget.positions.isNotEmpty)
            DropdownButtonFormField<String>(
              initialValue: _positionId.isEmpty ? null : _positionId,
              decoration: const InputDecoration(labelText: 'Position/Role'),
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
                  }
                });
              },
            )
          else
            TextField(
              controller: _positionTitle,
              decoration: const InputDecoration(labelText: 'Position/Role'),
            ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _employmentType,
            decoration: const InputDecoration(labelText: 'Employment Type'),
            items: const [
              DropdownMenuItem(value: 'full_time', child: Text('Full-Time')),
              DropdownMenuItem(value: 'part_time', child: Text('Part-Time')),
            ],
            onChanged: (value) =>
                setState(() => _employmentType = value ?? 'full_time'),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _submitting ? null : () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  onPressed: !_ready || _submitting ? null : _submit,
                  child: Text(
                    _submitting
                        ? 'Saving...'
                        : widget.editing
                            ? 'Save Changes'
                            : 'Add Employee',
                  ),
                ),
              ),
            ],
          ),
        ],
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

  @override
  Widget build(BuildContext context) {
    final employee = widget.employee;
    final fullTime = employee['employment_type'] == 'full_time';
    final tempPassword = employee['temporary_password'] as String?;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Employee Details',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              EmployeeAvatar(
                imageUrl: employee['profile_image_url'] as String?,
                name: '${employee['full_name'] ?? 'Employee'}',
                size: 64,
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
                        fontSize: 16,
                      ),
                    ),
                    Text('${employee['position_title'] ?? 'No role'}'),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _DetailLine(
              label: 'Contact',
              value: '${employee['phone'] ?? 'No contact number'}'),
          _DetailLine(
              label: 'Role',
              value: '${employee['position_title'] ?? 'No role'}'),
          _DetailLine(
            label: 'Employment',
            value: fullTime ? 'Full Timer' : 'Part Timer',
          ),
          _DetailLine(label: 'Work days', value: widget.workdays),
          _DetailLine(label: 'Status', value: '${employee['status']}'),
          const SizedBox(height: 12),
          const Text(
            'Login Credentials',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          _CredentialTile(
            label: 'Username',
            value: '${employee['username']}',
            onCopy: () => _copy('${employee['username']}', 'Username copied'),
          ),
          const SizedBox(height: 8),
          _CredentialTile(
            label: 'Temporary Password',
            value: tempPassword == null
                ? 'Not available'
                : _showPassword
                    ? tempPassword
                    : '********',
            onCopy: tempPassword == null
                ? null
                : () => _copy(tempPassword, 'Password copied'),
            trailing: tempPassword == null
                ? null
                : IconButton(
                    onPressed: () =>
                        setState(() => _showPassword = !_showPassword),
                    icon: Icon(
                      _showPassword
                          ? Icons.visibility_off_outlined
                          : Icons.visibility_outlined,
                    ),
                  ),
          ),
          const SizedBox(height: 8),
          _DetailLine(label: 'Account Status', value: _accountStatus),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: widget.onEdit,
                  child: const Text('Edit'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor:
                        employee['status'] == 'inactive' ? null : Colors.red,
                  ),
                  onPressed: employee['status'] == 'inactive'
                      ? () => widget.onRestore()
                      : widget.onDelete,
                  child: Text(
                    employee['status'] == 'inactive' ? 'Restore' : 'Delete',
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _DetailLine extends StatelessWidget {
  const _DetailLine({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: RichText(
        text: TextSpan(
          style: DefaultTextStyle.of(context).style,
          children: [
            TextSpan(
              text: '$label: ',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            TextSpan(text: value),
          ],
        ),
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
        Text(label,
            style: const TextStyle(fontSize: 12, color: Color(0xFF6B7280))),
        const SizedBox(height: 4),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
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
                  style: const TextStyle(fontFamily: 'monospace'),
                ),
              ),
              if (trailing != null) trailing!,
              if (onCopy != null)
                IconButton(
                  onPressed: onCopy,
                  icon: const Icon(Icons.copy_rounded, size: 18),
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
