import 'package:flutter/material.dart';
import 'package:sirf_hum/design_system/theme/app_theme.dart';
import 'package:sirf_hum/design_system/tokens/layout_tokens.dart';

/// A soft square choice: an accent outline icon over its label (Watch,
/// Listen, Make a Plan…). [badge] marks something that is not built yet
/// ("Soon"): the tile still answers a tap, so the screen can say so.
class ActionTile extends StatelessWidget {
  const ActionTile({
    required this.icon,
    required this.label,
    required this.onTap,
    this.badge,
    this.height = Spacing.xxxl * 2 + Spacing.lg,
    super.key,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final String? badge;
  final double height;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final badge = this.badge;
    return Semantics(
      button: true,
      label: badge == null ? label : '$label, $badge',
      excludeSemantics: true,
      child: Material(
        color: colors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Radii.lg),
          side: BorderSide(color: colors.surfaceMuted),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: height),
            child: Stack(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: Spacing.sm,
                    vertical: Spacing.lg,
                  ),
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          icon,
                          size: IconSizes.lg + Spacing.xs,
                          color: colors.accent,
                        ),
                        const SizedBox(height: Spacing.md),
                        Text(
                          label,
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.bodyLarge,
                        ),
                      ],
                    ),
                  ),
                ),
                if (badge != null)
                  PositionedDirectional(
                    top: Spacing.sm,
                    end: Spacing.sm,
                    child: _Badge(badge),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: context.colors.surfaceMuted,
      borderRadius: BorderRadius.circular(Radii.pill),
    ),
    child: Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: Spacing.sm,
        vertical: Spacing.xxs,
      ),
      child: Text(
        text,
        style: Theme.of(
          context,
        ).textTheme.bodySmall?.copyWith(color: context.colors.textSecondary),
      ),
    ),
  );
}
