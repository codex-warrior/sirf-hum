import 'package:flutter/painting.dart';

/// Type scale in the brand typeface, Plus Jakarta Sans (bundled, OFL; D-156).
/// A geometric sans with warmth: confident headlines, calm body text.
///
/// Sizes are logical pixels and scale with the user's system text size.
/// Layouts must tolerate at least 200% text scaling without clipping.
abstract final class FontWeights {
  static const regular = FontWeight.w400;
  static const medium = FontWeight.w500;
  static const semibold = FontWeight.w600;
  static const bold = FontWeight.w700;
}

/// The bundled family name (pubspec `fonts:`).
const String brandFontFamily = 'PlusJakartaSans';

abstract final class TypeScale {
  static const display = TextStyle(
    fontFamily: brandFontFamily,
    fontSize: 34,
    height: 40 / 34,
    fontWeight: FontWeights.bold,
    letterSpacing: -0.6,
  );
  static const title = TextStyle(
    fontFamily: brandFontFamily,
    fontSize: 24,
    height: 30 / 24,
    fontWeight: FontWeights.semibold,
    letterSpacing: -0.2,
  );
  static const heading = TextStyle(
    fontFamily: brandFontFamily,
    fontSize: 18,
    height: 24 / 18,
    fontWeight: FontWeights.semibold,
  );
  static const body = TextStyle(
    fontFamily: brandFontFamily,
    fontSize: 16,
    height: 24 / 16,
    fontWeight: FontWeights.regular,
  );
  static const bodyStrong = TextStyle(
    fontFamily: brandFontFamily,
    fontSize: 16,
    height: 24 / 16,
    fontWeight: FontWeights.medium,
  );
  static const label = TextStyle(
    fontFamily: brandFontFamily,
    fontSize: 14,
    height: 20 / 14,
    fontWeight: FontWeights.medium,
  );
  // Floor for any readable text. Nothing smaller than this ships.
  static const caption = TextStyle(
    fontFamily: brandFontFamily,
    fontSize: 12,
    height: 16 / 12,
    fontWeight: FontWeights.regular,
  );
}
