import 'package:equatable/equatable.dart';

class LegalConsentStatus extends Equatable {
  const LegalConsentStatus({
    required this.accepted,
    required this.businessName,
    required this.businessCode,
    required this.legalConsentUrl,
    required this.content,
    this.acceptedAt,
    this.legalConsentPageUrl,
    this.isDemo = false,
  });

  final bool accepted;
  final DateTime? acceptedAt;
  final String businessName;
  final String businessCode;
  final String legalConsentUrl;
  final String? legalConsentPageUrl;
  final String content;
  final bool isDemo;

  @override
  List<Object?> get props => [
        accepted,
        acceptedAt,
        businessName,
        businessCode,
        legalConsentUrl,
        legalConsentPageUrl,
        content,
        isDemo,
      ];
}
