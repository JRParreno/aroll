class LegalSection {
  const LegalSection({
    required this.title,
    required this.consentType,
    required this.published,
    this.content,
    this.version,
  });

  final String title;
  final String consentType;
  final bool published;
  final String? content;
  final String? version;

  factory LegalSection.fromJson(Map<String, dynamic> json) {
    return LegalSection(
      title: json['title'] as String? ?? '',
      consentType: json['consent_type'] as String? ?? '',
      published: json['published'] == true,
      content: json['content'] as String?,
      version: json['version'] as String?,
    );
  }
}

class PublicLegalPage {
  const PublicLegalPage({
    required this.businessName,
    required this.businessCode,
    required this.legalPageUrl,
    required this.terms,
    required this.privacy,
    required this.biometric,
  });

  final String businessName;
  final String businessCode;
  final String legalPageUrl;
  final LegalSection terms;
  final LegalSection privacy;
  final LegalSection biometric;

  factory PublicLegalPage.fromJson(Map<String, dynamic> json) {
    return PublicLegalPage(
      businessName: json['business_name'] as String? ?? '',
      businessCode: json['business_code'] as String? ?? '',
      legalPageUrl: json['legal_page_url'] as String? ?? '',
      terms: LegalSection.fromJson(
        json['terms'] as Map<String, dynamic>? ?? const {},
      ),
      privacy: LegalSection.fromJson(
        json['privacy'] as Map<String, dynamic>? ?? const {},
      ),
      biometric: LegalSection.fromJson(
        json['biometric'] as Map<String, dynamic>? ?? const {},
      ),
    );
  }
}

class ConsentTypeStatus {
  const ConsentTypeStatus({
    required this.consentType,
    required this.published,
    required this.satisfied,
    this.currentVersion,
    this.acceptedVersion,
    this.acceptedAt,
  });

  final String consentType;
  final bool published;
  final bool satisfied;
  final String? currentVersion;
  final String? acceptedVersion;
  final DateTime? acceptedAt;

  factory ConsentTypeStatus.fromJson(Map<String, dynamic> json) {
    return ConsentTypeStatus(
      consentType: json['consent_type'] as String? ?? '',
      published: json['published'] == true,
      satisfied: json['satisfied'] == true,
      currentVersion: json['current_version'] as String?,
      acceptedVersion: json['accepted_version'] as String?,
      acceptedAt: json['accepted_at'] == null
          ? null
          : DateTime.tryParse(json['accepted_at'].toString()),
    );
  }
}

class LegalConsentStatus {
  const LegalConsentStatus({
    required this.businessName,
    required this.businessCode,
    required this.legalPageUrl,
    required this.legalSatisfied,
    required this.biometricSatisfied,
    required this.terms,
    required this.privacy,
    required this.biometric,
    this.isDemo = false,
  });

  final String businessName;
  final String businessCode;
  final String legalPageUrl;
  final bool legalSatisfied;
  final bool biometricSatisfied;
  final bool isDemo;
  final ConsentTypeStatus terms;
  final ConsentTypeStatus privacy;
  final ConsentTypeStatus biometric;

  factory LegalConsentStatus.fromJson(Map<String, dynamic> json) {
    return LegalConsentStatus(
      businessName: json['business_name'] as String? ?? '',
      businessCode: json['business_code'] as String? ?? '',
      legalPageUrl: json['legal_page_url'] as String? ?? '',
      legalSatisfied: json['legal_satisfied'] == true,
      biometricSatisfied: json['biometric_satisfied'] == true,
      isDemo: json['is_demo'] == true,
      terms: ConsentTypeStatus.fromJson(
        json['terms'] as Map<String, dynamic>? ?? const {},
      ),
      privacy: ConsentTypeStatus.fromJson(
        json['privacy'] as Map<String, dynamic>? ?? const {},
      ),
      biometric: ConsentTypeStatus.fromJson(
        json['biometric'] as Map<String, dynamic>? ?? const {},
      ),
    );
  }
}
