import 'package:aroll_mobile/core/app_state.dart';
import 'package:aroll_mobile/core/di/injection.dart';
import 'package:aroll_mobile/core/router/app_router.dart';
import 'package:aroll_mobile/domain/entities/legal_consent.dart';
import 'package:aroll_mobile/domain/entities/user_session.dart';
import 'package:aroll_mobile/domain/repositories/employee_repository.dart';
import 'package:aroll_mobile/presentation/legal/employee_legal_consent_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  UserSession employee({
    bool demo = false,
    bool mustChange = false,
    bool? consentsCompleted,
  }) {
    return UserSession(
      userId: 'u1',
      employeeId: 'e1',
      businessId: 'b1',
      fullName: 'Casey',
      position: 'Staff',
      role: 'employee',
      businessName: 'Test Biz',
      businessCode: 'LC-TEST',
      mustChangePassword: mustChange,
      isDemo: demo,
      consentsCompleted: consentsCompleted,
    );
  }

  test('employee route order is password, consents, permissions, face', () {
    final appState = AppState()..setSession(employee(), mustChange: true);
    expect(resolveAuthenticatedRoute(appState), '/change-password');

    appState.passwordChanged();
    appState.setConsentStatus(
      legalSatisfied: false,
      biometricSatisfied: false,
      consentsCompleted: false,
    );
    expect(resolveAuthenticatedRoute(appState), '/consents');

    appState.setConsentStatus(
      legalSatisfied: true,
      biometricSatisfied: true,
      consentsCompleted: true,
    );
    appState.setPermissionsIntroSeen(false);
    expect(resolveAuthenticatedRoute(appState), '/permissions');

    appState.setPermissionsIntroSeen(true);
    appState.setFaceEnrolled(false);
    expect(resolveAuthenticatedRoute(appState), '/face-registration');

    appState.setFaceEnrolled(true);
    expect(resolveAuthenticatedRoute(appState), '/home');
  });

  test('demo employees skip consents, permissions, and face gates', () {
    final appState = AppState()..setSession(employee(demo: true), mustChange: false);
    expect(resolveAuthenticatedRoute(appState), '/home');
  });

  test('pendingRequiredConsents keeps required unaccepted docs by position', () {
    final pending = pendingRequiredConsents([
      const ConsentDocumentItem(
        id: 'b',
        title: 'Biometric',
        position: 3,
        url: '/api/v1/public/consents/b/page',
        required: true,
        accepted: false,
      ),
      const ConsentDocumentItem(
        id: 'a',
        title: 'Terms',
        position: 1,
        url: '/api/v1/public/consents/a/page',
        required: true,
        accepted: true,
      ),
      const ConsentDocumentItem(
        id: 'c',
        title: 'Optional',
        position: 2,
        url: '/api/v1/public/consents/c/page',
        required: false,
        accepted: false,
      ),
    ]);
    expect(pending.map((item) => item.id).toList(), ['b']);
  });

  testWidgets('WebView accept flow calls per-document accept API', (tester) async {
    await sl.reset();
    final appState = AppState()
      ..setSession(employee(consentsCompleted: false), mustChange: false);
    sl.registerSingleton(appState);
    final repo = _FakeConsentRepository();
    sl.registerSingleton<EmployeeRepository>(repo);

    await tester.pumpWidget(
      MaterialApp(
        home: EmployeeConsentFlowScreen(repository: repo),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Accept'), findsOneWidget);
    expect(find.byKey(const Key('consent-preview-url')), findsOneWidget);

    await tester.tap(find.text('Accept'));
    await tester.pumpAndSettle();

    expect(repo.acceptedIds, ['doc-1']);
  });
}

class _FakeConsentRepository extends Fake implements EmployeeRepository {
  final acceptedIds = <String>[];
  EmployeeConsents _payload = EmployeeConsents(
    consentsCompleted: false,
    items: const [
      ConsentDocumentItem(
        id: 'doc-1',
        title: 'Terms',
        position: 1,
        url: '/api/v1/public/consents/doc-1/page',
        required: true,
        accepted: false,
      ),
    ],
  );

  @override
  Future<EmployeeConsents> getConsents() async => _payload;

  @override
  Future<EmployeeConsents> acceptConsentDocument(
    String documentId, {
    String client = 'mobile',
  }) async {
    acceptedIds.add(documentId);
    _payload = const EmployeeConsents(
      consentsCompleted: true,
      items: [
        ConsentDocumentItem(
          id: 'doc-1',
          title: 'Terms',
          position: 1,
          url: '/api/v1/public/consents/doc-1/page',
          required: true,
          accepted: true,
        ),
      ],
    );
    return _payload;
  }
}
