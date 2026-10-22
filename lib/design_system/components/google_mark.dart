import 'package:flutter/material.dart';
import 'package:sirf_hum/design_system/tokens/layout_tokens.dart';

/// Google's "G" for the "Continue with Google" button (D-150).
///
/// Google's sign-in branding guidelines require the standard multicolor G on
/// a white field, unmodified. These four colors and the white are therefore
/// Google's, not Sirf Hum's: they are not theme tokens and must not be used
/// for anything else. Geometry: the official 48×48 mark.
class GoogleMark extends StatelessWidget {
  const GoogleMark({this.size = IconSizes.md, super.key});

  final double size;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: Container(
      width: size,
      height: size,
      padding: EdgeInsets.all(size * _fieldInset),
      decoration: const BoxDecoration(
        color: _GoogleBrand.field,
        shape: BoxShape.circle,
      ),
      child: const CustomPaint(painter: _GPainter()),
    ),
  );

  // The white field around the G, as a share of the mark's size.
  static const _fieldInset = 0.18;
}

abstract final class _GoogleBrand {
  static const field = Color(0xFFFFFFFF);
  static const red = Color(0xFFEA4335);
  static const blue = Color(0xFF4285F4);
  static const yellow = Color(0xFFFBBC05);
  static const green = Color(0xFF34A853);
}

class _GPainter extends CustomPainter {
  const _GPainter();

  static const _viewBox = 48.0;

  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.shortestSide / _viewBox;
    canvas.scale(scale);
    void fill(Path path, Color color) => canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..isAntiAlias = true,
    );
    fill(
      Path()
        ..moveTo(24, 9.5)
        ..cubicTo(27.54, 9.5, 30.71, 10.72, 33.21, 13.1)
        ..lineTo(40.06, 6.25)
        ..cubicTo(35.9, 2.38, 30.47, 0, 24, 0)
        ..cubicTo(14.62, 0, 6.51, 5.38, 2.56, 13.22)
        ..lineTo(10.54, 19.41)
        ..cubicTo(12.43, 13.72, 17.74, 9.5, 24, 9.5)
        ..close(),
      _GoogleBrand.red,
    );
    fill(
      Path()
        ..moveTo(46.98, 24.55)
        ..cubicTo(46.98, 22.98, 46.83, 21.46, 46.6, 20)
        ..lineTo(24, 20)
        ..lineTo(24, 29.02)
        ..lineTo(36.94, 29.02)
        ..cubicTo(36.36, 31.98, 34.68, 34.5, 32.16, 36.2)
        ..lineTo(39.89, 42.2)
        ..cubicTo(44.4, 38.02, 46.98, 31.84, 46.98, 24.55)
        ..close(),
      _GoogleBrand.blue,
    );
    fill(
      Path()
        ..moveTo(10.53, 28.59)
        ..cubicTo(10.05, 27.14, 9.77, 25.6, 9.77, 24)
        ..cubicTo(9.77, 22.4, 10.04, 20.86, 10.53, 19.41)
        ..lineTo(2.55, 13.22)
        ..cubicTo(0.92, 16.46, 0, 20.12, 0, 24)
        ..cubicTo(0, 27.88, 0.92, 31.54, 2.56, 34.78)
        ..lineTo(10.53, 28.59)
        ..close(),
      _GoogleBrand.yellow,
    );
    fill(
      Path()
        ..moveTo(24, 48)
        ..cubicTo(30.48, 48, 35.93, 45.87, 39.89, 42.19)
        ..lineTo(32.16, 36.19)
        ..cubicTo(30.01, 37.64, 27.24, 38.49, 24, 38.49)
        ..cubicTo(17.74, 38.49, 12.43, 34.27, 10.53, 28.58)
        ..lineTo(2.55, 34.77)
        ..cubicTo(6.51, 42.62, 14.62, 48, 24, 48)
        ..close(),
      _GoogleBrand.green,
    );
  }

  @override
  bool shouldRepaint(_GPainter oldDelegate) => false;
}
