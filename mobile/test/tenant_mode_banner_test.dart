import 'package:aroll_mobile/core/app_state.dart';
import 'package:aroll_mobile/core/di/injection.dart';
import 'package:aroll_mobile/core/tenant_mode.dart';
import 'package:aroll_mobile/domain/entities/user_session.dart';
import 'package:aroll_mobile/presentation/shared/research_evaluation_gate.dart';
import 'package:aroll_mobile/presentation/shared/tenant_mode_banner.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

UserSession _session({
  required bool isDemo,
  required bool isInternalTest,
  required String businessName,
}) {
  return UserSession(
    userId: 'u1',
    employeeId: 'e1',
    businessId: 'b1',
    fullName: 'Hannah Cruz',
    position: 'Barista',
    role: 'employee',
    businessName: businessName,
    isDemo: isDemo,
    isInternalTest: isInternalTest,
  );
}

void main() {
  testWidgets('shows DEMO MODE banner for demo session', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TenantModeBanner(
            session: _session(
              isDemo: true,
              isInternalTest: false,
              businessName: 'AROLL+ Demo Café',
            ),
          ),
        ),
      ),
    );

    expect(find.text(TenantModeCopy.demoTitle), findsOneWidget);
    expect(find.text('AROLL+ Demo Café'), findsOneWidget);
    expect(find.text(TenantModeCopy.demoBody), findsOneWidget);
    expect(find.text(TenantModeCopy.devTestTitle), findsNothing);
  });

  testWidgets('shows developer test banner for internal test session',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TenantModeBanner(
            session: _session(
              isDemo: false,
              isInternalTest: true,
              businessName: 'AROLL+ Dev Lab',
            ),
          ),
        ),
      ),
    );

    expect(find.text(TenantModeCopy.devTestTitle), findsOneWidget);
    expect(find.text(TenantModeCopy.devTestBody), findsOneWidget);
    expect(find.text(TenantModeCopy.demoTitle), findsNothing);
    expect(find.text(TenantModeCopy.payslipSample1), findsNothing);
  });

  testWidgets('ordinary session shows no tenant banner', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TenantModeBanner(
            session: _session(
              isDemo: false,
              isInternalTest: false,
              businessName: 'Acme Cafe',
            ),
          ),
        ),
      ),
    );

    expect(find.text(TenantModeCopy.demoTitle), findsNothing);
    expect(find.text(TenantModeCopy.devTestTitle), findsNothing);
  });

  testWidgets('demo attendance copy explains no camera or GPS', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Text(TenantModeCopy.demoAttendanceBody),
        ),
      ),
    );
    expect(find.textContaining('No camera or personal location is required'),
        findsOneWidget);
    expect(find.textContaining('seeded demo employee identity'), findsOneWidget);
  });

  testWidgets('payslip sample banner shows demonstration wording', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: PayslipSampleBanner()),
      ),
    );
    expect(find.text(TenantModeCopy.payslipSample1), findsOneWidget);
    expect(find.text(TenantModeCopy.payslipSample2), findsOneWidget);
  });

  testWidgets('research copy includes 18+ and voluntary participation', (tester) async {
    expect(TenantModeCopy.researchAttestation.contains('18 years of age'), isTrue);
    expect(TenantModeCopy.researchVoluntary.contains('voluntary'), isTrue);
    expect(
      TenantModeCopy.researchVoluntary.contains('will not affect employment'),
      isTrue,
    );
    expect(TenantModeCopy.demoAttendanceBody.contains('No camera'), isTrue);
    expect(
      TenantModeCopy.demoAttendanceBody.contains('personal location is required'),
      isTrue,
    );
  });

  group('research evaluation overlay', () {
    setUp(() async {
      await sl.reset();
      sl.registerSingleton(AppState());
    });

    testWidgets('shows 18+ gate for DEMO01 session only', (tester) async {
      sl<AppState>().setSession(
        _session(
          isDemo: true,
          isInternalTest: false,
          businessName: 'AROLL+ Demo Café',
        ),
        mustChange: false,
      );
      await tester.pumpWidget(
        const MaterialApp(
          home: ResearchEvaluationOverlay(child: Text('Workspace')),
        ),
      );

      expect(find.text(TenantModeCopy.researchTitle), findsOneWidget);
      expect(find.text(TenantModeCopy.researchAttestation), findsOneWidget);
      expect(find.text(TenantModeCopy.researchVoluntary), findsOneWidget);
      expect(find.text('Register your face'), findsNothing);
      expect(find.textContaining('Enable GPS'), findsNothing);
    });

    testWidgets('does not show research gate for DEVTEST or ordinary sessions',
        (tester) async {
      sl<AppState>().setSession(
        _session(
          isDemo: false,
          isInternalTest: true,
          businessName: 'AROLL+ Dev Lab',
        ),
        mustChange: false,
      );
      await tester.pumpWidget(
        const MaterialApp(
          home: ResearchEvaluationOverlay(child: Text('Workspace')),
        ),
      );
      expect(find.text(TenantModeCopy.researchTitle), findsNothing);

      sl<AppState>().clearSession();
      sl<AppState>().setSession(
        _session(
          isDemo: false,
          isInternalTest: false,
          businessName: 'Acme Cafe',
        ),
        mustChange: false,
      );
      await tester.pump();
      expect(find.text(TenantModeCopy.researchTitle), findsNothing);
    });
  });
}
