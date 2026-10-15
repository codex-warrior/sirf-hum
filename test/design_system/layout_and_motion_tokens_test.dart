import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sirf_hum/design_system/design_system.dart';

void main() {
  group('WindowSize.fromWidth', () {
    test('maps Material 3 breakpoints', () {
      expect(WindowSize.fromWidth(360), WindowSize.compact);
      expect(WindowSize.fromWidth(599.9), WindowSize.compact);
      expect(WindowSize.fromWidth(600), WindowSize.medium);
      expect(WindowSize.fromWidth(839.9), WindowSize.medium);
      expect(WindowSize.fromWidth(840), WindowSize.expanded);
    });
  });

  test('touch targets meet platform minimums (48dp Android, 44pt iOS)', () {
    expect(TouchTargets.minimum, greaterThanOrEqualTo(48));
    expect(TouchTargets.comfortable, greaterThan(TouchTargets.minimum));
  });

  test('type scale never goes below the readable floor', () {
    for (final style in [
      TypeScale.display,
      TypeScale.title,
      TypeScale.heading,
      TypeScale.body,
      TypeScale.bodyStrong,
      TypeScale.label,
      TypeScale.caption,
    ]) {
      expect(style.fontSize, greaterThanOrEqualTo(12));
    }
  });

  group('Motion.resolve', () {
    Future<Duration> resolveWith(
      WidgetTester tester, {
      required bool disableAnimations,
    }) async {
      late Duration resolved;
      await tester.pumpWidget(
        MediaQuery(
          data: MediaQueryData(disableAnimations: disableAnimations),
          child: Builder(
            builder: (context) {
              resolved = Motion.resolve(context, Motion.standard);
              return const SizedBox();
            },
          ),
        ),
      );
      return resolved;
    }

    testWidgets('keeps duration by default', (tester) async {
      expect(
        await resolveWith(tester, disableAnimations: false),
        Motion.standard,
      );
    });

    testWidgets('is zero when the user reduces motion', (tester) async {
      expect(await resolveWith(tester, disableAnimations: true), Duration.zero);
    });
  });
}
