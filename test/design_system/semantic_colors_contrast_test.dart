import 'dart:math' as math;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sirf_hum/design_system/tokens/semantic_colors.dart';

/// WCAG 2.x contrast ratio.
double contrastRatio(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
}

const _textMinimum = 4.5; // WCAG AA, normal text.
const _nonTextMinimum = 3.0; // WCAG AA, UI components / focus indicators.

void main() {
  for (final (name, c) in [
    ('light', SemanticColors.light),
    ('dark', SemanticColors.dark),
  ]) {
    group('$name semantic colors meet WCAG AA', () {
      final textPairs = <String, (Color, Color)>{
        'textPrimary on background': (c.textPrimary, c.background),
        'textPrimary on surface': (c.textPrimary, c.surface),
        'textPrimary on surfaceMuted': (c.textPrimary, c.surfaceMuted),
        'textSecondary on background': (c.textSecondary, c.background),
        'textSecondary on surface': (c.textSecondary, c.surface),
        'textSecondary on surfaceMuted': (c.textSecondary, c.surfaceMuted),
        'onAccent on accent': (c.onAccent, c.accent),
        'accent on background': (c.accent, c.background),
        'danger on background': (c.danger, c.background),
        'success on background': (c.success, c.background),
        'warning on background': (c.warning, c.background),
      };

      textPairs.forEach((label, pair) {
        test(label, () {
          expect(
            contrastRatio(pair.$1, pair.$2),
            greaterThanOrEqualTo(_textMinimum),
          );
        });
      });

      test('focusRing on background', () {
        expect(
          contrastRatio(c.focusRing, c.background),
          greaterThanOrEqualTo(_nonTextMinimum),
        );
      });
    });
  }

  test('lerp endpoints return the original themes', () {
    const light = SemanticColors.light;
    const dark = SemanticColors.dark;
    expect(light.lerp(dark, 0).background, light.background);
    expect(light.lerp(dark, 1).background, dark.background);
    expect(light.lerp(null, 0.5), same(light));
  });
}
