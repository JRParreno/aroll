import 'package:aroll_mobile/core/di/injection.dart';
import 'package:aroll_mobile/data/owner_support_email.dart';
import 'package:aroll_mobile/data/repositories/owner_repository.dart';
import 'package:aroll_mobile/presentation/owner/owner_shell.dart';
import 'package:aroll_mobile/presentation/owner/setup/setup_ui.dart';
import 'package:aroll_mobile/presentation/shared/app_ui.dart';
import 'package:flutter/material.dart';

typedef OwnerSupportSender = Future<Map<String, dynamic>> Function({
  required String subject,
  required String message,
});

class OwnerHelpScreen extends StatelessWidget {
  const OwnerHelpScreen({super.key, this.send});

  final OwnerSupportSender? send;

  @override
  Widget build(BuildContext context) {
    return OwnerShell(
      selectedIndex: 2,
      showBackButton: true,
      title: 'Help',
      backgroundColor: SetupUi.scaffold,
      child: OwnerHelpForm(
        send: send ??
            ({required subject, required message}) =>
                sl<OwnerRepository>().sendOwnerSupportEmail(
                  subject: subject,
                  message: message,
                ),
      ),
    );
  }
}

class OwnerHelpForm extends StatefulWidget {
  const OwnerHelpForm({super.key, required this.send});

  final OwnerSupportSender send;

  @override
  State<OwnerHelpForm> createState() => _OwnerHelpFormState();
}

class _OwnerHelpFormState extends State<OwnerHelpForm> {
  final _subject = TextEditingController();
  final _message = TextEditingController();
  var _sending = false;
  String? _notice;
  var _noticeIsError = false;

  @override
  void dispose() {
    _subject.dispose();
    _message.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_sending) return;
    final validation = ownerSupportDraftError(_subject.text, _message.text);
    if (validation != null) {
      setState(() {
        _notice = validation;
        _noticeIsError = true;
      });
      return;
    }
    setState(() {
      _sending = true;
      _notice = null;
    });
    try {
      final result = await widget.send(
        subject: _subject.text.trim(),
        message: _message.text.trim(),
      );
      if (result['status'] != 'accepted') {
        throw StateError('support email was not accepted');
      }
      final detail = result['detail'];
      if (!mounted) return;
      setState(() {
        _subject.clear();
        _message.clear();
        _noticeIsError = false;
        _notice = detail is String && detail.trim().isNotEmpty
            ? detail.trim()
            : 'The email provider accepted the message. Delivery to the inbox is not guaranteed.';
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _noticeIsError = true;
        _notice = ownerHelpFailureMessage(error);
      });
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
      children: [
        Text(
          'Contact support',
          style: appSectionTitleStyle(),
        ),
        const SizedBox(height: 6),
        const Text(
          'Describe the problem. Aroll+ sends this from your signed-in owner account.',
          style: TextStyle(color: AppColors.textMuted, height: 1.4),
        ),
        const SizedBox(height: 16),
        TextField(
          key: const Key('owner-help-subject'),
          controller: _subject,
          enabled: !_sending,
          maxLength: ownerSupportSubjectMax,
          textInputAction: TextInputAction.next,
          decoration: SetupUi.input('Subject', hint: 'What do you need help with?'),
        ),
        const SizedBox(height: 8),
        TextField(
          key: const Key('owner-help-message'),
          controller: _message,
          enabled: !_sending,
          maxLength: ownerSupportMessageMax,
          minLines: 6,
          maxLines: 10,
          decoration: SetupUi.input(
            'Message',
            hint: 'What happened, and what were you trying to do?',
          ),
        ),
        if (_notice != null) ...[
          const SizedBox(height: 12),
          Text(
            _notice!,
            key: const Key('owner-help-notice'),
            style: TextStyle(
              color: _noticeIsError ? const Color(0xFFB91C1C) : const Color(0xFF166534),
              height: 1.4,
            ),
          ),
        ],
        const SizedBox(height: 16),
        FilledButton(
          key: const Key('owner-help-send'),
          style: appBrandedPrimaryButtonStyle(context),
          onPressed: _sending ? null : _submit,
          child: Text(_sending ? 'Sending...' : 'Send'),
        ),
      ],
    );
  }
}
