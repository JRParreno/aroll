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
    this.mustChangePassword = false,
    this.branding,
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
  final bool mustChangePassword;
  final BusinessBrandingSettings? branding;

  bool get isOwner => role == 'owner' || role == 'manager';
  bool get isEmployee => role == 'employee';

  UserSession copyWith({
    bool? mustChangePassword,
    DateTime? setupCompletedAt,
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
      mustChangePassword: mustChangePassword ?? this.mustChangePassword,
      branding: branding,
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
        mustChangePassword,
        branding,
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
