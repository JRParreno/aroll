import 'package:aroll_mobile/core/app_state.dart';
import 'package:aroll_mobile/presentation/auth/change_password_screen.dart';
import 'package:aroll_mobile/presentation/auth/login_screen.dart';
import 'package:aroll_mobile/presentation/home/home_screen.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

GoRouter createAppRouter(AppState appState) {
  return GoRouter(
    initialLocation: '/login',
    refreshListenable: appState,
    redirect: (context, state) {
      final loc = state.matchedLocation;
      if (!appState.isLoggedIn) {
        return loc == '/login' ? null : '/login';
      }
      if (appState.mustChangePassword && loc != '/change-password') {
        return '/change-password';
      }
      if (!appState.mustChangePassword && loc == '/change-password') {
        return '/home';
      }
      if (appState.isLoggedIn && loc == '/login') {
        return appState.mustChangePassword ? '/change-password' : '/home';
      }
      return null;
    },
    routes: [
      GoRoute(path: '/login', builder: (_, __) => const LoginScreen()),
      GoRoute(
        path: '/change-password',
        builder: (_, __) => const ChangePasswordScreen(),
      ),
      GoRoute(
        path: '/home',
        builder: (_, __) {
          final session = appState.session;
          if (session == null) {
            return const Scaffold(body: Center(child: Text('No session')));
          }
          return HomeScreen(session: session);
        },
      ),
    ],
  );
}
