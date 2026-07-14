import 'package:aroll_mobile/domain/entities/user_session.dart';
import 'package:flutter/foundation.dart';

class AppState extends ChangeNotifier {
  bool isLoggedIn = false;
  bool mustChangePassword = false;
  UserSession? session;
  String? employeeProfileImageUrl;

  void setSession(UserSession s, {required bool mustChange}) {
    session = s;
    isLoggedIn = true;
    mustChangePassword = mustChange;
    if (s.isEmployee) {
      employeeProfileImageUrl = s.profileImageUrl;
    }
    debugPrint(
      '[AppState] setSession must_change_password=$mustChangePassword '
      '(session.mustChangePassword=${s.mustChangePassword})',
    );
    notifyListeners();
  }

  void clearSession() {
    session = null;
    isLoggedIn = false;
    mustChangePassword = false;
    employeeProfileImageUrl = null;
    notifyListeners();
  }

  void passwordChanged() {
    mustChangePassword = false;
    if (session != null) {
      session = session!.copyWith(mustChangePassword: false);
    }
    debugPrint(
      '[AppState] passwordChanged must_change_password=$mustChangePassword '
      '(session.mustChangePassword=${session?.mustChangePassword})',
    );
    notifyListeners();
  }

  void updateSetupCompletedAt(DateTime? setupCompletedAt) {
    if (session == null) return;
    session = session!.copyWith(setupCompletedAt: setupCompletedAt);
    notifyListeners();
  }

  void updateEmployeeProfileImage(String? imageUrl) {
    employeeProfileImageUrl = imageUrl;
    final current = session;
    if (current != null && current.isEmployee) {
      session = UserSession(
        userId: current.userId,
        employeeId: current.employeeId,
        businessId: current.businessId,
        fullName: current.fullName,
        position: current.position,
        role: current.role,
        businessName: current.businessName,
        email: current.email,
        businessCode: current.businessCode,
        setupCompletedAt: current.setupCompletedAt,
        mustChangePassword: current.mustChangePassword,
        branding: current.branding,
        profileImageUrl: imageUrl,
      );
    }
    notifyListeners();
  }

  void updateOwnerProfileImage(String? imageUrl) {
    if (session == null) return;
    final branding = session!.branding;
    session = session!.copyWith(
      branding: BusinessBrandingSettings(
        logoUrl: branding?.logoUrl,
        ownerProfileImageUrl: imageUrl,
        displayImageUrl: branding?.displayImageUrl,
        theme: branding?.theme ??
            const BusinessThemeSettings(
              primaryColor: '#1E3A5F',
              secondaryColor: '#284B73',
              sidebarColor: '#1E3A5F',
              accentColor: '#3B82F6',
              buttonColor: '#1E3A5F',
              cardStyle: 'soft',
              fontSize: 'comfortable',
              colorMode: 'light',
              layoutDensity: 'rounded',
            ),
      ),
    );
    notifyListeners();
  }

  String? resolveEmployeeAvatarUrl(String? fallback) =>
      employeeProfileImageUrl ?? fallback;
}
