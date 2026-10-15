import 'package:flutter/painting.dart';

/// Primitive colors. PROVISIONAL: the final Sirf Hum identity is not decided
/// (docs/design/DESIGN-TOKENS.md). Application code must not use these
/// directly; it uses [SemanticColors] so the palette can change in one place.
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
  static const neutral700 = Color(0xFF3F3731);
  static const neutral800 = Color(0xFF2A2420);
  static const neutral900 = Color(0xFF1C1815);
  static const neutral950 = Color(0xFF120F0D);

  // Single warm accent. One accent keeps the interface quiet.
  static const accent300 = Color(0xFFE9A08A);
  static const accent400 = Color(0xFFD9785F);
  static const accent500 = Color(0xFFC0573F);
  static const accent600 = Color(0xFFA3452F);
  static const accent700 = Color(0xFF833726);

  // Status colors. Never the sole carrier of meaning (color-blind users):
  // always pair with text or an icon.
  static const success300 = Color(0xFF8FD3A9);
  static const success700 = Color(0xFF256B43);
  static const warning300 = Color(0xFFF0C36A);
  static const warning700 = Color(0xFF7A4F00);
  static const danger300 = Color(0xFFF2B8B5);
  static const danger700 = Color(0xFFA1231B);
}
