import 'package:aroll_mobile/domain/entities/user_session.dart';
import 'package:flutter/foundation.dart';

class AppState extends ChangeNotifier {
  bool isLoggedIn = false;
  bool mustChangePassword = false;
  UserSession? session;

  void setSession(UserSession s, {required bool mustChange}) {
    session = s;
    isLoggedIn = true;
    mustChangePassword = mustChange;
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
}
