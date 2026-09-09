import 'package:flutter/services.dart';

enum LegalDocumentKind { terms, privacy, biometricConsent }

extension LegalDocumentKindX on LegalDocumentKind {
  String get title {
    switch (this) {
      case LegalDocumentKind.terms:
        return 'Terms & Conditions';
      case LegalDocumentKind.privacy:
        return 'Privacy Policy';
      case LegalDocumentKind.biometricConsent:
        return 'Biometric / Face Consent';
    }
  }

  String get assetPath {
    switch (this) {
      case LegalDocumentKind.terms:
        return '../docs/legal/TERMS-AND-CONDITIONS.md';
      case LegalDocumentKind.privacy:
        return '../docs/legal/PRIVACY-POLICY.md';
      case LegalDocumentKind.biometricConsent:
        return '../docs/legal/BIOMETRIC-CONSENT.md';
    }
  }

  String get route {
    switch (this) {
      case LegalDocumentKind.terms:
        return '/legal/docs/terms';
      case LegalDocumentKind.privacy:
        return '/legal/docs/privacy';
      case LegalDocumentKind.biometricConsent:
        return '/legal/docs/biometric-consent';
    }
  }
}

Future<String> loadLegalDocument(LegalDocumentKind kind) async {
  try {
    return await rootBundle.loadString(kind.assetPath);
  } catch (_) {
    // Flutter asset keys sometimes drop the leading "../".
    final fallback = kind.assetPath.replaceFirst('../', '');
    return rootBundle.loadString(fallback);
  }
}
