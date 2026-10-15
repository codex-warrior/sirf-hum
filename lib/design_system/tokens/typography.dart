import 'package:flutter/painting.dart';

/// Type scale. Font family is intentionally unset (platform default) until
/// the typography decision is made; see docs/design/DESIGN-TOKENS.md.
///
/// Sizes are logical pixels and scale with the user's system text size.
/// Layouts must tolerate at least 200% text scaling without clipping.
abstract final class FontWeights {
  static const regular = FontWeight.w400;
  static const medium = FontWeight.w500;
  static const semibold = FontWeight.w600;
}

abstract final class TypeScale {
  static const display = TextStyle(
    fontSize: 34,
    height: 40 / 34,
    fontWeight: FontWeights.semibold,
    letterSpacing: -0.4,
  );
  static const title = TextStyle(
    fontSize: 24,
    height: 30 / 24,
    fontWeight: FontWeights.semibold,
    letterSpacing: -0.2,
  );
  static const heading = TextStyle(
    fontSize: 18,
    height: 24 / 18,
    fontWeight: FontWeights.semibold,
  );
  static const body = TextStyle(
    fontSize: 16,
    height: 24 / 16,
    fontWeight: FontWeights.regular,
  );
  static const bodyStrong = TextStyle(
    fontSize: 16,
    height: 24 / 16,
    fontWeight: FontWeights.medium,
  );
  static const label = TextStyle(
    fontSize: 14,
    height: 20 / 14,
    fontWeight: FontWeights.medium,
  );
  // Floor for any readable text. Nothing smaller than this ships.
  static const caption = TextStyle(
    fontSize: 12,
    height: 16 / 12,
    fontWeight: FontWeights.regular,
  );
}
