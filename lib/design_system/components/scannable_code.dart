import 'package:flutter/material.dart';
import 'package:qr/qr.dart';
import 'package:sirf_hum/design_system/tokens/color_palette.dart';
import 'package:sirf_hum/design_system/tokens/layout_tokens.dart';

/// A QR code for [text] (D-130). Always dark modules on a light square with
/// a quiet zone, in both themes: cameras read inverted codes poorly, so this
/// is the one place that uses fixed palette colors instead of the theme.
/// Medium error correction; drawn, never cached as a file.
class ScannableCode extends StatelessWidget {
  const ScannableCode({
    required this.text,
    required this.semanticLabel,
    this.size = 220,
    super.key,
  });

  final String text;
  final String semanticLabel;
  final double size;

  @override
  Widget build(BuildContext context) {
    final image = QrImage(
      QrCode(
        payload: QrPayload.fromString(text),
        errorCorrectLevel: QrErrorCorrectLevel.medium,
      ),
    );
    return Semantics(
      label: semanticLabel,
      image: true,
      child: ExcludeSemantics(
        child: Container(
          width: size,
          height: size,
          padding: const EdgeInsets.all(Spacing.md),
          decoration: BoxDecoration(
            color: ColorPalette.neutral0,
            borderRadius: BorderRadius.circular(Radii.md),
          ),
          child: CustomPaint(painter: _QrPainter(image)),
        ),
      ),
    );
  }
}

class _QrPainter extends CustomPainter {
  _QrPainter(this.image);

  final QrImage image;

  @override
  void paint(Canvas canvas, Size size) {
    final n = image.moduleCount;
    final cell = size.shortestSide / n;
    final paint = Paint()..color = ColorPalette.neutral950;
    for (var y = 0; y < n; y++) {
      for (var x = 0; x < n; x++) {
        if (image.isDark(y, x)) {
          canvas.drawRect(Rect.fromLTWH(x * cell, y * cell, cell, cell), paint);
        }
      }
    }
  }

  @override
  bool shouldRepaint(_QrPainter old) => old.image != image;
}
