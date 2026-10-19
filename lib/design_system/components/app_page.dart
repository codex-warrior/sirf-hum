import 'package:flutter/material.dart';
import 'package:sirf_hum/design_system/theme/app_theme.dart';
import 'package:sirf_hum/design_system/tokens/layout_tokens.dart';

/// The page frame every screen uses: safe area, gutters, a readable content
/// width on wide windows, and one scroll view so 200% text never clips.
///
/// [title] is the page's single heading (announced as a header). Pages that
/// lead with something else (Home's greeting) pass [header] instead.
class AppPage extends StatelessWidget {
  const AppPage({
    required this.children,
    this.title,
    this.subtitle,
    this.header,
    super.key,
  }) : assert(title == null || header == null, 'title or header, not both');

  final String? title;
  final String? subtitle;
  final Widget? header;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final gutter = WindowSize.of(context) == WindowSize.compact
        ? Spacing.pageGutterCompact
        : Spacing.pageGutterWide;
    final textTheme = Theme.of(context).textTheme;
    final title = this.title;
    final subtitle = this.subtitle;

    return SafeArea(
      bottom: false,
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            maxWidth: WindowSize.maxContentWidth,
          ),
          child: ListView(
            padding: EdgeInsets.fromLTRB(
              gutter,
              Spacing.xxl,
              gutter,
              Spacing.xxxl,
            ),
            children: [
              ?header,
              if (title != null)
                Semantics(
                  header: true,
                  child: Text(title, style: textTheme.displaySmall),
                ),
              if (subtitle != null) ...[
                const SizedBox(height: Spacing.sm),
                Text(
                  subtitle,
                  style: textTheme.bodyLarge?.copyWith(
                    color: context.colors.textSecondary,
                  ),
                ),
              ],
              const SizedBox(height: Spacing.xxl),
              ...children,
            ],
          ),
        ),
      ),
    );
  }
}
