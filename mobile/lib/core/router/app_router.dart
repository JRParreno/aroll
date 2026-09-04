import 'package:aroll_mobile/domain/entities/employee_portal.dart';
import 'package:aroll_mobile/core/app_state.dart';
import 'package:aroll_mobile/core/router/app_nav_observer.dart';
import 'package:aroll_mobile/presentation/auth/change_password_screen.dart';
import 'package:aroll_mobile/presentation/auth/employee_login_screen.dart';
import 'package:aroll_mobile/presentation/auth/owner_login_screen.dart';
import 'package:aroll_mobile/presentation/auth/role_landing_screen.dart';
import 'package:aroll_mobile/presentation/employee/attendance_correction_screen.dart';
import 'package:aroll_mobile/presentation/employee/employee_notifications_screen.dart';
import 'package:aroll_mobile/presentation/employee/face_registration_screen.dart';
import 'package:aroll_mobile/presentation/employee/leave_request_detail_screen.dart';
import 'package:aroll_mobile/presentation/employee/leave_requests_screen.dart';
import 'package:aroll_mobile/presentation/employee/payroll_history_screen.dart';
import 'package:aroll_mobile/presentation/employee/payroll_screen.dart';
import 'package:aroll_mobile/presentation/employee/payslip_screen.dart';
import 'package:aroll_mobile/presentation/employee/profile_screen.dart';
import 'package:aroll_mobile/presentation/employee/request_leave_screen.dart';
import 'package:aroll_mobile/presentation/employee/schedule_screen.dart';
import 'package:aroll_mobile/presentation/employee/shift_detail_screen.dart';
import 'package:aroll_mobile/presentation/employee/shift_history_screen.dart';
import 'package:aroll_mobile/presentation/home/home_screen.dart';
import 'package:aroll_mobile/presentation/home/scan_attendance_screen.dart';
import 'package:aroll_mobile/presentation/owner/owner_attendance_screen.dart';
import 'package:aroll_mobile/presentation/owner/owner_employees_screen.dart';
import 'package:aroll_mobile/presentation/owner/owner_dashboard_screen.dart';
import 'package:aroll_mobile/presentation/owner/owner_leave_management_screen.dart';
import 'package:aroll_mobile/presentation/owner/owner_location_screen.dart';
import 'package:aroll_mobile/presentation/owner/owner_notifications_screen.dart';
import 'package:aroll_mobile/presentation/owner/owner_account_information_screen.dart';
import 'package:aroll_mobile/presentation/owner/owner_business_information_screen.dart';
import 'package:aroll_mobile/presentation/owner/owner_business_setup_summary_screen.dart';
import 'package:aroll_mobile/presentation/owner/owner_profile_screen.dart';
import 'package:aroll_mobile/presentation/owner/owner_leave_policy_screen.dart';
import 'package:aroll_mobile/presentation/owner/owner_settings_screen.dart';
import 'package:aroll_mobile/presentation/owner/owner_setup_screen.dart';
import 'package:aroll_mobile/presentation/owner/owner_registration.dart';
import 'package:aroll_mobile/presentation/owner/owner_set_schedule_screen.dart';
import 'package:aroll_mobile/presentation/owner/payroll/owner_payroll_detail_screen.dart';
import 'package:aroll_mobile/presentation/owner/payroll/owner_payroll_list_screen.dart';
import 'package:aroll_mobile/presentation/owner/setup/owner_setup_wizard_screen.dart';
import 'package:aroll_mobile/presentation/owner/setup/setup_wizard_constants.dart';
import 'package:aroll_mobile/presentation/shared/app_ui.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

