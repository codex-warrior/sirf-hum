import 'package:flutter/material.dart';
import 'package:sirf_hum/design_system/theme/app_theme.dart';
import 'package:sirf_hum/design_system/tokens/layout_tokens.dart';

/// A titled part of a page. Sections are separated by space and a hairline,
/// not by boxing each one in a card (DESIGN-CONSTITUTION).
class AppSection extends StatelessWidget {
  const AppSection({
    required this.title,
    required this.child,
    this.divider = true,
    super.key,
  });

  final String title;
  final Widget child;

  /// The hairline above the section; off for the first one on a page.
  final bool divider;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: Spacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (divider) ...[
            Divider(height: 1, thickness: 1, color: context.colors.border),
            const SizedBox(height: Spacing.xl),
          ],
          Semantics(
            header: true,
            child: Text(
              title,
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: context.colors.textSecondary,
              ),
            ),
          ),
          const SizedBox(height: Spacing.md),
          child,
        ],
      ),
    );
  }
}
