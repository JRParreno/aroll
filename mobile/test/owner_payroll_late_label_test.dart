import 'package:aroll_mobile/presentation/owner/payroll/owner_payroll_format.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('fractional late minutes keep two decimals', () {
    expect(
      ownerLateDeductionLabel(2.60, 1),
      'Late (2.60 min × ₱1.00)',
    );
    expect(
      ownerLateDeductionLabel(25.78, 1),
      'Late (25.78 min × ₱1.00)',
    );
  });

  test('whole late minutes omit trailing zeros', () {
    expect(ownerLateDeductionLabel(5, 1), 'Late (5 min × ₱1.00)');
    expect(ownerLateDeductionLabel(5.00, 1), 'Late (5 min × ₱1.00)');
  });

  test('zero late minutes use the plain deduction label', () {
    expect(ownerLateDeductionLabel(0, 1), 'Late Deduction');
  });

  test('deduction amount formatting is unchanged', () {
    expect(ownerPayrollMoney(2.60), '₱2.60');
    expect(ownerPayrollMoney(25.78), '₱25.78');
  });
}
