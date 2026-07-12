import 'package:aroll_mobile/core/di/injection.dart';
import 'package:aroll_mobile/data/repositories/owner_repository.dart';
import 'package:aroll_mobile/presentation/owner/owner_shell.dart';
import 'package:flutter/material.dart';

class OwnerProductivityScreen extends StatelessWidget {
  const OwnerProductivityScreen({super.key});

  @override
  Widget build(BuildContext context) => OwnerSecondaryScreen(
        title: 'Productivity Insights',
        future: sl<OwnerRepository>().performance(),
        builder: (data) {
          final employees =
              (data['employees'] as List<dynamic>? ?? const [])
                  .whereType<Map<String, dynamic>>()
                  .toList();
          return [
            OwnerPerformanceChart(
              summary: data['summary'] as Map<String, dynamic>? ?? const {},
            ),
            const SizedBox(height: 14),
            if (employees.isEmpty)
              const OwnerEmptyState('No performance records yet.')
            else
              ...employees.map(
                (item) => OwnerCard(
                  margin: const EdgeInsets.only(bottom: 10),
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text('${item['full_name'] ?? 'Employee'}'),
                    subtitle: Text(
                      'Attendance ${item['attendance_rate'] ?? 0}% • '
                      'Punctuality ${item['punctuality_rate'] ?? 0}%',
                    ),
                    trailing: Text(
                      '${item['productivity_score'] ?? 0}',
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ),
          ];
        },
      );
}
