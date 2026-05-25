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
    notifyListeners();
  }
}
