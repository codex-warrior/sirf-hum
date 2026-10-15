import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:sirf_hum/app/product_area.dart';
import 'package:sirf_hum/main.dart' as app;

/// Boots the real entrypoint on a device/emulator/browser and walks every
/// area. Run: `flutter test integration_test -d <device>`.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('app boots and every area is reachable', (tester) async {
    await app.main();
    await tester.pumpAndSettle();

    for (final area in ProductArea.values) {
      // Tap the label: the selected destination swaps to its selected icon.
      await tester.tap(
        find.descendant(
          of: find.byType(NavigationBar),
          matching: find.text(area.label),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text(area.purpose), findsOneWidget);
    }
    expect(find.byType(MaterialApp), findsOneWidget);
  });
}
