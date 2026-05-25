import 'package:aroll_mobile/app.dart';
import 'package:aroll_mobile/core/di/injection.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(() async {
    await sl.reset();
    await initDependencies();
  });

  testWidgets('shows login screen', (tester) async {
    await tester.pumpWidget(const ArollApp());
    await tester.pump();

    expect(find.text('Aroll+'), findsOneWidget);
    expect(find.text('Sign in'), findsOneWidget);
  });
}
