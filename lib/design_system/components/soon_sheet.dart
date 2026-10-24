import 'package:flutter/material.dart';
import 'package:sirf_hum/design_system/theme/app_theme.dart';
import 'package:sirf_hum/design_system/tokens/layout_tokens.dart';

/// Says plainly that [what] is not built yet ("Calling", "Devices"). Never
/// starts anything: the honest answer to tapping a "Soon" tile (D-156).
Future<void> showSoonSheet(BuildContext context, String what) {
  final textTheme = Theme.of(context).textTheme;
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: context.colors.surface,
    showDragHandle: true,
    builder: (context) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          Spacing.xl,
          0,
          Spacing.xl,
          Spacing.xl,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('$what is coming soon.', style: textTheme.titleLarge),
            const SizedBox(height: Spacing.sm),
            Text(
              'We’re building it now. It will appear right here, just for '
              'the two of you.',
              style: textTheme.bodyLarge?.copyWith(
                color: context.colors.textSecondary,
              ),
            ),
            const SizedBox(height: Spacing.xl),
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('OK'),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
