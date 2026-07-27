import 'package:flutter/material.dart';
import 'package:aroll_mobile/domain/entities/user_session.dart';

class BusinessTheme {
  static Color fromHex(String hex) {
    final normalized = hex.replaceAll('#', '');
    return Color(int.parse('FF$normalized', radix: 16));
  }

  static Color primary(UserSession session) {
    final hex = session.branding?.theme.primaryColor ?? '1E466E';
    return fromHex(hex);
  }

  static Color secondary(UserSession session) {
    final hex = session.branding?.theme.secondaryColor ?? 'E7EEF5';
    return fromHex(hex);
  }

  static Color sidebar(UserSession session) {
    final hex = session.branding?.theme.sidebarColor ?? '1E466E';
    return fromHex(hex);
  }

  static Color button(UserSession session) {
    final hex = session.branding?.theme.buttonColor ?? '1E466E';
    return fromHex(hex);
  }

  static Color accent(UserSession session) {
    final hex = session.branding?.theme.accentColor ?? '3B82F6';
    return fromHex(hex);
  }
}