import 'package:aroll_mobile/core/app_state.dart';
import 'package:aroll_mobile/core/di/injection.dart';
import 'package:aroll_mobile/core/utils/format.dart';
import 'package:aroll_mobile/domain/entities/employee_portal.dart';
import 'package:aroll_mobile/domain/entities/user_session.dart';
import 'package:aroll_mobile/domain/repositories/employee_repository.dart';
import 'package:aroll_mobile/presentation/employee/payroll_history_screen.dart';
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

  testWidgets('payroll history stays compact for zero and completed periods',
      (tester) async {
    sl.registerSingleton(AppState()..setSession(_session(), mustChange: false));
    sl.registerSingleton<EmployeeRepository>(_HistoryRepository());

    final router = GoRouter(
      initialLocation: '/payroll/history',
      routes: [
        GoRoute(
          path: '/payroll/history',
          builder: (context, state) => const EmployeePayrollHistoryScreen(),
        ),
        GoRoute(
          path: '/payslip',
          builder: (_, state) => Scaffold(
            body: Text('opened ${state.uri.query}'),
          ),
        ),
        GoRoute(path: '/home', builder: (context, state) => const SizedBox()),
        GoRoute(
          path: '/shift-history',
          builder: (context, state) => const SizedBox(),
        ),
        GoRoute(
          path: '/scan-attendance',
          builder: (context, state) => const SizedBox(),
        ),
        GoRoute(
            path: '/payroll', builder: (context, state) => const SizedBox()),
        GoRoute(
            path: '/profile', builder: (context, state) => const SizedBox()),
      ],
    );
    addTearDown(router.dispose);

    await tester.binding.setSurfaceSize(const Size(320, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();

    expect(find.text('Payroll History'), findsOneWidget);
    expect(find.text('Past pay periods'), findsOneWidget);
    expect(find.text('2 periods available'), findsOneWidget);
    expect(find.text('Current'), findsOneWidget);
    expect(find.text('Oct 1 – Oct 15, 2026'), findsOneWidget);
    expect(find.text(formatPeso(0)), findsWidgets);
    expect(find.text('Final net pay'), findsWidgets);

    await tester.scrollUntilVisible(
      find.text('Completed'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Dec 16, 2025 – Jan 15, 2026'), findsOneWidget);
    expect(find.text(formatPeso(122500.75)), findsWidgets);
    expect(find.text('Completed'), findsOneWidget);

    final net = tester.getRect(find.text('Final net pay').last);
    final nav = tester.getRect(find.byType(NavigationBar));
    expect(net.bottom, lessThanOrEqualTo(nav.top));

    await tester.tap(find.text('Completed'));
    await tester.pumpAndSettle();
    expect(find.text('opened as_of=2026-01-15'), findsOneWidget);

    router.pop();
    await tester.pumpAndSettle();
    await tester.binding.setSurfaceSize(const Size(800, 900));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('Oct 1 – Oct 15, 2026'), findsOneWidget);
  });
}

UserSession _session() {
  return const UserSession(
    userId: 'u1',
    employeeId: 'e1',
    businessId: 'b1',
    fullName: 'Ana',
    position: 'Cashier',
    role: 'employee',
    businessName: 'Cafe',
  );
}

class _HistoryRepository extends Fake implements EmployeeRepository {
  @override
  Future<EmployeePayroll> getPayroll({
    DateTime? asOf,
    int historyLimit = 6,
  }) async {
    return EmployeePayroll(
      summary: EmployeePayslip(
        businessName: 'Cafe',
        employeeId: 'e1',
        employeeName: 'Ana',
        positionTitle: 'Cashier',
        employmentType: 'full_time',
        periodStart: DateTime(2026, 10, 1),
        periodEnd: DateTime(2026, 10, 15),
        dailyRate: 0,
        workedDays: 0,
        overtimeHours: 0,
        overtimePay: 0,
        holidayPay: 0,
        restDayPay: 0,
        restDayDays: 0,
        restDayPremiumPercent: 0,
        restDayName: null,
        restDayRecords: const [],
        deductions: 0,
        absentDays: 0,
        grossPay: 0,
        netPay: 0,
        hoursWorked: 0,
        lateDeductions: 0,
        undertimeDeductions: 0,
        payrollStatus: 'current',
      ),
      rows: const [],
      history: [
        EmployeePayrollHistoryItem(
          periodStart: DateTime(2026, 10, 1),
          periodEnd: DateTime(2026, 10, 15),
          payDate: DateTime(2026, 10, 20),
          dailyRate: 0,
          workedDays: 0,
          hoursWorked: 0,
          lateDeductions: 0,
          undertimeDeductions: 0,
          overtimePay: 0,
          overtimeHours: 0,
          grossPay: 0,
          deductions: 0,
          netPay: 0,
          payrollStatus: 'current',
          finalNetPay: 0,
        ),
        EmployeePayrollHistoryItem(
          periodStart: DateTime(2025, 12, 16),
          periodEnd: DateTime(2026, 1, 15),
          payDate: DateTime(2026, 1, 20),
          dailyRate: 12500,
          workedDays: 12,
          hoursWorked: 96,
          lateDeductions: 0,
          undertimeDeductions: 0,
          overtimePay: 0,
          overtimeHours: 0,
          grossPay: 150000,
          deductions: 0,
          netPay: 122500.75,
          payrollStatus: 'completed',
          finalNetPay: 122500.75,
          payrollAdjustmentsTotal: 2500,
        ),
      ],
    );
  }
}
