import 'package:aroll_mobile/app.dart';
import 'package:aroll_mobile/core/di/injection.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(() async {
    await sl.reset();
    await initDependencies();
  });

  testWidgets('shows role choice landing screen', (tester) async {
    await tester.pumpWidget(const ArollApp());
    await tester.pump();

    expect(find.text('Welcome to Aroll+'), findsOneWidget);
    expect(find.text('Login as Employee'), findsOneWidget);
    expect(find.text('Login as Business Owner'), findsOneWidget);
  });
}
