import 'package:aroll_mobile/core/app_state.dart';
import 'package:aroll_mobile/core/router/app_nav_observer.dart';
import 'package:aroll_mobile/presentation/auth/change_password_screen.dart';
import 'package:aroll_mobile/presentation/auth/employee_login_screen.dart';
import 'package:aroll_mobile/presentation/auth/owner_login_screen.dart';
import 'package:aroll_mobile/presentation/auth/role_landing_screen.dart';
import 'package:aroll_mobile/presentation/employee/face_registration_screen.dart';
import 'package:aroll_mobile/presentation/employee/payroll_screen.dart';
import 'package:aroll_mobile/presentation/employee/payslip_screen.dart';
import 'package:aroll_mobile/presentation/employee/profile_screen.dart';
import 'package:aroll_mobile/presentation/employee/schedule_screen.dart';
import 'package:aroll_mobile/presentation/employee/shift_history_screen.dart';
import 'package:aroll_mobile/presentation/home/home_screen.dart';
import 'package:aroll_mobile/presentation/home/scan_attendance_screen.dart';
import 'package:aroll_mobile/presentation/owner/owner_attendance_screen.dart';
import 'package:aroll_mobile/presentation/owner/owner_employees_screen.dart';
import 'package:aroll_mobile/presentation/owner/owner_dashboard_screen.dart';
import 'package:aroll_mobile/presentation/owner/owner_location_screen.dart';
import 'package:aroll_mobile/presentation/owner/owner_productivity_screen.dart';
import 'package:aroll_mobile/presentation/owner/owner_profile_screen.dart';
import 'package:aroll_mobile/presentation/owner/owner_settings_screen.dart';
import 'package:aroll_mobile/presentation/owner/owner_setup_screen.dart';
import 'package:aroll_mobile/presentation/owner/owner_registration.dart';
import 'package:aroll_mobile/presentation/owner/owner_set_schedule_screen.dart';
import 'package:aroll_mobile/presentation/owner/payroll/owner_payroll_detail_screen.dart';
import 'package:aroll_mobile/presentation/owner/payroll/owner_payroll_list_screen.dart';
import 'package:aroll_mobile/presentation/owner/setup/owner_setup_wizard_screen.dart';
import 'package:aroll_mobile/presentation/owner/setup/setup_wizard_constants.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

bool _isPublicRoute(String loc) {
  return loc == '/login' ||
      loc.startsWith('/login/') ||
      loc == '/register-business' ||
      loc == '/track-registration';
}

/// Resolves the landing route after auth (login, restore, or password change).
String resolveAuthenticatedRoute(AppState appState) {
  if (!appState.isLoggedIn || appState.session == null) {
    return '/login';
  }
  final session = appState.session!;
  if (appState.mustChangePassword) {
    return '/change-password';
  }
  if (session.isOwner) {
    return session.setupCompletedAt == null
        ? '/owner/setup-wizard'
        : '/owner/home';
  }
  return '/home';
}

