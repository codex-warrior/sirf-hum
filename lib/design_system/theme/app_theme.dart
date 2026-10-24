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
      headlineSmall: TypeScale.hero,
      titleLarge: TypeScale.title,
      titleMedium: TypeScale.heading,
      titleSmall: TypeScale.bodyStrong,
      bodyLarge: TypeScale.body,
      bodyMedium: TypeScale.secondary,
      labelLarge: TypeScale.label,
      labelMedium: TypeScale.label,
      bodySmall: TypeScale.caption,
      labelSmall: TypeScale.caption,
    ).apply(bodyColor: colors.textPrimary, displayColor: colors.textPrimary);

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      fontFamily: brandFontFamily,
      colorScheme: scheme,
      scaffoldBackgroundColor: colors.background,
      textTheme: textTheme,
      materialTapTargetSize: MaterialTapTargetSize.padded,
      visualDensity: VisualDensity.standard,
      extensions: [colors],
      // Buttons: one filled (accent) primary per screen, text buttons for
      // everything else. Heights are touch-target tokens, never smaller.
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: colors.accent,
          foregroundColor: colors.onAccent,
          minimumSize: const Size(
            TouchTargets.minimum,
            TouchTargets.comfortable,
          ),
          padding: const EdgeInsets.symmetric(horizontal: Spacing.xl),
          textStyle: TypeScale.bodyStrong,
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(Radii.md)),
          ),
          elevation: Elevation.flat,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: colors.textPrimary,
          minimumSize: const Size(TouchTargets.minimum, TouchTargets.minimum),
          padding: const EdgeInsets.symmetric(horizontal: Spacing.lg),
          side: BorderSide(color: colors.border),
          textStyle: TypeScale.label,
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(Radii.md)),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: colors.accent,
          minimumSize: const Size(TouchTargets.minimum, TouchTargets.minimum),
          padding: const EdgeInsets.symmetric(horizontal: Spacing.sm),
          textStyle: TypeScale.label,
        ),
      ),
      dividerTheme: DividerThemeData(color: colors.border, thickness: 1),
      dialogTheme: DialogThemeData(
        backgroundColor: colors.surface,
        elevation: Elevation.modal,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(Radii.lg)),
        ),
      ),
      // The selected area glows in the accent (icon and label); there is
      // no pill behind it. Shape and weight, not colour alone, also mark it:
      // the selected icon is filled and its label is bolder.
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: colors.background,
        indicatorColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: Elevation.flat,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        iconTheme: WidgetStateProperty.resolveWith(
          (states) => IconThemeData(
            size: IconSizes.md + Spacing.xs,
            color: states.contains(WidgetState.selected)
                ? colors.accent
                : colors.textPrimary,
          ),
        ),
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? TypeScale.label.copyWith(
                  color: colors.accent,
                  fontWeight: FontWeights.bold,
                )
              : TypeScale.label.copyWith(color: colors.textPrimary),
        ),
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: colors.background,
        indicatorColor: colors.surfaceMuted,
        selectedIconTheme: IconThemeData(color: colors.textPrimary),
        unselectedIconTheme: IconThemeData(color: colors.textSecondary),
        selectedLabelTextStyle: TypeScale.label.copyWith(
          color: colors.textPrimary,
        ),
        unselectedLabelTextStyle: TypeScale.label.copyWith(
          color: colors.textSecondary,
        ),
      ),
      focusColor: colors.focusRing.withValues(alpha: 0.24),
    );
  }
}

extension SemanticColorsContext on BuildContext {
  SemanticColors get colors => Theme.of(this).extension<SemanticColors>()!;
}
