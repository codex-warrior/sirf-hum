import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sirf_hum/app/product_area.dart';
import 'package:sirf_hum/features/together/application/together_clock.dart';
import 'package:sirf_hum/features/together/application/together_controller.dart';
import 'package:sirf_hum/features/together/domain/together_backend.dart';

import '../../support/session_fakes.dart';
import '../../support/together_fakes.dart';

void main() {
  // A tap that misses its target must fail the test, not warn.
  setUpAll(() => WidgetController.hitTestWarningShouldBeFatal = true);
  tearDownAll(() => WidgetController.hitTestWarningShouldBeFatal = false);

  var now = DateTime.utc(2026, 10, 20, 12);

  Future<void> pumpTogether(
    WidgetTester tester, {
    FakeTogetherBackend? together,
    bool noBackend = false,
    bool privateContent = true,
    FakeAccountSession? session,
    Size size = const Size(390, 844),
  }) async {
    setPhoneWindow(tester, size);
    await pumpSirfHum(
      tester,
      session: session,
      privateContent: privateContent,
      initialLocation: ProductArea.together.path,
      extra: [
        togetherBackendProvider.overrideWithValue(
          noBackend ? null : together ?? FakeTogetherBackend(),
        ),
        togetherClockProvider.overrideWithValue(() => now),
      ],
    );
  }

  Finder text(String s) => find.text(s);

  Future<void> tapVisible(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.tap(finder);
  }

  group('the hub', () {
    testWidgets('production today: honest, nothing startable', (tester) async {
      await pumpTogether(tester, noBackend: true);
      expect(text('Start a Watch Together'), findsOneWidget);
      for (final label in ['Listen Together', 'Call', 'Play']) {
        expect(text(label), findsOneWidget);
      }
      expect(text('Soon'), findsNWidgets(4));
      expect(find.byType(FilledButton), findsNothing);
      // Nothing is said about the partner when presence is unknown.
      expect(find.textContaining('Ravi'), findsNothing);
    });

    testWidgets('web: points to the phone, nothing startable', (tester) async {
      await pumpTogether(tester, privateContent: false);
      expect(find.textContaining('app on your phone'), findsOneWidget);
      expect(find.byType(FilledButton), findsNothing);
    });

    testWidgets('idle: time together starts from the hero; what is not '
        'built says so and starts nothing', (tester) async {
      final together = FakeTogetherBackend();
      await pumpTogether(tester, together: together);
      expect(text('Ravi is here'), findsOneWidget);
      expect(text('Spend time together'), findsOneWidget);
      expect(text('Soon'), findsNWidgets(3));

      await tapVisible(tester, text('Call'));
      await tester.pumpAndSettle();
      expect(text('Calling is coming soon.'), findsOneWidget);
      await tester.tap(find.widgetWithText(TextButton, 'OK'));
      await tester.pumpAndSettle();
      expect(together.starts, isEmpty);
    });

    testWidgets('notes and plans lead to where they live', (tester) async {
      await pumpTogether(tester);
      await tapVisible(tester, text('Make a Plan'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
        ProductArea.future.index,
      );
    });

    testWidgets('presence is said in words, not colour alone', (tester) async {
      final together = FakeTogetherBackend(
        initial: const TogetherNoSession(presence: PartnerPresence.away),
      );
      await pumpTogether(tester, together: together);
      expect(text('Ravi is away'), findsOneWidget);
    });
  });

  group('a session, step by step', () {
    testWidgets('start → waiting → together → ended → back', (tester) async {
      final together = FakeTogetherBackend()..hold = Completer<void>();
      await pumpTogether(tester, together: together);

      await tester.tap(text('Spend time together'));
      await tester.pump();
      expect(text('Starting time together…'), findsOneWidget);

      together.hold!.complete();
      together.hold = null;
      await tester.pumpAndSettle();
      expect(text('Waiting for Ravi…'), findsOneWidget);
      expect(find.widgetWithText(OutlinedButton, 'Cancel'), findsOneWidget);

      together.partnerJoins(at: now);
      await tester.pumpAndSettle();
      expect(text('You’re together.'), findsOneWidget);
      expect(text('00:00'), findsOneWidget);

      now = now.add(const Duration(seconds: 65));
      await tester.pump(const Duration(seconds: 1));
      expect(text('01:05'), findsOneWidget);

      await tester.tap(find.widgetWithText(OutlinedButton, 'End together'));
      await tester.pumpAndSettle();
      expect(text('Time together ended.'), findsOneWidget);
      expect(text('You ended it.'), findsOneWidget);

      await tester.tap(find.widgetWithText(FilledButton, 'Back to Together'));
      await tester.pumpAndSettle();
      expect(text('Spend time together'), findsOneWidget);
      expectNoSecretsOnScreen(tester);
    });

    testWidgets('invited: join or not now', (tester) async {
      final together = FakeTogetherBackend();
      await pumpTogether(tester, together: together);
      together.partnerStarts();
      await tester.pumpAndSettle();
      expect(text('Ravi wants some time together.'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Join'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Join'));
      await tester.pumpAndSettle();
      expect(text('You’re together.'), findsOneWidget);
    });

    testWidgets('the partner leaving is said plainly', (tester) async {
      final together = FakeTogetherBackend();
      await pumpTogether(tester, together: together);
      await tester.tap(text('Spend time together'));
      await tester.pumpAndSettle();
      together.partnerJoins();
      await tester.pumpAndSettle();
      together.partnerLeaves();
      await tester.pumpAndSettle();
      expect(text('Ravi left.'), findsOneWidget);
    });
  });

  group('failures', () {
    final cases = {
      TogetherFailure.unavailable: 'We couldn’t reach Sirf Hum.',
      TogetherFailure.deviceNotTrusted: 'This phone can’t join Together.',
      TogetherFailure.unexpected: 'Something didn’t look right.',
    };
    cases.forEach((failure, title) {
      testWidgets('${failure.name}: human copy, no internals', (tester) async {
        final together = FakeTogetherBackend();
        await pumpTogether(tester, together: together);
        together.emitError(failure);
        await tester.pumpAndSettle();
        expect(text(title), findsOneWidget);
        expect(find.textContaining('TogetherFailure'), findsNothing);
        expect(find.textContaining(failure.name), findsNothing);
        expectNoSecretsOnScreen(tester);
      });
    });

    testWidgets('a revoked device gets no retry button', (tester) async {
      final together = FakeTogetherBackend();
      await pumpTogether(tester, together: together);
      together.emitError(TogetherFailure.deviceNotTrusted);
      await tester.pumpAndSettle();
      expect(find.byType(FilledButton), findsNothing);
    });

    testWidgets('retry recovers', (tester) async {
      final together = FakeTogetherBackend();
      await pumpTogether(tester, together: together);
      together.emitError(TogetherFailure.unavailable);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Try again'));
      await tester.pumpAndSettle();
      expect(text('Ravi is here'), findsOneWidget);
    });
  });

  testWidgets('signing out mid-session leaves nothing behind', (tester) async {
    final session = FakeAccountSession(alice);
    final together = FakeTogetherBackend();
    await pumpTogether(tester, together: together, session: session);
    await tester.tap(text('Spend time together'));
    await tester.pumpAndSettle();
    together.partnerJoins();
    await tester.pumpAndSettle();
    expect(text('You’re together.'), findsOneWidget);

    session.emit(null);
    await tester.pumpAndSettle();
    expect(text('You’re together.'), findsNothing);
    expect(find.textContaining('Ravi'), findsNothing);
    expect(text('Your private space for two.'), findsOneWidget);
  });

  testWidgets('Home → Together reaches the hub', (tester) async {
    setPhoneWindow(tester);
    await pumpSirfHum(
      tester,
      extra: [togetherBackendProvider.overrideWithValue(FakeTogetherBackend())],
    );
    await tester.tap(find.text('Watch'));
    await tester.pumpAndSettle();
    expect(text('Spend time together'), findsOneWidget);
  });

  group('accessibility', () {
    Future<void> toState(
      WidgetTester tester,
      String name,
      FakeTogetherBackend together,
    ) async {
      switch (name) {
        case 'waiting':
          await tapVisible(tester, text('Spend time together'));
        case 'invited':
          together.partnerStarts();
        case 'active':
          together.partnerStarts();
          await tester.pumpAndSettle();
          await tapVisible(tester, find.widgetWithText(FilledButton, 'Join'));
        case 'ended':
          together.partnerStarts();
          await tester.pumpAndSettle();
          await tapVisible(tester, find.widgetWithText(FilledButton, 'Join'));
          await tester.pumpAndSettle();
          together.partnerLeaves();
        case 'failed':
          together.emitError(TogetherFailure.unavailable);
      }
      await tester.pumpAndSettle();
    }

    const states = ['idle', 'waiting', 'invited', 'active', 'ended', 'failed'];
    for (final brightness in Brightness.values) {
      for (final name in states) {
        testWidgets('$name meets guidelines in ${brightness.name}', (
          tester,
        ) async {
          tester.platformDispatcher.platformBrightnessTestValue = brightness;
          addTearDown(
            tester.platformDispatcher.clearPlatformBrightnessTestValue,
          );
          final handle = tester.ensureSemantics();
          final together = FakeTogetherBackend();
          await pumpTogether(tester, together: together);
          await toState(tester, name, together);

          await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
          await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
          await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
          await expectLater(tester, meetsGuideline(textContrastGuideline));
          handle.dispose();
        });
      }
    }

    for (final name in states) {
      testWidgets('$name survives 200% text', (tester) async {
        tester.platformDispatcher.textScaleFactorTestValue = 2;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        final together = FakeTogetherBackend();
        await pumpTogether(
          tester,
          together: together,
          size: const Size(360, 740),
        );
        await toState(tester, name, together);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('the start is announced with its activity', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpTogether(tester);
      expect(
        find.bySemanticsLabel(RegExp('^Spend time together')),
        findsOneWidget,
      );
      handle.dispose();
    });

    testWidgets('the running clock is read in words', (tester) async {
      final handle = tester.ensureSemantics();
      final together = FakeTogetherBackend();
      await pumpTogether(tester, together: together);
      await toState(tester, 'active', together);
      expect(find.bySemanticsLabel(RegExp('Together for')), findsOneWidget);
      handle.dispose();
    });
  });
}