GoRouter createAppRouter(AppState appState) {
  return GoRouter(
    initialLocation: resolveAuthenticatedRoute(appState),
    debugLogDiagnostics: kDebugMode,
    refreshListenable: appState,
    observers: [AppNavObserver()],
    redirect: (context, state) {
      final loc = state.matchedLocation;
      final session = appState.session;
      String? redirect;

      if (!appState.isLoggedIn) {
        redirect = _isPublicRoute(loc) ? null : '/login';
      } else if (appState.mustChangePassword && loc != '/change-password') {
        redirect = '/change-password';
      } else if (!appState.mustChangePassword && loc == '/change-password') {
        redirect = session?.isOwner == true
            ? '/owner/home'
            : '/face-registration';
      } else if (loc == '/login' ||
          loc.startsWith('/login/') ||
          loc == '/register-business' ||
          loc == '/track-registration') {
        redirect = resolveAuthenticatedRoute(appState);
      } else if (session?.isOwner == true &&
          !loc.startsWith('/owner/') &&
          loc != '/change-password') {
        redirect = session?.setupCompletedAt == null
            ? '/owner/setup-wizard'
            : '/owner/home';
      } else if (session?.isEmployee == true && loc.startsWith('/owner/')) {
        redirect = '/home';
      }

      debugPrint(
        '[router] uri=${state.uri} loc=$loc isLoggedIn=${appState.isLoggedIn} '
        'role=${session?.role} '
        '-> ${redirect ?? 'allow'}',
      );
      return redirect;
    },
    routes: [
      GoRoute(path: '/login', builder: (_, __) => const RoleLandingScreen()),
      GoRoute(
        path: '/login/employee',
        builder: (_, __) => const EmployeeLoginScreen(),
      ),
      GoRoute(
        path: '/login/owner-options',
        builder: (_, __) => const OwnerOptionsScreen(),
      ),
      GoRoute(
        path: '/login/owner',
        builder: (_, __) => const OwnerLoginScreen(),
      ),
      GoRoute(
        path: '/register-business',
        builder: (_, __) => const OwnerRegistrationScreen(),
      ),
      GoRoute(
        path: '/track-registration',
        builder: (_, state) => TrackRegistrationScreen(
          initialEmail: state.uri.queryParameters['email'],
        ),
      ),
      GoRoute(
        path: '/change-password',
        builder: (_, __) => const ChangePasswordScreen(),
      ),
      GoRoute(
        path: '/home',
        builder: (context, state) {
          final session = appState.session;
          if (session == null) {
            return const Scaffold(body: Center(child: Text('No session')));
          }
          return HomeScreen(session: session);
        },
      ),
      GoRoute(
        path: '/face-registration',
        builder: (_, __) => const FaceRegistrationScreen(),
      ),
      GoRoute(
        path: '/schedule',
        builder: (_, __) => const EmployeeScheduleScreen(),
      ),
      GoRoute(
        path: '/profile',
        builder: (_, __) => const EmployeeProfileScreen(),
      ),
      GoRoute(
        path: '/shift-history',
        builder: (_, __) => const ShiftHistoryScreen(),
      ),
      GoRoute(
        path: '/payroll',
        builder: (_, __) => const EmployeePayrollScreen(),
      ),
      GoRoute(
        path: '/payslip',
        builder: (_, __) => const EmployeePayslipScreen(),
      ),
      GoRoute(
        path: '/scan-attendance',
        builder: (_, __) => const ScanAttendanceScreen(),
      ),
      GoRoute(
        path: '/owner/home',
        builder: (_, __) => OwnerDashboardScreen(session: appState.session!),
      ),
      GoRoute(
        path: '/owner/attendance',
        builder: (_, __) => const OwnerAttendanceScreen(),
      ),
      GoRoute(
        path: '/owner/employees',
        builder: (_, __) => const OwnerEmployeesScreen(),
      ),
      GoRoute(
        path: '/owner/schedule',
        builder: (_, __) => const OwnerScheduleScreen(),
      ),
      GoRoute(
        path: '/owner/payroll',
        builder: (_, __) => const OwnerPayrollListScreen(),
        routes: [
          GoRoute(
            path: ':employeeId',
            builder: (_, state) => OwnerPayrollDetailScreen(
              employeeId: state.pathParameters['employeeId']!,
            ),
          ),
        ],
      ),
      GoRoute(
        path: '/owner/profile',
        builder: (_, __) => OwnerProfileScreen(session: appState.session!),
      ),
      GoRoute(
        path: '/owner/productivity',
        builder: (_, __) => const OwnerProductivityScreen(),
      ),
      GoRoute(
        path: '/owner/location',
        builder: (_, __) => const OwnerLocationScreen(),
      ),
      GoRoute(
        path: '/owner/settings',
        builder: (_, __) => const OwnerSettingsScreen(),
      ),
      GoRoute(
        path: '/owner/setup-wizard',
        builder: (_, state) {
          final stepParam = state.uri.queryParameters['step'];
          final parsed = int.tryParse(stepParam ?? '0') ?? 0;
          return OwnerSetupWizardScreen(initialStep: clampSetupStep(parsed));
        },
      ),
      GoRoute(
        path: '/owner/setup',
        builder: (_, __) => const OwnerSetupScreen(),
      ),
    ],
  );
}
