import 'package:flutter/material.dart';
import 'package:sirf_hum/design_system/components/dusk_scene.dart';
import 'package:sirf_hum/design_system/theme/app_theme.dart';
import 'package:sirf_hum/design_system/tokens/color_palette.dart';
import 'package:sirf_hum/design_system/tokens/layout_tokens.dart';

/// The one large card on a screen, over the dusk scene (D-156). Its
/// [child] is laid out on the darker upper-left of the sky, where light
/// text stays legible; [HeroCard.textColor] is that text colour.
class HeroCard extends StatelessWidget {
  const HeroCard({
    required this.child,
    required this.semanticLabel,
    this.onTap,
    this.minHeight = Spacing.xxxl * 3 + Spacing.xl,
    this.horizon = DuskHorizon.tree,
    super.key,
  });

  final DuskHorizon horizon;

  final Widget child;

  /// What the whole card announces (it is one button when tappable).
  final String semanticLabel;
  final VoidCallback? onTap;
  final double minHeight;

  /// Text over the scene: the lightest neutral, in either theme.
  static const Color textColor = ColorPalette.neutral50;

  /// Secondary text over the scene.
  static const Color mutedTextColor = ColorPalette.neutral200;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: onTap != null,
      label: semanticLabel,
      excludeSemantics: true,
      child: ConstrainedBox(
        constraints: BoxConstraints(minHeight: minHeight),
        child: Material(
          color: ColorPalette.dusk0,
          borderRadius: BorderRadius.circular(Radii.xl),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: Stack(
              children: [
                Positioned.fill(child: DuskScene(horizon: horizon)),
                Padding(
                  padding: const EdgeInsets.all(Spacing.xl),
                  child: DefaultTextStyle.merge(
                    style: const TextStyle(color: textColor),
                    child: IconTheme.merge(
                      data: const IconThemeData(color: textColor),
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          minHeight: minHeight - Spacing.xl * 2,
                        ),
                        child: child,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The square icon well a hero card leads with ("+", "▷").
class HeroIcon extends StatelessWidget {
  const HeroIcon(this.icon, {super.key});

  final IconData icon;

  @override
  Widget build(BuildContext context) => Container(
    width: TouchTargets.comfortable + Spacing.lg,
    height: TouchTargets.comfortable + Spacing.lg,
    decoration: BoxDecoration(
      color: context.colors.accent.withValues(alpha: 0.28),
      borderRadius: BorderRadius.circular(Radii.lg),
    ),
    child: Icon(icon, size: IconSizes.lg, color: context.colors.accent),
  );
}
