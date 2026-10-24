import 'package:flutter/material.dart';
import 'package:sirf_hum/design_system/theme/app_theme.dart';
import 'package:sirf_hum/design_system/tokens/layout_tokens.dart';

/// Two overlapping initials in accent rings: the couple's mark until
/// profile photos exist (D-156). Purely visual; the names it stands for are
/// announced by the text beside it.
class CoupleMark extends StatelessWidget {
  const CoupleMark({required this.yours, required this.partner, super.key});

  /// One character each, or null for a neutral mark.
  final String? yours;
  final String? partner;

  static const double _size = TouchTargets.comfortable;

  /// The first character of [name], upper-cased, or null.
  static String? initialOf(String? name) {
    final trimmed = name?.trim();
    if (trimmed == null || trimmed.isEmpty) return null;
    return trimmed.characters.first.toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    // Initials must stay inside their circles at any text size.
    return ExcludeSemantics(
      child: MediaQuery.withNoTextScaling(
        child: SizedBox(
          width: _size * 2 - Spacing.md,
          height: _size,
          child: Stack(
            children: [
              _Circle(
                letter: yours,
                fill: colors.surfaceMuted,
                ink: colors.textPrimary,
                ring: colors.accent,
              ),
              Positioned(
                left: _size - Spacing.md,
                child: _Circle(
                  letter: partner,
                  fill: colors.accent.withValues(alpha: 0.32),
                  ink: colors.textPrimary,
                  ring: colors.accent,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Circle extends StatelessWidget {
  const _Circle({
    required this.letter,
    required this.fill,
    required this.ink,
    required this.ring,
  });

  final String? letter;
  final Color fill;
  final Color ink;
  final Color ring;

  @override
  Widget build(BuildContext context) {
    final letter = this.letter;
    return Container(
      width: CoupleMark._size,
      height: CoupleMark._size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: fill,
        shape: BoxShape.circle,
        border: Border.all(color: ring, width: Spacing.xxs),
      ),
      child: letter == null
          ? Icon(Icons.person_outline, color: ink, size: IconSizes.md)
          : Text(
              letter,
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(color: ink),
            ),
    );
  }
}
