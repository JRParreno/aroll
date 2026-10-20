import 'package:equatable/equatable.dart';

class UserSession extends Equatable {
  const UserSession({
    required this.userId,
    required this.employeeId,
    required this.businessId,
    required this.fullName,
    required this.position,
    required this.role,
    required this.businessName,
    this.email,
    this.businessCode,
    this.setupCompletedAt,
    this.needsBrandingOnboarding = false,
    this.mustChangePassword = false,
    this.branding,
    this.profileImageUrl,
    this.isDemo = false,
    this.isInternalTest = false,
    this.consentsCompleted,
    this.permissionsOnboardingCompleted,
    this.needsRecoveryEmail = false,
    this.timezone,
  });

  final String userId;
  final String? employeeId;
  final String? businessId;
  final String fullName;
  final String? position;
  final String role;
  final String businessName;
  final String? email;
  final String? businessCode;
  final DateTime? setupCompletedAt;
  final bool needsBrandingOnboarding;
  final bool mustChangePassword;
  final BusinessBrandingSettings? branding;
  final String? profileImageUrl;
  final bool isDemo;
  final bool isInternalTest;
  final bool? consentsCompleted;
  /// Server account-level permissions onboarding completion (not OS grants).
  final bool? permissionsOnboardingCompleted;
  final bool needsRecoveryEmail;
  final String? timezone;

  bool get isOwner => role == 'owner' || role == 'manager';
  bool get isEmployee => role == 'employee';

  UserSession copyWith({
    bool? mustChangePassword,
    DateTime? setupCompletedAt,
    bool? needsBrandingOnboarding,
    BusinessBrandingSettings? branding,
    String? profileImageUrl,
    bool? isDemo,
    bool? isInternalTest,
    bool? consentsCompleted,
    bool? permissionsOnboardingCompleted,
    bool? needsRecoveryEmail,
    String? timezone,
  }) {
    return UserSession(
      userId: userId,
      employeeId: employeeId,
      businessId: businessId,
      fullName: fullName,
      position: position,
      role: role,
      businessName: businessName,
      email: email,
      businessCode: businessCode,
      setupCompletedAt: setupCompletedAt ?? this.setupCompletedAt,
      needsBrandingOnboarding:
          needsBrandingOnboarding ?? this.needsBrandingOnboarding,
      mustChangePassword: mustChangePassword ?? this.mustChangePassword,
      branding: branding ?? this.branding,
      profileImageUrl: profileImageUrl ?? this.profileImageUrl,
      isDemo: isDemo ?? this.isDemo,
      isInternalTest: isInternalTest ?? this.isInternalTest,
      consentsCompleted: consentsCompleted ?? this.consentsCompleted,
      permissionsOnboardingCompleted: permissionsOnboardingCompleted ??
          this.permissionsOnboardingCompleted,
      needsRecoveryEmail: needsRecoveryEmail ?? this.needsRecoveryEmail,
      timezone: timezone ?? this.timezone,
    );
  }

  @override
  List<Object?> get props => [
        userId,
        employeeId,
        businessId,
        fullName,
        position,
        role,
        businessName,
        email,
        businessCode,
        setupCompletedAt,
        needsBrandingOnboarding,
        mustChangePassword,
        branding,
        profileImageUrl,
        isDemo,
        isInternalTest,
        consentsCompleted,
        permissionsOnboardingCompleted,
        needsRecoveryEmail,
        timezone,
      ];
}

class BusinessBrandingSettings extends Equatable {
  const BusinessBrandingSettings({
    this.logoUrl,
    this.ownerProfileImageUrl,
    this.displayImageUrl,
    required this.theme,
  });

  final String? logoUrl;
  final String? ownerProfileImageUrl;
  final String? displayImageUrl;
  final BusinessThemeSettings theme;

  @override
  List<Object?> get props => [
        logoUrl,
        ownerProfileImageUrl,
        displayImageUrl,
        theme,
      ];
}

class BusinessThemeSettings extends Equatable {
  const BusinessThemeSettings({
    required this.primaryColor,
    required this.secondaryColor,
    required this.sidebarColor,
    required this.accentColor,
    required this.buttonColor,
    required this.cardStyle,
    required this.fontSize,
    required this.colorMode,
    required this.layoutDensity,
  });

  final String primaryColor;
  final String secondaryColor;
  final String sidebarColor;
  final String accentColor;
  final String buttonColor;
  final String cardStyle;
  final String fontSize;
  final String colorMode;
  final String layoutDensity;

  @override
  List<Object?> get props => [
        primaryColor,
        secondaryColor,
        sidebarColor,
        accentColor,
        buttonColor,
        cardStyle,
        fontSize,
        colorMode,
        layoutDensity,
      ];
}
