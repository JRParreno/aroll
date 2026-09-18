import 'package:aroll_mobile/core/app_state.dart';
import 'package:aroll_mobile/core/di/injection.dart';
import 'package:aroll_mobile/core/network/api_error_detail.dart';
import 'package:aroll_mobile/domain/entities/employee_portal.dart';
import 'package:aroll_mobile/domain/entities/user_session.dart';
import 'package:aroll_mobile/domain/repositories/employee_repository.dart';
import 'package:aroll_mobile/presentation/employee/payroll_screen.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(() async {
    await sl.reset();
  });

  tearDown(() async {
    await sl.reset();
  });

  group('apiErrorCode', () {
    test('reads FastAPI detail.code from a Dio response map', () {
      expect(apiErrorCode(_snapshotUnavailable()), 'payslip_snapshot_unavailable');
      expect(isPayslipSnapshotUnavailable(_snapshotUnavailable()), isTrue);
    });

    test('does not treat other Dio errors as snapshot unavailable', () {
      expect(apiErrorCode(_notFoundString()), isNull);
      expect(isPayslipSnapshotUnavailable(_notFoundString()), isFalse);
      expect(isPayslipSnapshotUnavailable(_serverError()), isFalse);
      expect(isPayslipSnapshotUnavailable(_connectionError()), isFalse);
      expect(isPayslipSnapshotUnavailable(Exception('network')), isFalse);
    });

    test('does not match the code from DioException.toString()', () {
      final error = Exception(
        'DioException [bad response]: payslip_snapshot_unavailable',
      );
      expect(isPayslipSnapshotUnavailable(error), isFalse);
    });
  });

  testWidgets('payslip_snapshot_unavailable shows payroll unavailable state',
      (tester) async {
    _registerSession();
    sl.registerSingleton<EmployeeRepository>(
      _FakePayrollRepository(payrollError: _snapshotUnavailable()),
    );

    await tester.pumpWidget(const MaterialApp(home: EmployeePayrollScreen()));
    await tester.pumpAndSettle();

    expect(find.text('Payroll unavailable'), findsOneWidget);
    expect(
      find.text(
        'No finalized payroll record is available for this employee for the selected period.',
      ),
      findsOneWidget,
    );
    expect(find.textContaining('Unable to load employee data'), findsNothing);
    expect(find.text('Current net pay'), findsNothing);
    expect(find.text('View Payslip'), findsNothing);
  });

  testWidgets('other payroll API errors keep the generic error state',
      (tester) async {
    _registerSession();
    sl.registerSingleton<EmployeeRepository>(
      _FakePayrollRepository(payrollError: _serverError()),
    );

    await tester.pumpWidget(const MaterialApp(home: EmployeePayrollScreen()));
    await tester.pumpAndSettle();

    expect(find.textContaining('Unable to load employee data'), findsOneWidget);
    expect(find.text('Payroll unavailable'), findsNothing);
  });

  testWidgets('profile errors keep the generic error state', (tester) async {
    _registerSession();
    sl.registerSingleton<EmployeeRepository>(
      _FakePayrollRepository(profileError: _connectionError()),
    );

    await tester.pumpWidget(const MaterialApp(home: EmployeePayrollScreen()));
    await tester.pumpAndSettle();

    expect(find.textContaining('Unable to load employee data'), findsOneWidget);
    expect(find.text('Payroll unavailable'), findsNothing);
  });

  testWidgets('successful payroll response still shows current net pay',
      (tester) async {
    _registerSession();
    sl.registerSingleton<EmployeeRepository>(_FakePayrollRepository());
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.binding.setSurfaceSize(const Size(800, 2000));

    await tester.pumpWidget(const MaterialApp(home: EmployeePayrollScreen()));
    await tester.pumpAndSettle();

    expect(find.text('Current net pay'), findsOneWidget);
    expect(find.text('View Payslip'), findsOneWidget);
    expect(find.text('Payroll unavailable'), findsNothing);
    expect(find.textContaining('Unable to load employee data'), findsNothing);
  });
}

void _registerSession() {
  sl.registerSingleton(AppState()..setSession(_session(), mustChange: false));
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

DioException _snapshotUnavailable() {
  final options = RequestOptions(path: '/employee/payroll');
  return DioException(
    requestOptions: options,
    type: DioExceptionType.badResponse,
    response: Response<Map<String, dynamic>>(
      requestOptions: options,
      statusCode: 404,
      data: const {
        'detail': {
          'code': 'payslip_snapshot_unavailable',
          'message':
              'No finalized payslip snapshot exists for this employee in the selected period.',
          'period_start': '2026-09-01',
          'period_end': '2026-09-15',
        },
      },
    ),
  );
}

DioException _notFoundString() {
  final options = RequestOptions(path: '/employee/profile');
  return DioException(
    requestOptions: options,
    type: DioExceptionType.badResponse,
    response: Response<Map<String, dynamic>>(
      requestOptions: options,
      statusCode: 404,
      data: const {'detail': 'Employee not found'},
    ),
  );
}

DioException _serverError() {
  final options = RequestOptions(path: '/employee/payroll');
  return DioException(
    requestOptions: options,
    type: DioExceptionType.badResponse,
    response: Response<Map<String, dynamic>>(
      requestOptions: options,
      statusCode: 500,
      data: const {'detail': 'Internal server error'},
    ),
  );
}

DioException _connectionError() {
  return DioException(
    requestOptions: RequestOptions(path: '/employee/profile'),
    type: DioExceptionType.connectionError,
  );
}

EmployeeProfile _profile() {
  return const EmployeeProfile(
    employeeId: 'e1',
    businessId: 'b1',
    fullName: 'Ana',
    username: 'ana',
    position: 'Cashier',
    employmentType: 'full_time',
    phone: null,
    profileImageUrl: null,
    hireDate: null,
    status: 'active',
    businessName: 'Cafe',
    businessCode: 'CAFE01',
    businessType: null,
    ownerName: null,
    faceRegistrationStatus: 'completed',
    branding: null,
  );
}

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
    payrollStatus: 'current',
  );
}

class _FakePayrollRepository extends Fake implements EmployeeRepository {
  _FakePayrollRepository({this.payrollError, this.profileError});

  final Object? payrollError;
  final Object? profileError;

  @override
  Future<EmployeeProfile> getProfile() async {
    final error = profileError;
    if (error != null) throw error;
    return _profile();
  }

  @override
  Future<EmployeePayroll> getPayroll({
    DateTime? asOf,
    int historyLimit = 6,
  }) async {
    final error = payrollError;
    if (error != null) throw error;
    return EmployeePayroll(summary: _payslip(), rows: const []);
  }
}
