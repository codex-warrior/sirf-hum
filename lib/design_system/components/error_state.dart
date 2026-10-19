import 'package:flutter/material.dart';
import 'package:sirf_hum/design_system/components/empty_state.dart';
import 'package:sirf_hum/design_system/theme/app_theme.dart';
import 'package:sirf_hum/design_system/tokens/layout_tokens.dart';

/// Something went wrong: what happened, in human words, and what to do.
///
/// Takes copy only — never an exception, code or message from a backend,
/// so internal details cannot reach the screen (UX-PRINCIPLES).
class ErrorState extends StatelessWidget {
  const ErrorState({
    required this.title,
    required this.message,
    this.action,
    super.key,
  });

  final String title;
  final String message;

  /// The way forward. Omit it only when there is nothing to tap (the message
  /// then says what to do); never offer a button that cannot help.
  final StateAction? action;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final action = this.action;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        MergeSemantics(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ExcludeSemantics(
                child: Icon(
                  Icons.cloud_off_outlined,
                  size: IconSizes.lg,
                  color: context.colors.textSecondary,
                ),
              ),
              const SizedBox(height: Spacing.md),
              Semantics(
                liveRegion: true,
                child: Text(title, style: textTheme.titleMedium),
              ),
              const SizedBox(height: Spacing.xs),
              Text(
                message,
                style: textTheme.bodyLarge?.copyWith(
                  color: context.colors.textSecondary,
                ),
              ),
            ],
          ),
        ),
        if (action != null) ...[
          const SizedBox(height: Spacing.xl),
          FilledButton(onPressed: action.onPressed, child: Text(action.label)),
        ],
      ],
    );
  }
}
