import 'package:aroll_mobile/core/app_state.dart';
import 'package:aroll_mobile/core/di/injection.dart';
import 'package:aroll_mobile/core/router/app_router.dart';
import 'package:aroll_mobile/domain/entities/face_liveness.dart';
import 'package:aroll_mobile/domain/entities/user_session.dart';
import 'package:aroll_mobile/domain/repositories/auth_repository.dart';
import 'package:aroll_mobile/domain/repositories/employee_repository.dart';
import 'package:aroll_mobile/domain/usecase/auth/logout_usecase.dart';
import 'package:aroll_mobile/presentation/employee/face_registration_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

void main() {
  setUp(() async {
    await sl.reset();
  });

  tearDown(() async {
    await sl.reset();
  });

  test('enrollment upload blocks close, and a local capture can be cancelled', () {
    expect(
      faceRegistrationDismiss(canPop: false, enrolling: true),
      FaceRegistrationDismiss.blocked,
    );
    expect(
      faceRegistrationDismiss(canPop: true, enrolling: true),
      FaceRegistrationDismiss.blocked,
    );
    expect(
      faceRegistrationDismiss(canPop: false, enrolling: false),
      FaceRegistrationDismiss.signOut,
    );
    expect(
      faceRegistrationDismiss(canPop: true, enrolling: false),
      FaceRegistrationDismiss.pop,
    );
    expect(
      faceRegistrationBurstShouldStop(
        closing: true,
        elapsed: false,
        frameLimitReached: false,
      ),
      isTrue,
    );
    expect(
      faceRegistrationBurstShouldStop(
        closing: false,
        elapsed: false,
        frameLimitReached: false,
      ),
      isFalse,
    );
  });

  testWidgets('X signs out to login when face registration cannot pop', (
    tester,
  ) async {
    final auth = _AuthRepository();
    final appState = _enrolledEmployeeState(enrolled: false);
    sl.registerSingleton<AppState>(appState);
    sl.registerSingleton<EmployeeRepository>(_FaceRepository());
    sl.registerSingleton<LogoutUsecase>(LogoutUsecase(auth));

    final router = createAppRouter(appState);
    addTearDown(router.dispose);

    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    expect(router.routeInformationProvider.value.uri.path, '/face-registration');
    expect(find.text('Set up your face'), findsOneWidget);
    final close = find.widgetWithIcon(IconButton, Icons.close_rounded);
    expect(tester.widget<IconButton>(close).onPressed, isNotNull);

    router.go('/home');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(router.routeInformationProvider.value.uri.path, '/face-registration');
    expect(find.text('Set up your face'), findsOneWidget);

    await tester.tap(close);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Sign Out'), findsWidgets);

    await tester.tap(find.widgetWithText(FilledButton, 'Sign Out'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    expect(auth.logouts, 1);
    expect(appState.isLoggedIn, isFalse);
    expect(router.routeInformationProvider.value.uri.path, '/login');

    appState.setSession(_employee(), mustChange: false);
    appState.setFaceEnrolled(false);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(router.routeInformationProvider.value.uri.path, '/face-registration');

    router.go('/home');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(router.routeInformationProvider.value.uri.path, '/face-registration');
    expect(appState.faceEnrolled, isFalse);
  });

  testWidgets('X pops when face registration was opened on top of another route', (
    tester,
  ) async {
    final auth = _AuthRepository();
    final appState = _enrolledEmployeeState(enrolled: false);
    sl.registerSingleton<AppState>(appState);
    sl.registerSingleton<EmployeeRepository>(_FaceRepository());
    sl.registerSingleton<LogoutUsecase>(LogoutUsecase(auth));

    final router = GoRouter(
      initialLocation: '/previous',
      routes: [
        GoRoute(
          path: '/previous',
          builder: (context, state) => Scaffold(
            body: TextButton(
              onPressed: () => context.push('/face-registration'),
              child: const Text('Open face setup'),
            ),
          ),
        ),
        GoRoute(
          path: '/face-registration',
          builder: (context, state) => const FaceRegistrationScreen(),
        ),
        GoRoute(
          path: '/login',
          builder: (context, state) => const Text('Login'),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Open face setup'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    expect(find.text('Set up your face'), findsOneWidget);
    await tester.tap(find.widgetWithIcon(IconButton, Icons.close_rounded));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('Sign Out'), findsNothing);
    expect(auth.logouts, 0);
    expect(appState.isLoggedIn, isTrue);
    expect(find.text('Open face setup'), findsOneWidget);
    expect(router.routeInformationProvider.value.uri.path, '/previous');
  });
}

UserSession _employee() {
  return const UserSession(
    userId: 'u1',
    employeeId: 'e1',
    businessId: 'b1',
    fullName: 'Casey',
    position: 'Staff',
    role: 'employee',
    businessName: 'Cafe',
    consentsCompleted: true,
    permissionsOnboardingCompleted: true,
  );
}

AppState _enrolledEmployeeState({required bool enrolled}) {
  final state = AppState()..setSession(_employee(), mustChange: false);
  state.setFaceEnrolled(enrolled);
  return state;
}

class _AuthRepository extends Fake implements AuthRepository {
  int logouts = 0;

  @override
  Future<void> logout() async {
    logouts += 1;
  }
}

class _FaceRepository extends Fake implements EmployeeRepository {
  @override
  Future<FaceStatus> getFaceStatus() async {
    return const FaceStatus(
      employeeId: 'e1',
      faceRegistrationStatus: 'not_registered',
      sampleCount: 0,
      modelVersion: null,
      faceRegisteredAt: null,
      threshold: 0.5,
    );
  }
}
