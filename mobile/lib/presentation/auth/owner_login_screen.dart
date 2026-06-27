import 'package:aroll_mobile/core/app_state.dart';
import 'package:aroll_mobile/core/di/injection.dart';
import 'package:aroll_mobile/domain/repositories/auth_repository.dart';
import 'package:aroll_mobile/presentation/auth/owner_auth_ui.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class OwnerLoginScreen extends StatefulWidget {
  const OwnerLoginScreen({super.key});

  @override
  State<OwnerLoginScreen> createState() => _OwnerLoginScreenState();
}

class _OwnerLoginScreenState extends State<OwnerLoginScreen> {
  final _businessCode = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _loading = false;

  @override
  void dispose() {
    _businessCode.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_loading) return;
    setState(() => _loading = true);
    final result = await sl<AuthRepository>().ownerLogin(
      businessCode: _businessCode.text,
      email: _email.text,
      password: _password.text,
    );
    if (!mounted) return;
    setState(() => _loading = false);
    if (result.failure != null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(result.failure!.message)));
      return;
    }
    final session = result.data!;
    sl<AppState>().setSession(
      session,
      mustChange: session.mustChangePassword,
    );
    context.go(session.mustChangePassword
        ? '/change-password'
        : session.setupCompletedAt == null
            ? '/owner/setup-wizard'
            : '/owner/home');
  }

  @override
  Widget build(BuildContext context) {
    return OwnerAuthScaffold(
      badgeLabel: 'Owner portal',
      title: 'Welcome back',
      subtitle: 'Sign in with your business code and owner credentials.',
      child: OwnerAuthCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            OwnerAuthField(
              controller: _businessCode,
              label: 'Business Code',
              hintText: 'MB-D90987',
              prefixIcon: Icons.storefront_outlined,
              textInputAction: TextInputAction.next,
            ),
            OwnerAuthField(
              controller: _email,
              label: 'Email Address',
              hintText: 'owner@business.com',
              prefixIcon: Icons.mail_outline_rounded,
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.next,
            ),
            OwnerAuthField(
              controller: _password,
              label: 'Password',
              hintText: 'Enter your password',
              prefixIcon: Icons.lock_outline_rounded,
              obscureText: true,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _submit(),
            ),
            const SizedBox(height: 4),
            OwnerAuthPrimaryButton(
              label: _loading ? 'Signing in...' : 'Sign In',
              loading: _loading,
              icon: Icons.arrow_forward_rounded,
              onPressed: _loading ? null : _submit,
            ),
            const SizedBox(height: 8),
            OwnerAuthTextLink(
              label: 'Track registration status',
              onPressed: () => context.go('/track-registration'),
            ),
          ],
        ),
      ),
    );
  }
}
