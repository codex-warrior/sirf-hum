import 'package:flutter/widgets.dart';

/// Motion tokens. Motion communicates state, connection, success, transition
/// and presence; it is never decorative (docs/design/DESIGN-CONSTITUTION.md).
abstract final class Motion {
  static const Duration fast = Duration(milliseconds: 120);
  static const Duration standard = Duration(milliseconds: 220);
  static const Duration slow = Duration(milliseconds: 360);

  /// Reserved for moments of meaning (e.g. partner connects).
  static const Duration expressive = Duration(milliseconds: 560);

  static const Curve enter = Curves.easeOutCubic;
  static const Curve exit = Curves.easeInCubic;
  static const Curve move = Curves.easeInOutCubic;

  /// Returns [duration], or zero when the user asked the OS to reduce motion.
  /// Every animation in the app must go through this.
  static Duration resolve(BuildContext context, Duration duration) {
    return MediaQuery.disableAnimationsOf(context) ? Duration.zero : duration;
  }
}