CustomTransitionPage<void> _fadePage(GoRouterState state, Widget child) {
  return appFadeSlidePage(key: state.pageKey, child: child);
}

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
  if (session.isDemo) {
    return '/home';
  }
  if (appState.faceEnrolled != true) {
    return '/face-registration';
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
        redirect = resolveAuthenticatedRoute(appState);
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
        redirect = resolveAuthenticatedRoute(appState);
      } else if (session?.isEmployee == true &&
          session?.isDemo != true &&
          !appState.mustChangePassword &&
          appState.faceEnrolled != true &&
          loc != '/face-registration' &&
          loc != '/change-password') {
        // Force face enrollment on every session until completed — including
        // after app close/reopen (restore sets faceEnrolled from server).
        redirect = '/face-registration';
      } else if (session?.isEmployee == true &&
          session?.isDemo == true &&
          loc == '/face-registration') {
        redirect = '/home';
      } else if (session?.isEmployee == true &&
          appState.faceEnrolled == true &&
          loc == '/face-registration') {
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
      GoRoute(
        path: '/login',
        pageBuilder: (context, state) =>
            _fadePage(state, const RoleLandingScreen()),
      ),
      GoRoute(
        path: '/login/employee',
        pageBuilder: (context, state) =>
            _fadePage(state, const EmployeeLoginScreen()),
      ),
      GoRoute(
        path: '/login/owner-options',
        pageBuilder: (context, state) =>
            _fadePage(state, const OwnerOptionsScreen()),
      ),
      GoRoute(
        path: '/login/owner',
        pageBuilder: (context, state) =>
            _fadePage(state, const OwnerLoginScreen()),
      ),
      GoRoute(
        path: '/register-business',
        pageBuilder: (context, state) =>
            _fadePage(state, const OwnerRegistrationScreen()),
      ),
      GoRoute(
        path: '/track-registration',
        pageBuilder: (context, state) => _fadePage(
          state,
          TrackRegistrationScreen(
            initialEmail: state.uri.queryParameters['email'],
          ),
        ),
      ),
      GoRoute(
        path: '/change-password',
        pageBuilder: (context, state) =>
            _fadePage(state, const ChangePasswordScreen()),
      ),
      GoRoute(
        path: '/home',
        pageBuilder: (context, state) {
          final session = appState.session;
          if (session == null) {
            return _fadePage(
              state,
              const Scaffold(body: Center(child: Text('No session'))),
            );
          }
          return _fadePage(state, HomeScreen(session: session));
        },
      ),
      GoRoute(
        path: '/notifications',
        pageBuilder: (context, state) =>
            _fadePage(state, const EmployeeNotificationsScreen()),
      ),
      GoRoute(
        path: '/face-registration',
        pageBuilder: (context, state) =>
            _fadePage(state, const FaceRegistrationScreen()),
      ),
      GoRoute(
        path: '/schedule',
        pageBuilder: (context, state) =>
            _fadePage(state, const EmployeeScheduleScreen()),
        routes: [
          GoRoute(
            path: 'detail',
            pageBuilder: (context, state) {
              final item = state.extra;
              if (item is! EmployeeScheduleItem) {
                return _fadePage(state, const EmployeeScheduleScreen());
              }
              return _fadePage(state, ShiftDetailScreen(item: item));
            },
          ),
        ],
      ),
      GoRoute(
        path: '/profile',
        pageBuilder: (context, state) =>
            _fadePage(state, const EmployeeProfileScreen()),
      ),
      GoRoute(
        path: '/shift-history',
        pageBuilder: (context, state) {
          final focusAttendanceRecordId =
              state.uri.queryParameters['attendance_record_id'];
          final focusAssignmentId =
              state.uri.queryParameters['shift_assignment_id'];
          return _fadePage(
            state,
            ShiftHistoryScreen(
              focusAttendanceRecordId: focusAttendanceRecordId,
              focusAssignmentId: focusAssignmentId,
            ),
          );
        },
        routes: [
          GoRoute(
            path: 'correction',
            pageBuilder: (context, state) {
              final item = state.extra;
              if (item is! EmployeeShiftHistoryItem) {
                return _fadePage(state, const ShiftHistoryScreen());
              }
              return _fadePage(
                state,
                AttendanceCorrectionScreen(item: item),
              );
            },
          ),
        ],
      ),
      GoRoute(
        path: '/payroll',
        pageBuilder: (context, state) =>
            _fadePage(state, const EmployeePayrollScreen()),
        routes: [
          GoRoute(
            path: 'history',
            pageBuilder: (context, state) =>
                _fadePage(state, const EmployeePayrollHistoryScreen()),
          ),
        ],
      ),
      GoRoute(
        path: '/leave-requests',
        pageBuilder: (context, state) =>
            _fadePage(state, const LeaveRequestsScreen()),
        routes: [
          GoRoute(
            path: 'new',
            pageBuilder: (context, state) =>
                _fadePage(state, const RequestLeaveScreen()),
          ),
          GoRoute(
            path: ':requestId/edit',
            pageBuilder: (context, state) => _fadePage(
              state,
              RequestLeaveScreen(
                requestId: state.pathParameters['requestId'],
              ),
            ),
          ),
          GoRoute(
            path: ':requestId',
            pageBuilder: (context, state) => _fadePage(
              state,
              LeaveRequestDetailScreen(
                requestId: state.pathParameters['requestId'] ?? '',
              ),
            ),
          ),
        ],
      ),
      GoRoute(
        path: '/payslip',
        pageBuilder: (context, state) {
          final asOfRaw = state.uri.queryParameters['as_of'];
          final asOf = asOfRaw == null ? null : DateTime.tryParse(asOfRaw);
          return _fadePage(state, EmployeePayslipScreen(asOf: asOf));
        },
      ),
      GoRoute(
        path: '/scan-attendance',
        pageBuilder: (context, state) {
          final assignmentId =
              state.uri.queryParameters['shift_assignment_id'];
          return _fadePage(
            state,
            ScanAttendanceScreen(shiftAssignmentId: assignmentId),
          );
        },
      ),
      GoRoute(
        path: '/owner/home',
        pageBuilder: (context, state) => _fadePage(
          state,
          OwnerDashboardScreen(session: appState.session!),
        ),
      ),
      GoRoute(
        path: '/owner/attendance',
        pageBuilder: (context, state) =>
            _fadePage(state, const OwnerAttendanceScreen()),
      ),
      GoRoute(
        path: '/owner/employees',
        pageBuilder: (context, state) =>
            _fadePage(state, const OwnerEmployeesScreen()),
      ),
      GoRoute(
        path: '/owner/schedule',
        pageBuilder: (context, state) =>
            _fadePage(state, const OwnerScheduleScreen()),
      ),
      GoRoute(
        path: '/owner/leave',
        pageBuilder: (context, state) =>
            _fadePage(state, const OwnerLeaveManagementScreen()),
        routes: [
          GoRoute(
            path: ':requestId',
            pageBuilder: (context, state) => _fadePage(
              state,
              OwnerLeaveDetailScreen(
                requestId: state.pathParameters['requestId'] ?? '',
              ),
            ),
          ),
        ],
      ),
      GoRoute(
        path: '/owner/notifications',
        pageBuilder: (context, state) =>
            _fadePage(state, const OwnerNotificationsScreen()),
      ),
      GoRoute(
        path: '/owner/payroll',
        pageBuilder: (context, state) =>
            _fadePage(state, const OwnerPayrollListScreen()),
        routes: [
          GoRoute(
            path: ':employeeId',
            pageBuilder: (context, state) {
              final asOfRaw = state.uri.queryParameters['as_of'];
              final asOf =
                  asOfRaw == null ? null : DateTime.tryParse(asOfRaw);
              return _fadePage(
                state,
                OwnerPayrollDetailScreen(
                  employeeId: state.pathParameters['employeeId']!,
                  asOf: asOf,
                ),
              );
            },
          ),
        ],
      ),
      GoRoute(
        path: '/owner/profile',
        pageBuilder: (context, state) => _fadePage(
          state,
          OwnerProfileScreen(session: appState.session!),
        ),
      ),
      GoRoute(
        path: '/owner/location',
        pageBuilder: (context, state) =>
            _fadePage(state, const OwnerLocationScreen()),
      ),
      GoRoute(
        path: '/owner/settings',
        pageBuilder: (context, state) =>
            _fadePage(state, const OwnerSettingsScreen()),
        routes: [
          GoRoute(
            path: 'account',
            pageBuilder: (context, state) =>
                _fadePage(state, const OwnerAccountInformationScreen()),
          ),
          GoRoute(
            path: 'business',
            pageBuilder: (context, state) =>
                _fadePage(state, const OwnerBusinessInformationScreen()),
          ),
          GoRoute(
            path: 'setup-summary',
            pageBuilder: (context, state) =>
                _fadePage(state, const OwnerBusinessSetupSummaryScreen()),
          ),
          GoRoute(
            path: 'leave-policy',
            pageBuilder: (context, state) =>
                _fadePage(state, const OwnerLeavePolicyScreen()),
          ),
        ],
      ),
      GoRoute(
        path: '/owner/setup-wizard',
        pageBuilder: (context, state) {
          final stepParam = state.uri.queryParameters['step'];
          return _fadePage(
            state,
            OwnerSetupWizardScreen(
              initialStep: parseSetupWizardInitialStep(stepParam),
            ),
          );
        },
      ),
      GoRoute(
        path: '/owner/setup',
        pageBuilder: (context, state) =>
            _fadePage(state, const OwnerSetupScreen()),
      ),
    ],
  );
}
