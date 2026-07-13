import 'package:aroll_mobile/core/di/injection.dart';
import 'package:aroll_mobile/domain/repositories/employee_repository.dart';
import 'package:aroll_mobile/presentation/employee/employee_ui.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class FaceRegistrationScreen extends StatefulWidget {
  const FaceRegistrationScreen({super.key});

  @override
  State<FaceRegistrationScreen> createState() => _FaceRegistrationScreenState();
}

class _FaceRegistrationScreenState extends State<FaceRegistrationScreen> {
  bool _saving = false;

  Future<void> _submit(String status) async {
    setState(() => _saving = true);
    try {
      await sl<EmployeeRepository>().updateFaceRegistration(status);
      if (mounted) context.go('/home');
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Unable to save face registration status.')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: EmployeeColors.scaffold,
      appBar: AppBar(
        backgroundColor: EmployeeColors.scaffold,
        elevation: 0,
        scrolledUnderElevation: 0,
        title: const Text(
          'Face Registration',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Spacer(),
              EmployeeCard(
                padding: const EdgeInsets.all(24),
                child: Column(
                  children: [
                    Container(
                      height: 110,
                      width: 110,
                      decoration: const BoxDecoration(
                        color: EmployeeColors.iconWell,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.face_retouching_natural_rounded,
                        size: 58,
                        color: EmployeeColors.primary,
                      ),
                    ),
                    const SizedBox(height: 24),
                    Text(
                      'Register your face',
                      style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 10),
                    const Text(
                      'This helps the system verify your identity when you scan for attendance.',
                      style: TextStyle(color: EmployeeColors.textBody, height: 1.4),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 10),
                    const Text(
                      'Face registration is coming soon. You can continue to your dashboard for now.',
                      style: TextStyle(color: EmployeeColors.textMuted, height: 1.4),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 24),
                    EmployeePrimaryButton(
                      label: 'Register Face - Coming Soon',
                      onPressed: null,
                      icon: Icons.camera_alt_rounded,
                    ),
                    const SizedBox(height: 10),
                    TextButton(
                      onPressed: _saving ? null : () => _submit('skipped'),
                      child: const Text('Skip for Now'),
                    ),
                  ],
                ),
              ),
              const Spacer(),
            ],
          ),
        ),
      ),
    );
  }
}
