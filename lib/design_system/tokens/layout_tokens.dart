import 'package:flutter/widgets.dart';

/// 4-point spacing scale.
abstract final class Spacing {
  static const double xxs = 2;
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
  static const double xxl = 32;
  static const double xxxl = 48;

  /// Horizontal page gutter on phones.
  static const double pageGutterCompact = lg;
  static const double pageGutterWide = xl;
}

abstract final class Radii {
  static const double none = 0;
  static const double sm = 6;
  static const double md = 12;
  static const double lg = 20;
  static const double pill = 999;
}

/// Elevation is used sparingly: hierarchy comes from typography and space.
abstract final class Elevation {
  static const double flat = 0;
  static const double raised = 1;
  static const double overlay = 3;
  static const double modal = 6;
}

abstract final class IconSizes {
  static const double sm = 16;
  static const double md = 24;
  static const double lg = 32;
}

abstract final class TouchTargets {
  /// Minimum interactive size on every platform. Covers Material (48dp)
  /// and Apple HIG (44pt) minimums.
  static const double minimum = 48;

  /// For primary actions placed for one-handed thumb reach.
  static const double comfortable = 56;
}

/// Window size classes, aligned with Material 3 breakpoints.
enum WindowSize {
  compact,
  medium,
  expanded;

  static const double mediumMinWidth = 600;
  static const double expandedMinWidth = 840;

  /// Readable content width on large screens (web/tablet).
  static const double maxContentWidth = 720;

  static WindowSize fromWidth(double width) {
    if (width >= expandedMinWidth) return WindowSize.expanded;
    if (width >= mediumMinWidth) return WindowSize.medium;
    return WindowSize.compact;
  }

  static WindowSize of(BuildContext context) =>
      fromWidth(MediaQuery.sizeOf(context).width);
}
