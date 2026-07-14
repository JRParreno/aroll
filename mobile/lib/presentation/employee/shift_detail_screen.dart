import 'package:aroll_mobile/domain/entities/employee_portal.dart';
import 'package:aroll_mobile/presentation/employee/employee_ui.dart';
import 'package:flutter/material.dart';

class ShiftDetailScreen extends StatelessWidget {
  const ShiftDetailScreen({super.key, required this.item});

  final EmployeeScheduleItem item;

  @override
  Widget build(BuildContext context) {
    final statusStyle = employeeScheduleStatusStyle(item.status);
    return EmployeeScaffold(
      title: 'Shift Details',
      selectedIndex: 0,
      showBack: true,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        children: [
          EmployeeCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        item.shiftName,
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                      ),
                    ),
                    EmployeeStatusChip(
                      label: statusStyle.label,
                      color: statusStyle.color,
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                EmployeeInfoRow(
                  icon: Icons.calendar_today_outlined,
                  text:
                      '${monthDay(item.workDate)} · ${item.startLabel} - ${item.endLabel}',
                ),
                if (item.holidayName != null && item.holidayName!.isNotEmpty)
                  EmployeeInfoRow(
                    icon: Icons.celebration_outlined,
                    text: 'Holiday: ${item.holidayName}',
                  ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          EmployeeCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const EmployeeSectionTitle('Location'),
                const SizedBox(height: 8),
                EmployeeInfoRow(
                  icon: Icons.location_on_outlined,
                  text: item.locationLabel ?? 'Work site',
                ),
                if (item.locationAddress != null &&
                    item.locationAddress!.isNotEmpty)
                  EmployeeInfoRow(
                    icon: Icons.map_outlined,
                    text: item.locationAddress!,
                  ),
              ],
            ),
          ),
          if (item.notes != null && item.notes!.isNotEmpty) ...[
            const SizedBox(height: 12),
            EmployeeCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const EmployeeSectionTitle('Notes'),
                  const SizedBox(height: 8),
                  Text(
                    item.notes!,
                    style: const TextStyle(
                      fontSize: 14,
                      color: EmployeeColors.textBody,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
          ],
          if (item.coworkers.isNotEmpty) ...[
            const SizedBox(height: 12),
            EmployeeCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const EmployeeSectionTitle('Coworkers on this shift'),
                  const SizedBox(height: 12),
                  ...item.coworkers.map(
                    (coworker) => Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Row(
                        children: [
                          EmployeeAvatar(
                            imageUrl: coworker.profileImageUrl,
                            name: coworker.fullName,
                            size: 36,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              coworker.isCurrentEmployee
                                  ? '${coworker.fullName} (You)'
                                  : coworker.fullName,
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 14,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
