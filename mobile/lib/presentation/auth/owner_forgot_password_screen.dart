import 'dart:async';

import 'package:aroll_mobile/core/di/injection.dart';
import 'package:aroll_mobile/core/utils/password_validation.dart';
import 'package:aroll_mobile/core/utils/resend_countdown.dart';
import 'package:aroll_mobile/domain/repositories/auth_repository.dart';
import 'package:aroll_mobile/presentation/auth/owner_auth_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

class OwnerForgotPasswordScreen extends StatefulWidget {
  const OwnerForgotPasswordScreen({super.key});

  @override
  State<OwnerForgotPasswordScreen> createState() =>
      _OwnerForgotPasswordScreenState();
}

class _OwnerForgotPasswordScreenState extends State<OwnerForgotPasswordScreen>
    with WidgetsBindingObserver {
  final _email = TextEditingController();
  final _businessCode = TextEditingController();
  final _code = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();

  _ResetStep _step = _ResetStep.request;
  DateTime? _resendAvailableAt;
  Timer? _ticker;
  bool _busy = false;
  String? _message;
  String? _resetToken;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _ticker?.cancel();
    _email.dispose();
    _businessCode.dispose();
    _code.dispose();
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _syncCountdownFromServer();
    }
  }

  int get _secondsLeft =>
      resendSecondsRemaining(_resendAvailableAt, DateTime.now());

  void _rememberCooldown(DateTime? availableAt) {
    _resendAvailableAt = availableAt;
    _ticker?.cancel();
    if (_secondsLeft <= 0) return;
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {});
      if (_secondsLeft <= 0) _ticker?.cancel();
    });
  }

  Future<void> _syncCountdownFromServer() async {
    if (_email.text.trim().isEmpty || _businessCode.text.trim().isEmpty) return;
    final result = await sl<AuthRepository>().ownerResetStatus(
      email: _email.text,
      businessCode: _businessCode.text,
    );
    if (!mounted || result.failure != null) return;
    setState(() => _rememberCooldown(result.data?.resendAvailableAt));
  }

  Future<void> _requestCode() async {
    if (_busy || _secondsLeft > 0) return;
    if (_email.text.trim().isEmpty || _businessCode.text.trim().isEmpty) {
      setState(() => _message = 'Enter your registered email and business code.');
      return;
    }
    setState(() {
      _busy = true;
      _message = null;
    });
    final result = await sl<AuthRepository>().requestOwnerResetCode(
      email: _email.text,
      businessCode: _businessCode.text,
    );
    if (!mounted) return;
    final ticket = result.data;
    setState(() {
      _busy = false;
      if (ticket != null) {
        _rememberCooldown(ticket.resendAvailableAt);
        _message = ticket.message;
        if (ticket.accepted || ticket.retryAfterSeconds > 0) {
          _step = _ResetStep.verify;
        }
      } else {
        _message = result.failure?.message ?? 'Could not send a code.';
      }
    });
  }

  Future<void> _verify() async {
    if (_busy || _code.text.trim().length != 6) return;
    setState(() {
      _busy = true;
      _message = null;
    });
    final result = await sl<AuthRepository>().verifyOwnerResetCode(
      email: _email.text,
      businessCode: _businessCode.text,
      code: _code.text,
    );
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (result.data != null) {
        _resetToken = result.data;
        _step = _ResetStep.password;
        _message = null;
      } else {
        _message = result.failure?.message ?? 'That code could not be verified.';
      }
    });
  }

  Future<void> _savePassword() async {
    final token = _resetToken;
    final validation = validatePassword(_password.text);
    if (_busy || token == null || !validation.valid) return;
    if (!passwordsMatch(_password.text, _confirm.text)) {
      setState(() => _message = 'The passwords do not match.');
      return;
    }
    setState(() {
      _busy = true;
      _message = null;
    });
    final failure = await sl<AuthRepository>().completeOwnerPasswordReset(
      resetToken: token,
      newPassword: _password.text,
    );
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (failure == null) {
        _resetToken = null;
        _step = _ResetStep.done;
        _message = null;
      } else {
        _message = failure.message;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final title = switch (_step) {
      _ResetStep.request => 'Forgot password',
      _ResetStep.verify => 'Enter verification code',
      _ResetStep.password => 'Create a new password',
      _ResetStep.done => 'Password updated',
    };
    return OwnerAuthScaffold(
      badgeLabel: 'Owner portal',
      title: title,
      subtitle: switch (_step) {
        _ResetStep.request =>
          'Enter the email registered to your owner account and your business code. We will send a verification code to that email.',
        _ResetStep.verify =>
          'Enter the 6-digit code sent to your registered email. The code expires in 10 minutes.',
        _ResetStep.password =>
          'Choose a new password. You will sign in with your email and business code afterward.',
        _ResetStep.done =>
          'Your password was updated. Sign in with your email, business code, and new password.',
      },
      onBack: () => context.go('/login/owner'),
      child: OwnerAuthCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_step == _ResetStep.request || _step == _ResetStep.verify) ...[
              OwnerAuthField(
                controller: _email,
                label: 'Registered email',
                hintText: 'owner@business.com',
                prefixIcon: Icons.mail_outline_rounded,
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.next,
                readOnly: _step != _ResetStep.request,
                onChanged: (_) => setState(() {}),
              ),
              OwnerAuthField(
                controller: _businessCode,
                label: 'Business code',
                hintText: 'MB-D90987',
                prefixIcon: Icons.storefront_outlined,
                textInputAction: TextInputAction.done,
                readOnly: _step != _ResetStep.request,
                onChanged: (_) => setState(() {}),
              ),
            ],
            if (_step == _ResetStep.verify)
              OwnerAuthField(
                controller: _code,
                label: 'Verification code',
                hintText: '6-digit code',
                prefixIcon: Icons.pin_outlined,
                keyboardType: TextInputType.number,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(6),
                ],
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _verify(),
                onChanged: (_) => setState(() {}),
              ),
            if (_step == _ResetStep.password) ...[
              OwnerAuthField(
                controller: _password,
                label: 'New password',
                prefixIcon: Icons.lock_outline_rounded,
                obscureText: true,
                onChanged: (_) => setState(() {}),
              ),
              OwnerAuthField(
                controller: _confirm,
                label: 'Confirm new password',
                prefixIcon: Icons.lock_outline_rounded,
                obscureText: true,
                onChanged: (_) => setState(() {}),
              ),
              ...validatePassword(_password.text).errors.map(
                    (error) => Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Text(
                        error,
                        style: const TextStyle(
                          color: OwnerAuthColors.textMuted,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ),
            ],
            if (_message != null) ...[
              const SizedBox(height: 8),
              Text(
                _message!,
                style: const TextStyle(
                  color: OwnerAuthColors.textSecondary,
                  height: 1.35,
                ),
              ),
            ],
            const SizedBox(height: 12),
            if (_step == _ResetStep.request || _step == _ResetStep.verify) ...[
              if (_secondsLeft > 0)
                Text(
                  resendCountdownLabel(_secondsLeft),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: OwnerAuthColors.textMuted,
                    fontWeight: FontWeight.w600,
                  ),
                )
              else if (_step == _ResetStep.verify)
                TextButton(
                  onPressed: _busy ? null : _requestCode,
                  child: const Text('Resend code'),
                ),
              const SizedBox(height: 8),
            ],
            if (_step == _ResetStep.request)
              OwnerAuthPrimaryButton(
                label: _busy ? 'Sending...' : 'Send verification code',
                loading: _busy,
                onPressed: _busy || _secondsLeft > 0 ? null : _requestCode,
              ),
            if (_step == _ResetStep.verify)
              OwnerAuthPrimaryButton(
                label: _busy ? 'Verifying...' : 'Verify',
                loading: _busy,
                onPressed: _busy || _code.text.trim().length != 6 ? null : _verify,
              ),
            if (_step == _ResetStep.password)
              OwnerAuthPrimaryButton(
                label: _busy ? 'Saving...' : 'Save new password',
                loading: _busy,
                onPressed: _busy ? null : _savePassword,
              ),
            if (_step == _ResetStep.done)
              OwnerAuthPrimaryButton(
                label: 'Back to sign in',
                onPressed: () => context.go('/login/owner'),
              ),
          ],
        ),
      ),
    );
  }
}

enum _ResetStep { request, verify, password, done }
