import 'package:flutter/material.dart';
import 'package:sirf_hum/design_system/theme/app_theme.dart';
import 'package:sirf_hum/design_system/tokens/layout_tokens.dart';

/// A one-tap action offered by a state component.
class StateAction {
  const StateAction({required this.label, required this.onPressed});

  final String label;
  final VoidCallback onPressed;
}

/// "Nothing here yet" that explains the value and, when one exists, offers
/// the one next step (UX-PRINCIPLES rule 8). Copy is human, never
/// "No data available".
class EmptyState extends StatelessWidget {
  const EmptyState({
    required this.title,
    required this.message,
    this.icon,
    this.action,
    super.key,
  });

  final IconData? icon;
  final String title;
  final String message;
  final StateAction? action;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final icon = this.icon;
    final action = this.action;

    return MergeSemantics(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (icon != null) ...[
            ExcludeSemantics(
              child: Icon(
                icon,
                size: IconSizes.lg,
                color: context.colors.textSecondary,
              ),
            ),
            const SizedBox(height: Spacing.md),
          ],
          Text(title, style: textTheme.titleMedium),
          const SizedBox(height: Spacing.xs),
          Text(
            message,
            style: textTheme.bodyLarge?.copyWith(
              color: context.colors.textSecondary,
            ),
          ),
          if (action != null) ...[
            const SizedBox(height: Spacing.sm),
            TextButton(
              onPressed: action.onPressed,
              // Flush with the text above; the 48dp target still holds.
              style: TextButton.styleFrom(padding: EdgeInsets.zero),
              child: Text(action.label),
            ),
          ],
        ],
      ),
    );
  }
}
