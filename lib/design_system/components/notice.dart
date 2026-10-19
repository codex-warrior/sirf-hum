import 'package:flutter/material.dart';
import 'package:sirf_hum/design_system/theme/app_theme.dart';
import 'package:sirf_hum/design_system/tokens/layout_tokens.dart';

/// A quiet, inline line of context ("Private moments open on your phone",
/// "Coming in an upcoming version"). Not a banner and not dismissible: it
/// states a fact about this screen.
class Notice extends StatelessWidget {
  const Notice({
    required this.message,
    this.icon = Icons.info_outline,
    super.key,
  });

  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ExcludeSemantics(
          child: Padding(
            padding: const EdgeInsets.only(top: Spacing.xxs),
            child: Icon(
              icon,
              size: IconSizes.sm + Spacing.xs,
              color: context.colors.textSecondary,
            ),
          ),
        ),
        const SizedBox(width: Spacing.sm),
        Expanded(
          child: Text(
            message,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: context.colors.textSecondary,
            ),
          ),
        ),
      ],
    );
  }
}
