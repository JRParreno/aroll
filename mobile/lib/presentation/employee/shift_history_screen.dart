import 'package:aroll_mobile/core/di/injection.dart';
import 'package:aroll_mobile/domain/entities/employee_portal.dart';
import 'package:aroll_mobile/domain/repositories/employee_repository.dart';
import 'package:aroll_mobile/presentation/employee/employee_ui.dart';
import 'package:flutter/material.dart';

class ShiftHistoryScreen extends StatefulWidget {
  const ShiftHistoryScreen({super.key});

  @override
  State<ShiftHistoryScreen> createState() => _ShiftHistoryScreenState();
}

class _ShiftHistoryScreenState extends State<ShiftHistoryScreen> {
  final _searchController = TextEditingController();
  String _query = '';
  String _remark = 'all';
  int _month = DateTime.now().month;
  int _year = DateTime.now().year;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return EmployeeScaffold(
      title: 'Shift History',
      selectedIndex: 1,
      showBack: true,
      child: FutureBuilder<List<EmployeeShiftHistoryItem>>(
        future: sl<EmployeeRepository>().getShiftHistory(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return loadingView();
          }
          if (snapshot.hasError) return errorView(snapshot.error);
          final items = _filtered(snapshot.data ?? []);

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
            children: [
              _FilterCard(
                controller: _searchController,
                month: _month,
                year: _year,
                remark: _remark,
                onSearchChanged: (value) => setState(() => _query = value),
                onRemarkChanged: (value) => setState(() => _remark = value),
                onMonthChanged: (value) => setState(() => _month = value),
                onYearChanged: (value) => setState(() => _year = value),
              ),
              const SizedBox(height: 18),
              if (items.isEmpty)
                const EmployeeEmptyState(
                  title: 'No shift history yet',
                  description:
                      'Completed shifts and attendance records will appear here.',
                  icon: Icons.history_rounded,
                  inCard: true,
                )
              else
                ...items.map(
                  (item) => Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: _HistoryCard(item: item),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  List<EmployeeShiftHistoryItem> _filtered(
      List<EmployeeShiftHistoryItem> items) {
    return items.where((item) {
      final matchesPeriod =
          item.date.month == _month && item.date.year == _year;
      if (!matchesPeriod) return false;
      if (_remark != 'all' &&
          _displayStatus(item).toLowerCase().replaceAll(' ', '_') != _remark) {
        return false;
      }
      if (_query.trim().isEmpty) return true;
      final haystack = [
        item.shiftName,
        item.status,
        item.holidayName,
        shortDate(item.date),
      ].whereType<String>().join(' ').toLowerCase();
      return haystack.contains(_query.toLowerCase());
    }).toList();
  }
}

class _FilterCard extends StatelessWidget {
  const _FilterCard({
    required this.controller,
    required this.month,
    required this.year,
    required this.remark,
    required this.onSearchChanged,
    required this.onRemarkChanged,
    required this.onMonthChanged,
    required this.onYearChanged,
  });

  final TextEditingController controller;
  final int month;
  final int year;
  final String remark;
  final ValueChanged<String> onSearchChanged;
  final ValueChanged<String> onRemarkChanged;
  final ValueChanged<int> onMonthChanged;
  final ValueChanged<int> onYearChanged;

  @override
  Widget build(BuildContext context) {
    final years = List.generate(5, (index) => DateTime.now().year - index);
    return EmployeeCard(
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: controller,
                  onChanged: onSearchChanged,
                  decoration: employeeInputDecoration(
                    hintText: 'Search shifts',
                    prefixIcon: const Icon(Icons.search_rounded, size: 18),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: DropdownButtonFormField<String>(
                  initialValue: remark,
                  decoration: employeeInputDecoration(labelText: 'Remarks'),
                  items: const [
                    DropdownMenuItem(value: 'all', child: Text('Remarks')),
                    DropdownMenuItem(value: 'on_time', child: Text('On Time')),
                    DropdownMenuItem(value: 'late', child: Text('Late')),
                    DropdownMenuItem(
                        value: 'over_time', child: Text('Over Time')),
                  ],
                  onChanged: (value) {
                    if (value != null) onRemarkChanged(value);
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<int>(
                  initialValue: month,
                  decoration: employeeInputDecoration(labelText: 'Month'),
                  items: List.generate(
                    12,
                    (index) => DropdownMenuItem(
                      value: index + 1,
                      child: Text(_monthLabel(index + 1)),
                    ),
                  ),
                  onChanged: (value) {
                    if (value != null) onMonthChanged(value);
                  },
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: DropdownButtonFormField<int>(
                  initialValue: year,
                  decoration: employeeInputDecoration(labelText: 'Year'),
                  items: years
                      .map(
                        (year) => DropdownMenuItem(
                          value: year,
                          child: Text('$year'),
                        ),
                      )
                      .toList(),
                  onChanged: (value) {
                    if (value != null) onYearChanged(value);
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Row(
            children: [
              Expanded(
                child: Text(
                  'Date',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: EmployeeColors.textMuted,
                  ),
                ),
              ),
              Expanded(
                child: Text(
                  'Remarks',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: EmployeeColors.textMuted,
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

class _HistoryCard extends StatelessWidget {
  const _HistoryCard({required this.item});

  final EmployeeShiftHistoryItem item;

  @override
  Widget build(BuildContext context) {
    final displayStatus = _displayStatus(item);
    final color = statusColor(displayStatus);
    return EmployeeCard(
      padding: const EdgeInsets.all(14),
      margin: const EdgeInsets.only(bottom: 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  shortDate(item.date),
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                  ),
                ),
              ),
              EmployeeStatusChip(label: displayStatus, color: color),
            ],
          ),
          const SizedBox(height: 10),
          EmployeeInfoRow(
            icon: Icons.calendar_today_outlined,
            text: 'Shift: ${item.shiftStart ?? '--'} - ${item.shiftEnd ?? '--'}',
          ),
          EmployeeInfoRow(
            icon: Icons.login_rounded,
            text: 'Clock In: ${timeOnly(item.timeIn)}',
          ),
          EmployeeInfoRow(
            icon: Icons.logout_rounded,
            text: 'Clock Out: ${timeOnly(item.timeOut)}',
          ),
          EmployeeInfoRow(
            icon: Icons.schedule_rounded,
            text: 'Total Hours: ${_totalHours(item)} hrs',
          ),
        ],
      ),
    );
  }
}

String _displayStatus(EmployeeShiftHistoryItem item) {
  if (item.overtimeMinutes > 0) return 'Over Time';
  if (item.status == 'complete') return 'On Time';
  if (item.status == 'incomplete') return 'Under Time';
  return titleCase(item.status);
}

String _totalHours(EmployeeShiftHistoryItem item) {
  if (item.timeIn == null || item.timeOut == null) return '0';
  final hours = item.timeOut!.difference(item.timeIn!).inMinutes / 60;
  return hours.toStringAsFixed(hours.truncateToDouble() == hours ? 0 : 1);
}

String _monthLabel(int month) {
  return const [
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ][month - 1];
}
