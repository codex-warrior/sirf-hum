import 'package:flutter/material.dart';
import 'package:sirf_hum/app/product_area.dart';
import 'package:sirf_hum/design_system/design_system.dart';

/// Scaffolding that marks where a product area will live. Replaced by the
/// real feature in its own phase; contains no product functionality.
class AreaPlaceholder extends StatelessWidget {
  const AreaPlaceholder({required this.area, super.key});

  final ProductArea area;

  @override
  Widget build(BuildContext context) {
    final gutter = WindowSize.of(context) == WindowSize.compact
        ? Spacing.pageGutterCompact
        : Spacing.pageGutterWide;
    final textTheme = Theme.of(context).textTheme;

    return SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            maxWidth: WindowSize.maxContentWidth,
          ),
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: gutter),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Semantics(
                  header: true,
                  child: Text(area.label, style: textTheme.displaySmall),
                ),
                const SizedBox(height: Spacing.sm),
                Text(
                  area.purpose,
                  style: textTheme.bodyLarge?.copyWith(
                    color: context.colors.textSecondary,
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
