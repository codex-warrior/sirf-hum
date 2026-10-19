import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:sirf_hum/app/product_area.dart';
import 'package:sirf_hum/security/couple/pairing.dart';

import '../test/support/session_fakes.dart';

/// The core UX on a real device (Prompt 13): the router, shell and screens
/// over fake account and pairing ports, at the device's own size, density,
/// fonts and theme. No backend: Functions are not deployed (D-025).
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('paired: Home, then every area through the bottom bar', (
    tester,
  ) async {
    await pumpSirfHum(tester);
    expect(find.text('Asha & Ravi'), findsOneWidget);
    expect(tester.takeException(), isNull);

    for (final area in ProductArea.values) {
      await tester.tap(
        find.descendant(
          of: find.byType(NavigationBar),
          matching: find.text(area.label),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
        area.index,
      );
      expect(tester.takeException(), isNull, reason: area.name);
    }
    expectNoSecretsOnScreen(tester);
  });

  testWidgets('not paired: pairing guidance, no shell', (tester) async {
    await tester.pumpWidget(const SizedBox());
    await pumpSirfHum(
      tester,
      backend: FakePairingBackend.returning(const PairingNone()),
      initialLocation: ProductArea.us.path,
    );
    expect(find.text('Invite your person.'), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
  });

  testWidgets('unreachable: human error, retry recovers', (tester) async {
    await tester.pumpWidget(const SizedBox());
    var fail = true;
    await pumpSirfHum(
      tester,
      backend: FakePairingBackend(
        () async => fail
            ? throw const PairingException(PairingFailure.unavailable)
            : paired,
      ),
    );
    expect(find.text('We couldn’t reach Sirf Hum.'), findsOneWidget);
    fail = false;
    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();
    expect(find.text('Asha & Ravi'), findsOneWidget);
  });
}
