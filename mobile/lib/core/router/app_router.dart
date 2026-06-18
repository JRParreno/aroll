import 'package:aroll_mobile/core/app_state.dart';
import 'package:aroll_mobile/core/router/app_nav_observer.dart';
import 'package:aroll_mobile/presentation/auth/change_password_screen.dart';
import 'package:aroll_mobile/presentation/auth/login_screen.dart';
import 'package:aroll_mobile/presentation/home/home_screen.dart';
import 'package:aroll_mobile/presentation/home/scan_attendance_screen.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

GoRouter createAppRouter(AppState appState) {
  return GoRouter(
    initialLocation: '/login',
    debugLogDiagnostics: kDebugMode,
    refreshListenable: appState,
    observers: [AppNavObserver()],
    redirect: (context, state) {
      final loc = state.matchedLocation;
      final uri = state.uri.toString();
      String? redirect;

      if (!appState.isLoggedIn) {
        redirect = loc == '/login' ? null : '/login';
      } else if (appState.mustChangePassword && loc != '/change-password') {
        redirect = '/change-password';
      } else if (!appState.mustChangePassword && loc == '/change-password') {
        redirect = '/home';
      } else if (appState.isLoggedIn && loc == '/login') {
        redirect = appState.mustChangePassword ? '/change-password' : '/home';
      }

      debugPrint(
        '[router] uri=$uri loc=$loc isLoggedIn=${appState.isLoggedIn} '
        'must_change_password=${appState.mustChangePassword} '
        'session=${appState.session != null} '
        'sessionFlag=${appState.session?.mustChangePassword} '
        '-> ${redirect ?? 'allow'}',
      );
      return redirect;
    },
    routes: [
      GoRoute(
        path: '/login',
        builder: (context, state) {
          debugPrint('[route-build] /login');
          return const LoginScreen();
        },
      ),
      GoRoute(
        path: '/change-password',
        builder: (context, state) {
          debugPrint('[route-build] /change-password');
          return const ChangePasswordScreen();
        },
      ),
      GoRoute(
        path: '/home',
        builder: (context, state) {
          final session = appState.session;
          debugPrint(
            '[route-build] /home sessionNull=${session == null} '
            'name=${session?.fullName}',
          );
          if (session == null) {
            return const Scaffold(body: Center(child: Text('No session')));
          }
          return HomeScreen(session: session);
        },
      ),
      GoRoute(
        path: '/scan-attendance',
        builder: (_, __) => const ScanAttendanceScreen(),
      ),
    ],
  );
}
