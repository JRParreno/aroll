import 'package:aroll_mobile/core/location/workplace_wifi.dart';
import 'package:aroll_mobile/presentation/owner/widgets/workplace_wifi_section.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('dropdown shows every signal option and the saved choice', (tester) async {
    await _pump(tester, saved: -50);

    expect(_preset(tester), RssiThresholdPreset.strong);
    expect(find.text('Strong (−50 dBm)'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
    _expectSelectionVisible(tester, 'Strong (−50 dBm)');

    await tester.tap(find.byType(DropdownButton<RssiThresholdPreset>));
    await tester.pumpAndSettle();

    for (final option in rssiThresholdOptions) {
      expect(find.text(option.label), findsWidgets);
    }
  });

  testWidgets('selecting a preset updates the closed dropdown', (tester) async {
    await _pump(tester, saved: null);
    expect(_preset(tester), RssiThresholdPreset.off);
    _expectSelectionVisible(tester, 'Off — saved Wi-Fi address only');

    await _choose(tester, 'Moderate (−60 dBm)');

    expect(_preset(tester), RssiThresholdPreset.moderate);
    expect(find.text('Moderate (−60 dBm)'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
    _expectSelectionVisible(tester, 'Moderate (−60 dBm)');
  });

  testWidgets('custom value shows the numeric input and rejects an invalid number', (
    tester,
  ) async {
    int? saved;
    var savedCalls = 0;
    await _pump(
      tester,
      saved: null,
      onSave: (value) {
        savedCalls += 1;
        saved = value;
      },
    );

    await _choose(tester, 'Custom value');

    expect(_preset(tester), RssiThresholdPreset.custom);
    expect(find.byType(TextField), findsOneWidget);
    expect(find.text('Custom minimum (dBm)'), findsOneWidget);

    await tester.enterText(find.byType(TextField), '-19');
    await tester.tap(find.text('Save signal check'));
    await tester.pump();

    expect(find.text('Enter a whole number from -120 to -20 dBm.'), findsOneWidget);
    expect(savedCalls, 0);

    await tester.enterText(find.byType(TextField), '-55');
    await tester.tap(find.text('Save signal check'));
    await tester.pumpAndSettle();

    expect(savedCalls, 1);
    expect(saved, -55);
    expect(find.text('-55'), findsWidgets);
  });

  testWidgets('off saves null and a reopened custom threshold stays filled', (tester) async {
    int? saved;
    var savedCalls = 0;
    await _pump(
      tester,
      saved: -40,
      onSave: (value) {
        savedCalls += 1;
        saved = value;
      },
    );
    expect(_preset(tester), RssiThresholdPreset.veryStrong);

    await _choose(tester, 'Off — saved Wi-Fi address only');
    await tester.tap(find.text('Save signal check'));
    await tester.pumpAndSettle();

    expect(savedCalls, 1);
    expect(saved, isNull);
    expect(_preset(tester), RssiThresholdPreset.off);
    expect(find.byType(TextField), findsNothing);

    await _pump(tester, saved: -55);
    expect(_preset(tester), RssiThresholdPreset.custom);
    expect(find.byType(TextField), findsOneWidget);
    expect(tester.widget<TextField>(find.byType(TextField)).controller?.text, '-55');
  });
}

Future<void> _pump(
  WidgetTester tester, {
  required int? saved,
  void Function(int? value)? onSave,
}) async {
  tester.view.physicalSize = const Size(800, 1400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: WorkplaceWifiSection.testing(
            key: ValueKey('rssi-$saved'),
            radiusM: 75,
            isAndroid: false,
            loadPoints: () async => const [],
            loadRssi: () async => {'minimum_rssi_dbm': saved},
            saveRssi: (value) async {
              onSave?.call(value);
              return {'minimum_rssi_dbm': value};
            },
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _choose(WidgetTester tester, String label) async {
  await tester.tap(find.byType(DropdownButton<RssiThresholdPreset>));
  await tester.pumpAndSettle();
  await tester.tap(find.text(label).last);
  await tester.pumpAndSettle();
}

RssiThresholdPreset? _preset(WidgetTester tester) {
  return tester
      .widget<DropdownButtonFormField<RssiThresholdPreset>>(
        find.byType(DropdownButtonFormField<RssiThresholdPreset>),
      )
      .initialValue;
}

void _expectSelectionVisible(WidgetTester tester, String label) {
  final textRect = tester.getRect(find.text(label));
  final buttonRect = tester.getRect(find.byType(DropdownButton<RssiThresholdPreset>));
  expect(textRect.height, greaterThan(8));
  expect(buttonRect.contains(textRect.center), isTrue);
}
