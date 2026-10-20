import 'package:aroll_mobile/core/di/injection.dart';
import 'package:aroll_mobile/core/error/failures.dart';
import 'package:aroll_mobile/domain/repositories/auth_repository.dart';
import 'package:aroll_mobile/presentation/auth/owner_forgot_password_screen.dart';
import 'package:aroll_mobile/presentation/auth/owner_login_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    await sl.reset();
  });

  tearDown(() async {
    await sl.reset();
  });

  testWidgets('owner login shows forgot password', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: OwnerLoginScreen()));
    expect(find.text('Forgot password?'), findsOneWidget);
    expect(find.text('Sign In'), findsOneWidget);
  });

  testWidgets('owner can request, verify, and set a new password', (tester) async {
    final repo = _FakeAuthRepository();
    sl.registerSingleton<AuthRepository>(repo);
    final router = GoRouter(
      initialLocation: '/forgot',
      routes: [
        GoRoute(
          path: '/forgot',
          builder: (_, __) => const OwnerForgotPasswordScreen(),
        ),
        GoRoute(
          path: '/login/owner',
          builder: (_, __) => const Scaffold(body: Text('Owner login')),
        ),
      ],
    );
    addTearDown(router.dispose);

    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pump();

    await tester.enterText(find.byType(TextField).at(0), 'Owner@Example.com');
    await tester.enterText(find.byType(TextField).at(1), 'lc-test');
    await tester.tap(find.text('Send verification code'));
    await tester.pump();

    expect(repo.requests, 1);
    expect(repo.lastEmail, 'Owner@Example.com');
    expect(repo.lastBusinessCode, 'lc-test');
    expect(find.text('Enter verification code'), findsOneWidget);

    await tester.enterText(
      find.byWidgetPredicate(
        (widget) =>
            widget is TextField &&
            widget.decoration?.hintText == '6-digit code',
      ),
      '123456',
    );
    await tester.pump();
    await tester.ensureVisible(find.text('Verify'));
    await tester.tap(find.text('Verify'));
    await tester.pump();
    expect(repo.lastCode, '123456');
    expect(find.text('Create a new password'), findsOneWidget);

    await tester.enterText(find.byType(TextField).at(0), 'NewOwner123!');
    await tester.enterText(find.byType(TextField).at(1), 'NewOwner123!');
    await tester.tap(find.text('Save new password'));
    await tester.pump();
    expect(repo.lastPassword, 'NewOwner123!');
    expect(find.text('Password updated'), findsOneWidget);

    await tester.tap(find.text('Back to sign in'));
    await tester.pumpAndSettle();
    expect(find.text('Owner login'), findsOneWidget);
  });

  testWidgets('delivery failure does not advance or claim success', (tester) async {
    final repo = _FakeAuthRepository()..failRequest = true;
    sl.registerSingleton<AuthRepository>(repo);
    await tester.pumpWidget(
      const MaterialApp(home: OwnerForgotPasswordScreen()),
    );
    await tester.pump();
    await tester.enterText(find.byType(TextField).at(0), 'owner@example.com');
    await tester.enterText(find.byType(TextField).at(1), 'LC-1');
    await tester.tap(find.text('Send verification code'));
    await tester.pump();

    expect(
      find.text('Email delivery is unavailable right now. Please try again later.'),
      findsOneWidget,
    );
    expect(find.text('Enter verification code'), findsNothing);
    expect(find.text('Password updated'), findsNothing);
  });
}

class _FakeAuthRepository extends Fake implements AuthRepository {
  int requests = 0;
  bool failRequest = false;
  String? lastEmail;
  String? lastBusinessCode;
  String? lastCode;
  String? lastPassword;

  @override
  Future<AuthResult<PasswordResetTicket>> requestOwnerResetCode({
    required String email,
    required String businessCode,
  }) async {
    requests += 1;
    lastEmail = email;
    lastBusinessCode = businessCode;
    if (failRequest) {
      return (
        data: null,
        failure: const AuthFailure(
          'Email delivery is unavailable right now. Please try again later.',
        ),
      );
    }
    return (
      data: const PasswordResetTicket(
        accepted: true,
        message:
            'If the email and business code match an owner account, a verification code has been sent.',
        retryAfterSeconds: 0,
        resendAvailableAt: null,
      ),
      failure: null,
    );
  }

  @override
  Future<AuthResult<String>> verifyOwnerResetCode({
    required String email,
    required String businessCode,
    required String code,
  }) async {
    lastCode = code;
    return (data: 'reset-token-value', failure: null);
  }

  @override
  Future<Failure?> completeOwnerPasswordReset({
    required String resetToken,
    required String newPassword,
  }) async {
    lastPassword = newPassword;
    return null;
  }
}
