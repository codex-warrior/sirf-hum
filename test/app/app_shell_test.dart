import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sirf_hum/app/product_area.dart';
import 'package:sirf_hum/security/couple/pairing.dart';
import 'package:sirf_hum_crypto/sirf_hum_crypto.dart';

import '../support/session_fakes.dart';

void main() {
  int selectedIndex(WidgetTester tester) =>
      tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex;

  final areaTitles = {
    ProductArea.home: 'Asha & Ravi',
    ProductArea.together: 'Spend time together, wherever you are.',
    ProductArea.moments: 'Your memories, just for the two of you.',
    ProductArea.future: 'Things you want to do together.',
    ProductArea.us: 'The two of you.',
  };

  testWidgets('phone layout shows the five areas in a bottom bar', (
    tester,
  ) async {
    setPhoneWindow(tester);
    await pumpSirfHum(tester);

    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.byType(NavigationRail), findsNothing);
    expect(find.byType(NavigationDestination), findsNWidgets(5));
    for (final area in ProductArea.values) {
      expect(
        find.widgetWithText(NavigationDestination, area.label),
        findsOneWidget,
      );
    }
    expect(selectedIndex(tester), ProductArea.home.index);
  });

  testWidgets('every area is reachable and marked selected', (tester) async {
    setPhoneWindow(tester);
    await pumpSirfHum(tester);

    for (final area in ProductArea.values.reversed) {
      await tester.tap(find.byIcon(area.icon).hitTestable().first);
      await tester.pumpAndSettle();
      expect(selectedIndex(tester), area.index, reason: area.name);
      expect(find.text(areaTitles[area]!), findsOneWidget, reason: area.name);
    }
  });

  testWidgets('deep link opens the requested area', (tester) async {
    setPhoneWindow(tester);
    await pumpSirfHum(tester, initialLocation: ProductArea.future.path);

    expect(selectedIndex(tester), ProductArea.future.index);
    expect(find.text(areaTitles[ProductArea.future]!), findsOneWidget);
  });

  testWidgets('a deep link opened while loading lands after loading', (
    tester,
  ) async {
    setPhoneWindow(tester);
    final backend = FakePairingBackend(() async {
      await Future<void>.delayed(const Duration(seconds: 1));
      return paired;
    });
    await pumpSirfHum(
      tester,
      backend: backend,
      initialLocation: ProductArea.moments.path,
      settle: false,
    );
    await tester.pump();
    expect(find.byType(NavigationBar), findsNothing);
    expect(find.bySemanticsLabel('Opening Sirf Hum'), findsOneWidget);

    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(selectedIndex(tester), ProductArea.moments.index);
  });

  testWidgets('wide layout uses a navigation rail', (tester) async {
    setPhoneWindow(tester, const Size(1280, 800));
    await pumpSirfHum(tester);

    expect(find.byType(NavigationRail), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
    expect(find.text('Asha & Ravi'), findsOneWidget);
  });

  testWidgets('no shell without a couple, whatever the deep link', (
    tester,
  ) async {
    setPhoneWindow(tester);
    for (final area in ProductArea.values) {
      // A fresh app per link, so nothing carries over between them.
      await tester.pumpWidget(const SizedBox());
      await pumpSirfHum(
        tester,
        backend: FakePairingBackend.returning(const PairingNone()),
        initialLocation: area.path,
      );
      expect(find.byType(NavigationBar), findsNothing, reason: area.name);
      expect(find.text('Bring your person in.'), findsOneWidget);
    }
  });

  testWidgets('losing the couple state leaves the shell', (tester) async {
    setPhoneWindow(tester);
    final session = FakeAccountSession(alice);
    await pumpSirfHum(tester, session: session);
    expect(find.byType(NavigationBar), findsOneWidget);

    session.emit(null);
    await tester.pumpAndSettle();
    expect(find.byType(NavigationBar), findsNothing);
    expect(find.text('Your private space for two.'), findsOneWidget);
  });

  testWidgets('switching account never shows the previous couple', (
    tester,
  ) async {
    setPhoneWindow(tester);
    final session = FakeAccountSession(alice);
    final bobAnswer = Completer<PairingState>();
    var calls = 0;
    final backend = FakePairingBackend(() {
      calls++;
      return calls == 1 ? Future.value(paired) : bobAnswer.future;
    });
    await pumpSirfHum(
      tester,
      session: session,
      backend: backend,
      initialLocation: ProductArea.us.path,
    );
    expect(find.text('Asha & Ravi'), findsOneWidget);

    session.emit(AccountId('uidBob'));
    // One frame for the auth event to reach the session, one to rebuild.
    await tester.pump();
    await tester.pump();
    // From then on: nothing of the previous couple.
    expect(find.textContaining('Asha'), findsNothing);
    expect(find.textContaining('Ravi'), findsNothing);
    // Once the route transition ends, the shell is gone while Bob's answer
    // is still pending.
    await tester.pump(const Duration(seconds: 1));
    expect(find.byType(NavigationBar), findsNothing);
    expect(find.bySemanticsLabel('Opening Sirf Hum'), findsOneWidget);
    expect(find.textContaining('Asha'), findsNothing);

    bobAnswer.complete(const PairingNone());
    await tester.pumpAndSettle();
    expect(find.text('Bring your person in.'), findsOneWidget);
    expect(find.textContaining('Asha'), findsNothing);
  });

  group('accessibility guidelines', () {
    for (final brightness in Brightness.values) {
      for (final area in ProductArea.values) {
        testWidgets('${area.name} passes in ${brightness.name} mode', (
          tester,
        ) async {
          setPhoneWindow(tester);
          tester.platformDispatcher.platformBrightnessTestValue = brightness;
          addTearDown(
            tester.platformDispatcher.clearPlatformBrightnessTestValue,
          );
          final handle = tester.ensureSemantics();

          await pumpSirfHum(tester, initialLocation: area.path);

          await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
          await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
          await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
          await expectLater(tester, meetsGuideline(textContrastGuideline));
          handle.dispose();
        });
      }
    }

    for (final area in ProductArea.values) {
      testWidgets('${area.name} survives 200% text without overflow', (
        tester,
      ) async {
        setPhoneWindow(tester, const Size(360, 740));
        tester.platformDispatcher.textScaleFactorTestValue = 2;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

        await pumpSirfHum(tester, initialLocation: area.path);

        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('navigation destinations are announced by name', (
      tester,
    ) async {
      setPhoneWindow(tester);
      final handle = tester.ensureSemantics();
      await pumpSirfHum(tester);
      for (final area in ProductArea.values) {
        expect(
          find.semantics.byLabel(RegExp(area.label)),
          findsWidgets,
          reason: area.label,
        );
      }
      handle.dispose();
    });
  });
}
