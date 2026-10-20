import 'package:aroll_mobile/core/app_state.dart';
import 'package:aroll_mobile/core/di/injection.dart';
import 'package:aroll_mobile/core/legal/consent_sync.dart';
import 'package:aroll_mobile/core/legal/employee_gate_loader.dart';
import 'package:aroll_mobile/core/legal/privacy_preferences.dart';
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
    bool? permissionsOnboardingCompleted,
    String userId = 'u1',
  }) {
    return UserSession(
      userId: userId,
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
      permissionsOnboardingCompleted: permissionsOnboardingCompleted,
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

  test('existing completed consent skips Terms gate', () {
    final appState = AppState()
      ..setSession(employee(consentsCompleted: true), mustChange: false)
      ..setConsentStatus(
        legalSatisfied: true,
        biometricSatisfied: true,
        consentsCompleted: true,
      )
      ..setPermissionsIntroSeen(true)
      ..setFaceEnrolled(true);
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

  test('ConsentDocumentItem parses accepted_at and accepted_version', () {
    final item = ConsentDocumentItem.fromJson({
      'id': 'doc-1',
      'title': 'Terms',
      'position': 1,
      'url': '/page',
      'required': true,
      'accepted': true,
      'version': 'v2',
      'accepted_version': 'v2',
      'accepted_at': '2026-09-18T10:15:00Z',
      'body_text': '## Who may use Aroll+\n\nA readable paragraph.\n\n- First item',
    });
    expect(item.acceptedVersion, 'v2');
    expect(item.acceptedAt, isNotNull);
    expect(item.acceptedAt!.toUtc().year, 2026);
    expect(item.bodyText, contains('Who may use Aroll+'));
  });

  test('consent sync soft-fails without wiping known-good completed state', () async {
    final appState = AppState()
      ..setSession(employee(consentsCompleted: true), mustChange: false)
      ..setConsentStatus(
        legalSatisfied: true,
        biometricSatisfied: true,
        consentsCompleted: true,
      );
    final repo = _FailingConsentRepository();
    await syncEmployeeConsentGate(appState, repo);
    expect(appState.consentsCompleted, isTrue);
    expect(
      resolveAuthenticatedRoute(
        appState
          ..setPermissionsIntroSeen(true)
          ..setFaceEnrolled(true),
      ),
      '/home',
    );
  });

  test('consent sync marks incomplete when GET fails and no known-good state',
      () async {
    final appState = AppState()
      ..setSession(employee(consentsCompleted: false), mustChange: false);
    final repo = _FailingConsentRepository();
    await syncEmployeeConsentGate(appState, repo);
    expect(appState.consentsCompleted, isFalse);
    expect(resolveAuthenticatedRoute(appState), '/consents');
  });

  test('permission onboarding is account-scoped across account switch', () async {
    final prefs = _MemoryPrivacyPreferences();
    final accountA = employee(
      userId: 'user-a',
      permissionsOnboardingCompleted: false,
    );
    final accountB = employee(
      userId: 'user-b',
      permissionsOnboardingCompleted: false,
    );

    expect(
      await shouldShowPermissionsOnboarding(
        session: accountA,
        preferences: prefs,
        accountCompletedFromServer: false,
      ),
      isTrue,
    );

    await prefs.markAccountOnboardingCompleted('user-a');

    expect(
      await shouldShowPermissionsOnboarding(
        session: accountA,
        preferences: prefs,
        accountCompletedFromServer: true,
      ),
      isFalse,
    );

    // Same device, different account — must not inherit A's state.
    expect(
      await shouldShowPermissionsOnboarding(
        session: accountB,
        preferences: prefs,
        accountCompletedFromServer: false,
      ),
      isTrue,
    );
  });

  test('completed account skips intro even when OS permissions missing',
      () async {
    final prefs = _MemoryPrivacyPreferences();
    final accountA = employee(
      userId: 'user-a',
      permissionsOnboardingCompleted: true,
    );

    // Server says completed on a new device with missing OS grants —
    // do not replay the introductory onboarding.
    expect(
      await shouldShowPermissionsOnboarding(
        session: accountA,
        preferences: prefs,
        accountCompletedFromServer: true,
      ),
      isFalse,
    );

    // Local cache alone is enough when server flag is present in session.
    expect(
      await shouldShowPermissionsOnboarding(
        session: accountA,
        preferences: prefs,
        accountCompletedFromServer: true,
      ),
      isFalse,
    );
  });

  test('incomplete account still shows intro when only another account completed',
      () async {
    final prefs = _MemoryPrivacyPreferences();
    await prefs.markAccountOnboardingCompleted('user-a');

    // Account B has not completed App Permission onboarding — must show intro
    // even if another account completed it on the same device.
    expect(
      await shouldShowPermissionsOnboarding(
        session: employee(
          userId: 'user-b',
          permissionsOnboardingCompleted: false,
        ),
        preferences: prefs,
        accountCompletedFromServer: false,
      ),
      isTrue,
    );
  });

  test('incomplete account shows intro regardless of unrelated completion flags',
      () async {
    final prefs = _MemoryPrivacyPreferences();
    // Consent/face/account existence are irrelevant; only App Permission
    // completion (server/local) controls this gate.
    expect(
      await shouldShowPermissionsOnboarding(
        session: employee(
          userId: 'brand-new',
          permissionsOnboardingCompleted: false,
          consentsCompleted: true,
        ),
        preferences: prefs,
        accountCompletedFromServer: false,
      ),
      isTrue,
    );
  });

  test('setSession honors server permissions completion before notify', () {
    final appState = AppState()
      ..setSession(
        employee(permissionsOnboardingCompleted: true),
        mustChange: false,
      );
    expect(appState.permissionsIntroSeen, isTrue);

    final pending = AppState()
      ..setSession(
        employee(permissionsOnboardingCompleted: false),
        mustChange: false,
      );
    expect(pending.permissionsIntroSeen, isFalse);
  });

  test('local account cache skips intro when server flag not yet synced',
      () async {
    final prefs = _MemoryPrivacyPreferences();
    await prefs.markAccountOnboardingCompleted('user-a');

    expect(
      await shouldShowPermissionsOnboarding(
        session: employee(
          userId: 'user-a',
          permissionsOnboardingCompleted: false,
        ),
        preferences: prefs,
        accountCompletedFromServer: false,
      ),
      isFalse,
    );
  });

  testWidgets('checkbox required before agree; accept API called after check',
      (tester) async {
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

    expect(find.text('Step 1 of 1'), findsOneWidget);
    expect(find.text('I have read and agree to this document.'), findsOneWidget);
    expect(find.text('I Agree & Continue'), findsOneWidget);
    expect(find.text("I Don't Agree"), findsOneWidget);
    expect(find.byKey(const Key('consent-preview-url')), findsOneWidget);
    expect(
      find.textContaining('embed=1'),
      findsOneWidget,
    );

    final continueButton = find.widgetWithText(FilledButton, 'I Agree & Continue');
    expect(tester.widget<FilledButton>(continueButton).onPressed, isNull);

    await tester.tap(find.byType(Checkbox));
    await tester.pumpAndSettle();
    expect(tester.widget<FilledButton>(continueButton).onPressed, isNotNull);

    await tester.tap(continueButton);
    await tester.pumpAndSettle();

    expect(repo.acceptedIds, ['doc-1']);
    expect(appState.consentsCompleted, isTrue);
  });

  testWidgets('view consent shows minimal status metadata', (tester) async {
    await sl.reset();
    final appState = AppState()
      ..setSession(employee(consentsCompleted: true), mustChange: false)
      ..setConsentStatus(
        legalSatisfied: true,
        biometricSatisfied: true,
        consentsCompleted: true,
      );
    sl.registerSingleton(appState);
    final repo = _FakeConsentRepository()..seedAccepted();
    sl.registerSingleton<EmployeeRepository>(repo);

    await tester.pumpWidget(
      MaterialApp(
        home: EmployeeConsentFlowScreen(
          repository: repo,
          viewOnly: true,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('Agreed'), findsOneWidget);
    expect(find.textContaining('Required'), findsOneWidget);
    expect(find.textContaining('Version'), findsOneWidget);
  });

  testWidgets('employee consent shows published body headings, lists, and scroll',
      (tester) async {
    await sl.reset();
    final appState = AppState()
      ..setSession(employee(consentsCompleted: false), mustChange: false);
    sl.registerSingleton(appState);
    final repo = _FakeConsentRepository()..seedBody();
    sl.registerSingleton<EmployeeRepository>(repo);

    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: EmployeeConsentFlowScreen(repository: repo),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Terms and Conditions'), findsWidgets);
    expect(find.text('Who may use Aroll+'), findsOneWidget);
    expect(find.textContaining('A readable paragraph.'), findsOneWidget);
    expect(find.text('Owners manage this workplace.'), findsOneWidget);
    expect(find.byType(SingleChildScrollView), findsWidgets);

    await tester.scrollUntilVisible(
      find.text('Owners manage this workplace.'),
      80,
    );
    expect(find.text('Owners manage this workplace.'), findsOneWidget);
  });
}

class _MemoryPrivacyPreferences implements PermissionsOnboardingStore {
  final Map<String, String> _data = {};

  @override
  Future<bool> hasAccountOnboardingCompleted(String userId) async =>
      _data['aroll_permissions_onboarding_completed_$userId'] == '1';

  @override
  Future<void> markAccountOnboardingCompleted(String userId) async {
    _data['aroll_permissions_onboarding_completed_$userId'] = '1';
  }

  @override
  Future<bool> hasDeviceReviewedForAccount(String userId) async =>
      _data['aroll_permissions_device_reviewed_$userId'] == '1';

  @override
  Future<void> markDeviceReviewedForAccount(String userId) async {
    _data['aroll_permissions_device_reviewed_$userId'] = '1';
  }

  @override
  Future<void> clearLegacyDeviceFlag() async {}
}

class _FailingConsentRepository extends Fake implements EmployeeRepository {
  @override
  Future<EmployeeConsents> getConsents() async {
    throw Exception('network');
  }
}

class _FakeConsentRepository extends Fake implements EmployeeRepository {
  final acceptedIds = <String>[];
  EmployeeConsents _payload = const EmployeeConsents(
    consentsCompleted: false,
    items: [
      ConsentDocumentItem(
        id: 'doc-1',
        title: 'Terms',
        position: 1,
        url: '/api/v1/public/consents/doc-1/page',
        required: true,
        accepted: false,
        version: 'v1',
      ),
    ],
  );

  void seedBody() {
    _payload = const EmployeeConsents(
      consentsCompleted: false,
      items: [
        ConsentDocumentItem(
          id: 'doc-1',
          title: 'Terms and Conditions',
          position: 1,
          url: '/api/v1/public/consents/doc-1/page',
          required: true,
          accepted: false,
          version: 'v1',
          bodyText:
              'Terms and Conditions\n\n## Who may use Aroll+\n\nA readable paragraph.\n\n- Owners manage this workplace.',
        ),
      ],
    );
  }

  void seedAccepted() {
    _payload = EmployeeConsents(
      consentsCompleted: true,
      items: [
        ConsentDocumentItem(
          id: 'doc-1',
          title: 'Terms',
          position: 1,
          url: '/api/v1/public/consents/doc-1/page',
          required: true,
          accepted: true,
          version: 'v1',
          acceptedVersion: 'v1',
          acceptedAt: DateTime.utc(2026, 9, 18, 10, 15),
        ),
      ],
    );
  }

  @override
  Future<EmployeeConsents> getConsents() async => _payload;

  @override
  Future<EmployeeConsents> acceptConsentDocument(
    String documentId, {
    String client = 'mobile',
  }) async {
    acceptedIds.add(documentId);
    _payload = EmployeeConsents(
      consentsCompleted: true,
      items: [
        ConsentDocumentItem(
          id: 'doc-1',
          title: 'Terms',
          position: 1,
          url: '/api/v1/public/consents/doc-1/page',
          required: true,
          accepted: true,
          version: 'v1',
          acceptedVersion: 'v1',
          acceptedAt: DateTime.utc(2026, 9, 18, 10, 15),
        ),
      ],
    );
    return _payload;
  }

  @override
  Future<void> withdrawBiometricConsent({String client = 'mobile'}) async {}

  @override
  Future<void> completePermissionsOnboarding() async {}
}
