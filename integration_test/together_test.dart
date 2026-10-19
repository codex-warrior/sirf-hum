import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:sirf_hum/features/together/application/together_controller.dart';

import '../test/support/session_fakes.dart';
import '../test/support/together_fakes.dart';

/// Together on a real device (Prompt 14). The session runs over the
/// test-only FakeTogetherBackend: this proves the app's state machine and
/// screens, not a production backend (none exists yet, D-112).
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('without a backend, Together is honest: nothing startable', (
    tester,
  ) async {
    await pumpSirfHum(tester);
    await tester.tap(find.widgetWithText(FilledButton, 'Go to Together'));
    await tester.pumpAndSettle();
    expect(find.text('What do you want to do?'), findsOneWidget);
    expect(find.byType(FilledButton), findsNothing);
  });

  testWidgets('Home → Together → start → together → ended → back', (
    tester,
  ) async {
    await tester.pumpWidget(const SizedBox());
    final together = FakeTogetherBackend();
    await pumpSirfHum(
      tester,
      extra: [togetherBackendProvider.overrideWithValue(together)],
    );

    await tester.tap(find.widgetWithText(FilledButton, 'Go to Together'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Start'));
    await tester.pumpAndSettle();
    expect(find.text('Waiting for Ravi…'), findsOneWidget);

    together.partnerJoins();
    await tester.pumpAndSettle();
    expect(find.text('You’re together.'), findsOneWidget);

    await tester.tap(find.widgetWithText(OutlinedButton, 'End together'));
    await tester.pumpAndSettle();
    expect(find.text('Time together ended.'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'Back to Together'));
    await tester.pumpAndSettle();
    expect(find.text('What do you want to do?'), findsOneWidget);
    expect(tester.takeException(), isNull);
    expectNoSecretsOnScreen(tester);
  });
}
