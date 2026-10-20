import 'package:aroll_mobile/core/app_state.dart';
import 'package:aroll_mobile/core/di/injection.dart';
import 'package:aroll_mobile/core/router/app_router.dart';
import 'package:aroll_mobile/domain/repositories/employee_repository.dart';
import 'package:aroll_mobile/presentation/employee/employee_ui.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class EmployeeRecoveryEmailScreen extends StatefulWidget {
  const EmployeeRecoveryEmailScreen({super.key, this.voluntary = false});

  /// Existing employees can register an email without repeating first login.
  final bool voluntary;

  @override
  State<EmployeeRecoveryEmailScreen> createState() =>
      _EmployeeRecoveryEmailScreenState();
}

class _EmployeeRecoveryEmailScreenState
    extends State<EmployeeRecoveryEmailScreen> {
  final _email = TextEditingController();
  bool _saving = false;
  bool _done = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  bool get _emailLooksValid {
    final value = _email.text.trim();
    return RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(value);
  }

  Future<void> _save() async {
    if (_saving || !_emailLooksValid) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await sl<EmployeeRepository>().registerRecoveryEmail(_email.text);
      if (!mounted) return;
      sl<AppState>().markRecoveryEmailRegistered();
      setState(() {
        _saving = false;
        _done = true;
      });
    } on DioException catch (error) {
      if (!mounted) return;
      final data = error.response?.data;
      String message = 'Could not save your recovery email. Please try again.';
      if (data is Map && data['detail'] is String) {
        message = data['detail'] as String;
      }
      setState(() {
        _saving = false;
        _error = message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = 'Could not save your recovery email. Please try again.';
      });
    }
  }

  void _continue() {
    if (widget.voluntary) {
      if (context.canPop()) {
        context.pop();
      } else {
        context.go('/profile');
      }
      return;
    }
    context.go(resolveAuthenticatedRoute(sl<AppState>()));
  }

  @override
  Widget build(BuildContext context) {
    final voluntary = widget.voluntary;
    return Scaffold(
      backgroundColor: EmployeeColors.scaffold,
      appBar: AppBar(
        backgroundColor: EmployeeColors.scaffold,
        elevation: 0,
        scrolledUnderElevation: 0,
        automaticallyImplyLeading: voluntary,
        title: Text(
          voluntary ? 'Recovery email' : 'Account setup',
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Text(
              _done
                  ? 'Account setup saved'
                  : voluntary
                      ? 'Register a recovery email'
                      : 'Step 2: Register a recovery email',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const SizedBox(height: 8),
            Text(
              _done
                  ? 'Your recovery email is saved. You can continue.'
                  : 'This email receives a verification code if you forget your password. It does not replace your username.',
              style: const TextStyle(
                color: EmployeeColors.textMuted,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 24),
            if (!_done) ...[
              TextField(
                controller: _email,
                keyboardType: TextInputType.emailAddress,
                autocorrect: false,
                enableSuggestions: false,
                decoration: employeeInputDecoration(
                  context,
                  labelText: 'Recovery email',
                ),
                onChanged: (_) => setState(() => _error = null),
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(
                  _error!,
                  style: const TextStyle(color: EmployeeColors.danger),
                ),
              ],
              const SizedBox(height: 20),
              FilledButton(
                onPressed: _saving || !_emailLooksValid ? null : _save,
                child: Text(_saving ? 'Saving...' : 'Save recovery email'),
              ),
            ] else
              FilledButton(
                onPressed: _continue,
                child: const Text('Continue'),
              ),
          ],
        ),
      ),
    );
  }
}
