import 'package:flutter/material.dart';
import 'package:sirf_hum/design_system/tokens/layout_tokens.dart';
import 'package:sirf_hum/design_system/tokens/semantic_colors.dart';
import 'package:sirf_hum/design_system/tokens/typography.dart';

/// Builds [ThemeData] purely from tokens. Widgets read styling from the theme
/// (or [SemanticColorsContext.colors]); they never hard-code visual values.
abstract final class AppTheme {
  static ThemeData light() => _build(Brightness.light, SemanticColors.light);
  static ThemeData dark() => _build(Brightness.dark, SemanticColors.dark);

  static ThemeData _build(Brightness brightness, SemanticColors colors) {
    final scheme = ColorScheme(
      brightness: brightness,
      primary: colors.accent,
      onPrimary: colors.onAccent,
      secondary: colors.accent,
      onSecondary: colors.onAccent,
      error: colors.danger,
      onError: colors.background,
      surface: colors.background,
      onSurface: colors.textPrimary,
      onSurfaceVariant: colors.textSecondary,
      surfaceContainerLowest: colors.surface,
      surfaceContainerLow: colors.surface,
      surfaceContainer: colors.surfaceMuted,
      outline: colors.border,
      outlineVariant: colors.border,
    );

    final textTheme = const TextTheme(
      displaySmall: TypeScale.display,
      headlineSmall: TypeScale.title,
      titleMedium: TypeScale.heading,
      bodyLarge: TypeScale.body,
      bodyMedium: TypeScale.body,
      labelLarge: TypeScale.label,
      labelMedium: TypeScale.label,
      bodySmall: TypeScale.caption,
    ).apply(bodyColor: colors.textPrimary, displayColor: colors.textPrimary);

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: colors.background,
      textTheme: textTheme,
      materialTapTargetSize: MaterialTapTargetSize.padded,
      visualDensity: VisualDensity.standard,
      extensions: [colors],
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: colors.background,
        indicatorColor: colors.surfaceMuted,
        elevation: Elevation.flat,
        labelTextStyle: WidgetStatePropertyAll(
          TypeScale.label.copyWith(color: colors.textPrimary),
        ),
      ),
      focusColor: colors.focusRing.withValues(alpha: 0.24),
    );
  }
}

extension SemanticColorsContext on BuildContext {
  SemanticColors get colors => Theme.of(this).extension<SemanticColors>()!;
}
