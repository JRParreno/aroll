import 'package:aroll_mobile/presentation/shared/app_ui.dart';
import 'package:flutter/material.dart';

class BiometricConsentView extends StatelessWidget {
  const BiometricConsentView({
    super.key,
    required this.documentText,
    required this.onAgree,
    this.onReadFullDocument,
  });

  final String documentText;
  final VoidCallback onAgree;
  final VoidCallback? onReadFullDocument;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
            children: [
              Text('Face enrollment', style: appPageTitleStyle()),
              const SizedBox(height: 8),
              Text(
                'Please read this information before Aroll+ uses the camera to enroll your face.',
                style: appMutedStyle(),
              ),
              const SizedBox(height: 18),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: appCardDecoration(),
                child: Text(
                  documentText,
                  style: appBodyStyle().copyWith(height: 1.55),
                ),
              ),
              if (onReadFullDocument != null) ...[
                const SizedBox(height: 8),
                TextButton(
                  onPressed: onReadFullDocument,
                  child: const Text('Open full biometric consent document'),
                ),
              ],
            ],
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'The camera will not start until you continue. This confirmation is shown on this device before enrollment. Your agreement is saved on the server as your employee legal consent record.',
                  style: appMutedStyle().copyWith(fontSize: 12),
                ),
                const SizedBox(height: 12),
                FilledButton(
                  style: appPrimaryButtonStyle(),
                  onPressed: onAgree,
                  child: const Text('I understand and continue'),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

String plainBiometricConsentText(String markdown) {
  return markdown
      .replaceAll(RegExp(r'^#+\s*', multiLine: true), '')
      .replaceAll('**', '');
}
