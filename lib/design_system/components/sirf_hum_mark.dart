import 'package:flutter/material.dart';
import 'package:sirf_hum/design_system/tokens/color_palette.dart';

/// The Sirf Hum mark: a doorway (a home) with two people inside. The same
/// geometry as the launcher icon (`android/.../ic_launcher_foreground.xml`).
/// Decorative: the name beside it carries the meaning.
class SirfHumMark extends StatelessWidget {
  const SirfHumMark({required this.size, super.key});

  final double size;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: CustomPaint(size: Size.square(size), painter: const _MarkPainter()),
  );
}

class _MarkPainter extends CustomPainter {
  const _MarkPainter();

  // The mark's own fixed colors, as on the launcher icon; brand artwork,
  // not interface color, so it does not follow the theme.
  static const _you = ColorPalette.accent300;
  static const _them = ColorPalette.accent500;

  @override
  void paint(Canvas canvas, Size size) {
    // Drawn in the icon's 108-unit space, cropped to the mark (x 34..74,
    // y 28..82) and centred.
    const left = 34.0, top = 28.0, width = 40.0, height = 54.0;
    final scale = size.shortestSide / height;
    canvas
      ..save()
      ..translate(
        (size.width - width * scale) / 2 - left * scale,
        (size.height - height * scale) / 2 - top * scale,
      )
      ..scale(scale);

    final frame = Path()
      ..fillType = PathFillType.evenOdd
      ..moveTo(34, 82)
      ..lineTo(34, 48)
      ..arcToPoint(const Offset(74, 48), radius: const Radius.circular(20))
      ..lineTo(74, 82)
      ..close()
      ..moveTo(39, 82)
      ..lineTo(39, 48)
      ..arcToPoint(const Offset(69, 48), radius: const Radius.circular(15))
      ..lineTo(69, 82)
      ..close();
    canvas.drawPath(frame, Paint()..color = _you);

    for (final (x, color) in [(47.5, _you), (60.5, _them)]) {
      final paint = Paint()..color = color;
      canvas
        ..drawCircle(Offset(x, 57), 4, paint)
        ..drawRRect(
          RRect.fromLTRBR(x - 5.5, 63, x + 5.5, 82, const Radius.circular(5.5)),
          paint,
        );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_MarkPainter oldDelegate) => false;
}
