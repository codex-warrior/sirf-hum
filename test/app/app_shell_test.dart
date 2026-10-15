import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sirf_hum/app/app.dart';
import 'package:sirf_hum/app/product_area.dart';

void main() {
  void setWindow(WidgetTester tester, Size size) {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  testWidgets('phone layout shows the five areas in a bottom bar', (
    tester,
  ) async {
    setWindow(tester, const Size(390, 844));
    await tester.pumpWidget(const SirfHumApp());
    await tester.pumpAndSettle();

    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.byType(NavigationRail), findsNothing);
    for (final area in ProductArea.values) {
      expect(find.text(area.label), findsWidgets);
    }
    expect(find.text(ProductArea.home.purpose), findsOneWidget);
  });

  testWidgets('selecting an area navigates to it', (tester) async {
    setWindow(tester, const Size(390, 844));
    await tester.pumpWidget(const SirfHumApp());
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(ProductArea.moments.icon));
    await tester.pumpAndSettle();

    expect(find.text(ProductArea.moments.purpose), findsOneWidget);
  });

  testWidgets('deep link opens the requested area', (tester) async {
    setWindow(tester, const Size(390, 844));
    await tester.pumpWidget(
      SirfHumApp(initialLocation: ProductArea.future.path),
    );
    await tester.pumpAndSettle();

    expect(find.text(ProductArea.future.purpose), findsOneWidget);
  });

  testWidgets('wide layout uses a navigation rail', (tester) async {
    setWindow(tester, const Size(1280, 800));
    await tester.pumpWidget(const SirfHumApp());
    await tester.pumpAndSettle();

    expect(find.byType(NavigationRail), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
  });

  group('accessibility guidelines', () {
    for (final brightness in Brightness.values) {
      testWidgets('pass in ${brightness.name} mode', (tester) async {
        setWindow(tester, const Size(390, 844));
        tester.platformDispatcher.platformBrightnessTestValue = brightness;
        addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
        final handle = tester.ensureSemantics();

        await tester.pumpWidget(const SirfHumApp());
        await tester.pumpAndSettle();

        await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
        await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
        await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
        await expectLater(tester, meetsGuideline(textContrastGuideline));
        handle.dispose();
      });
    }

    testWidgets('survives 200% text scaling without overflow', (tester) async {
      setWindow(tester, const Size(390, 844));
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

      await tester.pumpWidget(const SirfHumApp());
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    });
  });
}
