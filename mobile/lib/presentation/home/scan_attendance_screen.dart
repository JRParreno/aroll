import 'package:aroll_mobile/presentation/employee/employee_ui.dart';
import 'package:flutter/material.dart';

class ScanAttendanceScreen extends StatelessWidget {
  const ScanAttendanceScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;

    return EmployeeScaffold(
      title: 'Scan Attendance',
      selectedIndex: 2,
      showBack: true,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        child: Column(
          children: [
            const Spacer(),
            Container(
              height: 150,
              width: 150,
              decoration: BoxDecoration(
                color: primary.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(28),
                border: Border.all(color: primary.withValues(alpha: 0.18)),
              ),
              child: Icon(
                Icons.face_retouching_natural_rounded,
                size: 82,
                color: primary,
              ),
            ),
            const SizedBox(height: 22),
            Text(
              'Face Recognition Coming Soon',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const SizedBox(height: 10),
            Text(
              'Attendance scanning is prepared in the app, but camera-based face recognition is not enabled yet.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: const Color(0xFF6B7280),
                  ),
            ),
            const Spacer(),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Back to Dashboard'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
