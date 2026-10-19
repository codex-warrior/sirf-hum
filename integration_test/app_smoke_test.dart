import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:sirf_hum/main.dart' as app;

/// Boots the real entrypoint on a device/emulator/browser. CI runs it without
/// Firebase credentials, so the session is signed out: the welcome screen
/// shows and no couple screen is reachable (D-106, D-108).
/// Run: `flutter test integration_test/app_smoke_test.dart -d <device>`.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('app boots to the welcome when signed out', (tester) async {
    await app.main();
    await tester.pumpAndSettle();

    expect(find.byType(MaterialApp), findsOneWidget);
    expect(find.text('A private home for the two of you.'), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
  });
}
