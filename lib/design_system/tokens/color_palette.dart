import 'package:flutter/painting.dart';

/// Primitive colors: visual identity v1, "night intimacy" (D-156). Warm
/// near-blacks, one peach accent, and a dusk palette for the sky scene.
/// Application code must not use these directly; it uses [SemanticColors]
/// (and design-system components) so the palette changes in one place.
abstract final class ColorPalette {
  // Warm neutrals: paper to ink.
  static const neutral0 = Color(0xFFFFFFFF);
  static const neutral50 = Color(0xFFFBF7F2);
  static const neutral100 = Color(0xFFF3ECE4);
  static const neutral200 = Color(0xFFE6DDD3);
  static const neutral300 = Color(0xFFCFC3B6);
  static const neutral400 = Color(0xFFA89A8C);
  static const neutral500 = Color(0xFF7D7064);
  static const neutral600 = Color(0xFF5C5148);
  static const neutral700 = Color(0xFF3A302C);
  static const neutral800 = Color(0xFF241D1B);
  static const neutral900 = Color(0xFF1A1514);
  static const neutral950 = Color(0xFF0E0B0A);

  // Single warm accent. One accent keeps the interface quiet.
  static const accent300 = Color(0xFFEBA48E);
  static const accent400 = Color(0xFFD9785F);
  static const accent500 = Color(0xFFC0573F);
  static const accent600 = Color(0xFFA3452F);
  static const accent700 = Color(0xFF833726);

  // Dusk: the sky behind hero cards (DuskScene), top to horizon, plus the
  // moon and the foliage silhouette. Decorative only: text over it is
  // always neutral50 on the darker upper half.
  static const dusk0 = Color(0xFF231B2A);
  static const dusk1 = Color(0xFF3E2C3A);
  static const dusk2 = Color(0xFF6E4448);
  static const dusk3 = Color(0xFFB0705F);
  static const duskMoon = Color(0xFFF6DCCB);
  static const duskFoliage = Color(0xFF110C0C);

  // Status colors. Never the sole carrier of meaning (color-blind users):
  // always pair with text or an icon.
  static const success300 = Color(0xFF8FD3A9);
  static const success700 = Color(0xFF256B43);
  static const warning300 = Color(0xFFF0C36A);
  static const warning700 = Color(0xFF7A4F00);
  static const danger300 = Color(0xFFF2B8B5);
  static const danger700 = Color(0xFFA1231B);
}
