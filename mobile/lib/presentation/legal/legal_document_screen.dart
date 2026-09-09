import 'package:aroll_mobile/core/legal/legal_documents.dart';
import 'package:aroll_mobile/presentation/shared/app_ui.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class LegalDocumentScreen extends StatelessWidget {
  const LegalDocumentScreen({super.key, required this.kind});

  final LegalDocumentKind kind;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.scaffold,
      appBar: AppBar(
        backgroundColor: AppColors.white,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
        scrolledUnderElevation: 0,
        title: Text(
          kind.title,
          style: const TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 17,
            letterSpacing: -0.2,
          ),
        ),
      ),
      body: FutureBuilder<String>(
        future: loadLegalDocument(kind),
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError || snapshot.data == null) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.xl),
                child: Text(
                  'Unable to load this document. Please try again.',
                  style: appMutedStyle(),
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }
          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
            children: [
              Text(
                _plainLegalText(snapshot.data!),
                style: appBodyStyle().copyWith(height: 1.55, fontSize: 15),
              ),
            ],
          );
        },
      ),
    );
  }
}

String _plainLegalText(String markdown) {
  return markdown
      .replaceAll(RegExp(r'^#+\s*', multiLine: true), '')
      .replaceAll('**', '')
      .replaceAll('“', '"')
      .replaceAll('”', '"');
}

class LegalLinksRow extends StatelessWidget {
  const LegalLinksRow({
    super.key,
    this.lightOnNavy = false,
    this.includeBiometric = false,
  });

  final bool lightOnNavy;
  final bool includeBiometric;

  @override
  Widget build(BuildContext context) {
    final color = lightOnNavy ? const Color(0xFFC8D8E7) : AppColors.primaryDark;
    Widget link(LegalDocumentKind kind) {
      return TextButton(
        onPressed: () => context.push(kind.route),
        style: TextButton.styleFrom(
          foregroundColor: color,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          minimumSize: Size.zero,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
        child: Text(
          kind.title,
          style: TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 12.5,
            decoration: TextDecoration.underline,
            decorationColor: color.withValues(alpha: 0.5),
          ),
        ),
      );
    }

    return Wrap(
      alignment: WrapAlignment.center,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        link(LegalDocumentKind.terms),
        Text('·', style: TextStyle(color: color.withValues(alpha: 0.7))),
        link(LegalDocumentKind.privacy),
        if (includeBiometric) ...[
          Text('·', style: TextStyle(color: color.withValues(alpha: 0.7))),
          link(LegalDocumentKind.biometricConsent),
        ],
      ],
    );
  }
}
