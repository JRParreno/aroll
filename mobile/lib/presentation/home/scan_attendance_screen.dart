import 'package:aroll_mobile/presentation/employee/employee_ui.dart';
import 'package:flutter/material.dart';

class ScanAttendanceScreen extends StatelessWidget {
  const ScanAttendanceScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return EmployeeScaffold(
      title: 'Scan Attendance',
      selectedIndex: 2,
      showBack: true,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        child: Column(
          children: [
            const Spacer(),
            EmployeeCard(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
              child: Column(
                children: [
                  Container(
                    height: 120,
                    width: 120,
                    decoration: BoxDecoration(
                      color: EmployeeColors.iconWell,
                      borderRadius: BorderRadius.circular(28),
                    ),
                    child: const Icon(
                      Icons.face_retouching_natural_rounded,
                      size: 64,
                      color: EmployeeColors.primary,
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'Face Recognition Coming Soon',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'Attendance scanning is prepared in the app, but camera-based face recognition is not enabled yet.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: EmployeeColors.textMuted,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
            const Spacer(),
            EmployeePrimaryButton(
              label: 'Back to Dashboard',
              onPressed: () => employeeNavigateBack(context),
            ),
          ],
        ),
      ),
    );
  }
}
