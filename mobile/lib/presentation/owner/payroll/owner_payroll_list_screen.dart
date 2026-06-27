import 'package:aroll_mobile/core/di/injection.dart';
import 'package:aroll_mobile/data/repositories/owner_repository.dart';
import 'package:aroll_mobile/presentation/employee/employee_ui.dart';
import 'package:aroll_mobile/presentation/owner/payroll/owner_payroll_format.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class OwnerPayrollListScreen extends StatefulWidget {
  const OwnerPayrollListScreen({super.key});

  @override
  State<OwnerPayrollListScreen> createState() => _OwnerPayrollListScreenState();
}

class _OwnerPayrollListScreenState extends State<OwnerPayrollListScreen> {
  final _repo = sl<OwnerRepository>();

  bool _loading = true;
  String? _error;
  String _selectedEmployeeId = '';
  List<Map<String, dynamic>> _items = const [];
  List<Map<String, dynamic>> _employees = const [];
  Map<String, String> _profileImages = const {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait([
        _repo.payroll(),
        _repo.employees(),
      ]);
      final payroll = results[0] as Map<String, dynamic>;
      final employees = results[1] as List<Map<String, dynamic>>;
      final images = <String, String>{};
      for (final employee in employees) {
        final id = '${employee['id']}';
        final image = employee['profile_image_url'] as String?;
        if (image != null && image.isNotEmpty) {
          images[id] = image;
        }
      }
      if (!mounted) return;
      setState(() {
        _items = (payroll['items'] as List<dynamic>? ?? const [])
            .whereType<Map<String, dynamic>>()
            .toList();
        _employees = employees;
        _profileImages = images;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Unable to load payroll summary.';
      });
    }
  }

  List<Map<String, dynamic>> get _filteredItems {
    return _items.where((item) {
      if (_selectedEmployeeId.isNotEmpty &&
          '${item['employee_id']}' != _selectedEmployeeId) {
        return false;
      }
      return true;
    }).toList();
  }

  String? get _periodStart =>
      _items.isEmpty ? null : '${_items.first['period_start']}';

  String? get _periodEnd =>
      _items.isEmpty ? null : '${_items.first['period_end']}';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F6F8),
      appBar: AppBar(
        backgroundColor: const Color(0xFFF4F6F8),
        elevation: 0,
        title: const Text(
          'Payroll Summary',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.download_outlined),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _ErrorState(message: _error!, onRetry: _load)
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                    children: [
                      _FilterCard(
                        employees: _employees,
                        selectedEmployeeId: _selectedEmployeeId,
                        periodStart: _periodStart,
                        periodEnd: _periodEnd,
                        onEmployeeChanged: (value) =>
                            setState(() => _selectedEmployeeId = value ?? ''),
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'Employee Salary Overview',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF1E466E),
                        ),
                      ),
                      const SizedBox(height: 12),
                      if (_filteredItems.isEmpty)
                        const _EmptyPayrollCard()
                      else
                        ..._filteredItems.map(
                          (item) => _EmployeePayrollCard(
                            item: item,
                            profileImageUrl:
                                _profileImages['${item['employee_id']}'],
                            onViewDetails: () => context.push(
                              '/owner/payroll/${item['employee_id']}',
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
    );
  }
}

class _FilterCard extends StatelessWidget {
  const _FilterCard({
    required this.employees,
    required this.selectedEmployeeId,
    required this.periodStart,
    required this.periodEnd,
    required this.onEmployeeChanged,
  });

  final List<Map<String, dynamic>> employees;
  final String selectedEmployeeId;
  final String? periodStart;
  final String? periodEnd;
  final ValueChanged<String?> onEmployeeChanged;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            DropdownButtonFormField<String>(
              initialValue: selectedEmployeeId,
              isExpanded: true,
              isDense: true,
              decoration: InputDecoration(
                isDense: true,
                prefixIcon: const Icon(Icons.search, size: 20),
                hintText: 'Select employee',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              ),
              items: [
                const DropdownMenuItem(
                  value: '',
                  child: Text('All employees'),
                ),
                ...employees.map(
                  (employee) => DropdownMenuItem(
                    value: '${employee['id']}',
                    child: Text('${employee['full_name']}'),
                  ),
                ),
              ],
              onChanged: (value) => onEmployeeChanged(value ?? ''),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: _PeriodChip(
                    label: ownerPayrollShortDate(periodStart),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _PeriodChip(
                    label: ownerPayrollShortDate(periodEnd),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _PeriodChip(
                    label: ownerPayrollYear(periodStart),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _PeriodChip extends StatelessWidget {
  const _PeriodChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
      decoration: BoxDecoration(
        border: Border.all(color: const Color(0xFFE5E7EB)),
        borderRadius: BorderRadius.circular(10),
        color: Colors.white,
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
            ),
          ),
          const Icon(Icons.unfold_more, size: 16, color: Color(0xFF9CA3AF)),
        ],
      ),
    );
  }
}

class _EmployeePayrollCard extends StatelessWidget {
  const _EmployeePayrollCard({
    required this.item,
    required this.onViewDetails,
    this.profileImageUrl,
  });

  final Map<String, dynamic> item;
  final VoidCallback onViewDetails;
  final String? profileImageUrl;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${item['employee_name'] ?? 'Employee'}',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                EmployeeAvatar(
                  imageUrl: profileImageUrl,
                  name: '${item['employee_name'] ?? 'Employee'}',
                  size: 44,
                  backgroundColor: const Color(0xFFE7EEF5),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _PayrollMetricRow(
              icon: Icons.calendar_month_outlined,
              label: 'Worked Days',
              value: '${item['worked_days'] ?? 0} Days',
            ),
            _PayrollMetricRow(
              icon: Icons.payments_outlined,
              label: 'Daily Rate',
              value: ownerPayrollMoney(parsePayrollAmount(item['daily_rate'])),
            ),
            _PayrollMetricRow(
              icon: Icons.remove_circle_outline,
              label: 'Deductions',
              value: ownerPayrollMoney(parsePayrollAmount(item['deductions'])),
            ),
            _PayrollMetricRow(
              icon: Icons.schedule_outlined,
              label: 'Overtime Pay',
              value:
                  ownerPayrollMoney(parsePayrollAmount(item['overtime_pay'])),
            ),
            _PayrollMetricRow(
              icon: Icons.account_balance_wallet_outlined,
              label: 'Total Salary',
              value:
                  ownerPayrollMoney(parsePayrollAmount(item['total_salary'])),
              highlight: true,
            ),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: onViewDetails,
                child: const Text('View Details'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PayrollMetricRow extends StatelessWidget {
  const _PayrollMetricRow({
    required this.icon,
    required this.label,
    required this.value,
    this.highlight = false,
  });

  final IconData icon;
  final String label;
  final String value;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(icon, size: 18, color: const Color(0xFF6B7280)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(fontSize: 13, color: Color(0xFF6B7280)),
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: 13,
              fontWeight: highlight ? FontWeight.w700 : FontWeight.w600,
              color:
                  highlight ? const Color(0xFF16A34A) : const Color(0xFF1F2937),
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyPayrollCard extends StatelessWidget {
  const _EmptyPayrollCard();

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Text(
          'No payroll records found.',
          style: TextStyle(color: Colors.grey.shade600),
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(message),
          const SizedBox(height: 12),
          FilledButton(onPressed: onRetry, child: const Text('Retry')),
        ],
      ),
    );
  }
}
