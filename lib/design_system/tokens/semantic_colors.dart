import 'package:flutter/material.dart';
import 'package:sirf_hum/design_system/tokens/color_palette.dart';

/// Role-based colors consumed by application code via
/// `Theme.of(context).extension<SemanticColors>()!` or `context.colors`.
///
/// Text/background pairs here are covered by WCAG contrast tests in
/// test/design_system/semantic_colors_contrast_test.dart.
@immutable
class SemanticColors extends ThemeExtension<SemanticColors> {
  const SemanticColors({
    required this.background,
    required this.surface,
    required this.surfaceMuted,
    required this.textPrimary,
    required this.textSecondary,
    required this.accent,
    required this.onAccent,
    required this.border,
    required this.focusRing,
    required this.success,
    required this.warning,
    required this.danger,
  });

  static const light = SemanticColors(
    background: ColorPalette.neutral50,
    surface: ColorPalette.neutral0,
    surfaceMuted: ColorPalette.neutral100,
    textPrimary: ColorPalette.neutral900,
    textSecondary: ColorPalette.neutral600,
    accent: ColorPalette.accent600,
    onAccent: ColorPalette.neutral0,
    border: ColorPalette.neutral200,
    focusRing: ColorPalette.accent700,
    success: ColorPalette.success700,
    warning: ColorPalette.warning700,
    danger: ColorPalette.danger700,
  );

  static const dark = SemanticColors(
    background: ColorPalette.neutral950,
    surface: ColorPalette.neutral900,
    surfaceMuted: ColorPalette.neutral800,
    textPrimary: ColorPalette.neutral50,
    textSecondary: ColorPalette.neutral300,
    accent: ColorPalette.accent300,
    onAccent: ColorPalette.neutral950,
    border: ColorPalette.neutral700,
    focusRing: ColorPalette.accent300,
    success: ColorPalette.success300,
    warning: ColorPalette.warning300,
    danger: ColorPalette.danger300,
  );

  final Color background;
  final Color surface;
  final Color surfaceMuted;
  final Color textPrimary;
  final Color textSecondary;
  final Color accent;
  final Color onAccent;
  final Color border;
  final Color focusRing;
  final Color success;
  final Color warning;
  final Color danger;

  @override
  SemanticColors copyWith({
    Color? background,
    Color? surface,
    Color? surfaceMuted,
    Color? textPrimary,
    Color? textSecondary,
    Color? accent,
    Color? onAccent,
    Color? border,
    Color? focusRing,
    Color? success,
    Color? warning,
    Color? danger,
  }) {
    return SemanticColors(
      background: background ?? this.background,
      surface: surface ?? this.surface,
      surfaceMuted: surfaceMuted ?? this.surfaceMuted,
      textPrimary: textPrimary ?? this.textPrimary,
      textSecondary: textSecondary ?? this.textSecondary,
      accent: accent ?? this.accent,
      onAccent: onAccent ?? this.onAccent,
      border: border ?? this.border,
      focusRing: focusRing ?? this.focusRing,
      success: success ?? this.success,
      warning: warning ?? this.warning,
      danger: danger ?? this.danger,
    );
  }

  @override
  SemanticColors lerp(SemanticColors? other, double t) {
    if (other == null) return this;
    return SemanticColors(
      background: Color.lerp(background, other.background, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      surfaceMuted: Color.lerp(surfaceMuted, other.surfaceMuted, t)!,
      textPrimary: Color.lerp(textPrimary, other.textPrimary, t)!,
      textSecondary: Color.lerp(textSecondary, other.textSecondary, t)!,
      accent: Color.lerp(accent, other.accent, t)!,
      onAccent: Color.lerp(onAccent, other.onAccent, t)!,
      border: Color.lerp(border, other.border, t)!,
      focusRing: Color.lerp(focusRing, other.focusRing, t)!,
      success: Color.lerp(success, other.success, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      danger: Color.lerp(danger, other.danger, t)!,
    );
  }
}
