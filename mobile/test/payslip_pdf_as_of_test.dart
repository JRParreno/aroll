import 'package:aroll_mobile/core/app_state.dart';
import 'package:aroll_mobile/core/di/injection.dart';
import 'package:aroll_mobile/data/repositories/employee_repository_impl.dart';
import 'package:aroll_mobile/domain/entities/employee_portal.dart';
import 'package:aroll_mobile/domain/entities/user_session.dart';
import 'package:aroll_mobile/domain/repositories/employee_repository.dart';
import 'package:aroll_mobile/presentation/employee/payslip_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

EmployeePayslip _payslip() {
  return EmployeePayslip(
    businessName: 'Cafe',
    employeeId: 'e1',
    employeeName: 'Ana',
    positionTitle: 'Cashier',
    employmentType: 'full_time',
    periodStart: DateTime(2026, 9, 1),
    periodEnd: DateTime(2026, 9, 15),
    dailyRate: 730,
    workedDays: 1,
    overtimeHours: 0.51,
    overtimePay: 30.48,
    holidayPay: 100,
    restDayPay: 0,
    restDayDays: 0,
    restDayPremiumPercent: 0,
    restDayName: null,
    restDayRecords: const [],
    deductions: 19.22,
    absentDays: 0,
    grossPay: 760.48,
    netPay: 741.26,
    hoursWorked: 8,
    lateDeductions: 19.22,
    undertimeDeductions: 0,
    payrollStatus: 'completed',
  );
}

void main() {
  final historical = DateTime(2026, 9, 10);

  setUp(() async {
    await sl.reset();
  });

  tearDown(() async {
    await sl.reset();
  });

  test('historical PDF query includes the same as_of date', () {
    expect(
      employeePayslipPdfQueryParameters(historical),
      {'as_of': '2026-09-10'},
    );
  });

  test('omitted as_of keeps PDF query empty so the backend uses today', () {
    expect(employeePayslipPdfQueryParameters(null), isEmpty);
  });

  testWidgets('historical payslip screen loads and downloads with the same as_of',
      (tester) async {
    final repo = _FakePayslipRepository();
    sl.registerSingleton(AppState()..setSession(_session(), mustChange: false));
    sl.registerSingleton<EmployeeRepository>(repo);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.binding.setSurfaceSize(const Size(800, 2000));

    await tester.pumpWidget(
      MaterialApp(home: EmployeePayslipScreen(asOf: historical)),
    );
    await tester.pumpAndSettle();

    expect(repo.payslipAsOf, historical);

    final download = find.text('Download Payslip (PDF)');
    expect(download, findsOneWidget);
    await tester.tap(download);
    await tester.pump();

    expect(repo.pdfAsOf, historical);
    expect(repo.pdfAsOf, repo.payslipAsOf);
  });

  testWidgets('current payslip screen omits as_of on both GET and PDF download',
      (tester) async {
    final repo = _FakePayslipRepository();
    sl.registerSingleton(AppState()..setSession(_session(), mustChange: false));
    sl.registerSingleton<EmployeeRepository>(repo);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.binding.setSurfaceSize(const Size(800, 2000));

    await tester.pumpWidget(
      const MaterialApp(home: EmployeePayslipScreen()),
    );
    await tester.pumpAndSettle();

    expect(repo.payslipAsOf, isNull);

    final download = find.text('Download Payslip (PDF)');
    expect(download, findsOneWidget);
    await tester.tap(download);
    await tester.pump();

    expect(repo.pdfAsOf, isNull);
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

class _FakePayslipRepository extends Fake implements EmployeeRepository {
  DateTime? payslipAsOf;
  DateTime? pdfAsOf;

  @override
  Future<EmployeePayslip> getPayslip({DateTime? asOf}) async {
    payslipAsOf = asOf;
    return _payslip();
  }

  @override
  Future<String> downloadPayslipPdf({DateTime? asOf}) async {
    pdfAsOf = asOf;
    throw Exception('skip share');
  }
}
