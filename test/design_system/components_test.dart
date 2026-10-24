import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sirf_hum/design_system/design_system.dart';

void main() {
  Future<void> pump(
    WidgetTester tester,
    Widget child, {
    Brightness brightness = Brightness.light,
  }) => tester.pumpWidget(
    MaterialApp(
      theme: brightness == Brightness.light
          ? AppTheme.light()
          : AppTheme.dark(),
      home: Scaffold(body: AppPage(children: [child])),
    ),
  );

  testWidgets('EmptyState reads as one unit and offers its action', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    var taps = 0;
    await pump(
      tester,
      EmptyState(
        icon: Icons.photo_outlined,
        title: 'Your first memory is waiting.',
        message: 'Moments will appear here.',
        action: StateAction(label: 'Go to Moments', onPressed: () => taps++),
      ),
    );
    expect(
      find.semantics.byLabel(RegExp('Your first memory is waiting.')),
      findsOneWidget,
    );
    await tester.tap(find.text('Go to Moments'));
    expect(taps, 1);
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    handle.dispose();
  });

  for (final brightness in Brightness.values) {
    testWidgets('ErrorState meets guidelines in ${brightness.name}', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await pump(
        tester,
        ErrorState(
          title: 'We couldn’t reach Sirf Hum.',
          message: 'Try again.',
          action: StateAction(label: 'Try again', onPressed: () {}),
        ),
        brightness: brightness,
      );
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(textContrastGuideline));
      final button = tester.getSize(find.byType(FilledButton));
      expect(button.height, greaterThanOrEqualTo(TouchTargets.comfortable));
      handle.dispose();
    });
  }

  testWidgets('Skeleton announces one label, not its blocks', (tester) async {
    final handle = tester.ensureSemantics();
    await pump(
      tester,
      const Skeleton(
        label: 'Opening Sirf Hum',
        child: Column(
          children: [
            SkeletonBlock(height: Spacing.lg),
            SkeletonBlock(height: Spacing.lg, widthFactor: 0.5),
          ],
        ),
      ),
    );
    expect(find.bySemanticsLabel('Opening Sirf Hum'), findsOneWidget);
    handle.dispose();
  });

  test('CoupleMark initials', () {
    expect(CoupleMark.initialOf('asha'), 'A');
    expect(CoupleMark.initialOf('  ravi'), 'R');
    expect(CoupleMark.initialOf('आशा'), 'आ');
    expect(CoupleMark.initialOf(''), isNull);
    expect(CoupleMark.initialOf(null), isNull);
  });

  testWidgets('CoupleMark is decorative to screen readers', (tester) async {
    final handle = tester.ensureSemantics();
    await pump(tester, const CoupleMark(yours: 'A', partner: 'R'));
    expect(find.bySemanticsLabel('A'), findsNothing);
    handle.dispose();
  });

  for (final brightness in Brightness.values) {
    testWidgets('ActionTile and HeroCard are one labelled button each, with '
        'the badge read out (${brightness.name})', (tester) async {
      final handle = tester.ensureSemantics();
      var tile = 0;
      var hero = 0;
      await pump(
        tester,
        Column(
          children: [
            HeroCard(
              semanticLabel: 'Together for 12 days',
              onTap: () => hero++,
              child: const Text('Together for 12 days'),
            ),
            Row(
              children: [
                Expanded(
                  child: ActionTile(
                    icon: Icons.videocam_outlined,
                    label: 'Call',
                    badge: 'Soon',
                    onTap: () => tile++,
                  ),
                ),
              ],
            ),
          ],
        ),
        brightness: brightness,
      );
      expect(find.bySemanticsLabel('Call, Soon'), findsOneWidget);
      expect(find.bySemanticsLabel('Together for 12 days'), findsOneWidget);
      await tester.tap(find.text('Call'));
      await tester.tap(find.text('Together for 12 days'));
      expect((tile, hero), (1, 1));
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      await expectLater(tester, meetsGuideline(textContrastGuideline));
      handle.dispose();
    });
  }
}
