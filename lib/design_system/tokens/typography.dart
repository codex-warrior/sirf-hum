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

/// Tuned for a premium, calm read (D-158): one step smaller than Material's
/// defaults, with explicit letter spacing (Material adds +0.5 to body text,
/// which makes this geometric face look loose). Headlines are tight, body
/// text is neutral.
abstract final class TypeScale {
  static const display = TextStyle(
    fontFamily: brandFontFamily,
    fontSize: 28,
    height: 34 / 28,
    fontWeight: FontWeights.bold,
    letterSpacing: -0.6,
  );

  /// Hero card titles: a step above section titles.
  static const hero = TextStyle(
    fontFamily: brandFontFamily,
    fontSize: 22,
    height: 28 / 22,
    fontWeight: FontWeights.bold,
    letterSpacing: -0.4,
  );
  static const title = TextStyle(
    fontFamily: brandFontFamily,
    fontSize: 20,
    height: 26 / 20,
    fontWeight: FontWeights.semibold,
    letterSpacing: -0.3,
  );
  static const heading = TextStyle(
    fontFamily: brandFontFamily,
    fontSize: 16,
    height: 22 / 16,
    fontWeight: FontWeights.semibold,
    letterSpacing: -0.1,
  );
  static const body = TextStyle(
    fontFamily: brandFontFamily,
    fontSize: 15,
    height: 22 / 15,
    fontWeight: FontWeights.regular,
    letterSpacing: 0,
  );
  static const bodyStrong = TextStyle(
    fontFamily: brandFontFamily,
    fontSize: 15,
    height: 22 / 15,
    fontWeight: FontWeights.medium,
    letterSpacing: 0,
  );

  /// Supporting lines under a title (subtitles, details).
  static const secondary = TextStyle(
    fontFamily: brandFontFamily,
    fontSize: 14,
    height: 20 / 14,
    fontWeight: FontWeights.regular,
    letterSpacing: 0,
  );
  static const label = TextStyle(
    fontFamily: brandFontFamily,
    fontSize: 13,
    height: 18 / 13,
    fontWeight: FontWeights.medium,
    letterSpacing: 0.1,
  );
  // Floor for any readable text. Nothing smaller than this ships.
  static const caption = TextStyle(
    fontFamily: brandFontFamily,
    fontSize: 12,
    height: 16 / 12,
    fontWeight: FontWeights.regular,
    letterSpacing: 0.1,
  );
}
