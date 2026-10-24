import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:sirf_hum/design_system/tokens/color_palette.dart';

/// The brand's one illustration (D-156): an evening sky over a tree, with a
/// crescent moon — the hour two people far apart still share. Painted, not
/// an image, so it is crisp at any size and costs no asset or network.
/// Decorative: excluded from semantics.
class DuskScene extends StatelessWidget {
  const DuskScene({super.key});

  @override
  Widget build(BuildContext context) => const ExcludeSemantics(
    child: CustomPaint(painter: _DuskPainter(), child: SizedBox.expand()),
  );
}

class _DuskPainter extends CustomPainter {
  const _DuskPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final w = size.width;
    final h = size.height;

    // Sky: violet above, warm towards the lower right.
    canvas.drawRect(
      rect,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment(-0.7, -1),
          end: Alignment(0.7, 1),
          colors: [
            ColorPalette.dusk0,
            ColorPalette.dusk1,
            ColorPalette.dusk2,
            ColorPalette.dusk3,
          ],
          stops: [0, 0.42, 0.76, 1],
        ).createShader(rect),
    );
    // Afterglow on the horizon behind the tree.
    canvas.drawRect(
      rect,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(0.75, 1.1),
          radius: 0.9,
          colors: [
            ColorPalette.dusk3.withValues(alpha: 0.55),
            ColorPalette.dusk3.withValues(alpha: 0),
          ],
        ).createShader(rect),
    );

    _moon(canvas, Offset(w * 0.8, h * 0.26), math.min(h * 0.1, 20));
    _tree(canvas, size);
  }

  void _moon(Canvas canvas, Offset c, double r) {
    canvas.drawCircle(
      c,
      r * 1.6,
      Paint()
        ..color = ColorPalette.duskMoon.withValues(alpha: 0.18)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, r),
    );
    final crescent = Path.combine(
      PathOperation.difference,
      Path()..addOval(Rect.fromCircle(center: c, radius: r)),
      Path()..addOval(
        Rect.fromCircle(
          center: c + Offset(-r * 0.48, -r * 0.32),
          radius: r * 0.92,
        ),
      ),
    );
    canvas.drawPath(crescent, Paint()..color = ColorPalette.duskMoon);
  }

  /// A leafy silhouette rising from the lower-right corner. Deterministic
  /// (fixed seed), so the scene never flickers between frames.
  void _tree(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final scale = math.min(h / 180, 1.4);
    final ink = Paint()..color = ColorPalette.duskFoliage;
    final stem = Paint()
      ..color = ColorPalette.duskFoliage
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    final random = math.Random(7);

    // Branch tips the leaves gather around, fanning up and left.
    final base = Offset(w + 6 * scale, h + 4 * scale);
    // A dense mound where the branches meet the ground.
    for (final (dx, dy, r) in const [
      (0.0, 0.0, 34.0),
      (-30.0, 6.0, 24.0),
      (-12.0, -26.0, 22.0),
      (-52.0, 10.0, 16.0),
    ]) {
      canvas.drawCircle(base + Offset(dx * scale, dy * scale), r * scale, ink);
    }
    final tips = [
      Offset(w - 30 * scale, h - 120 * scale),
      Offset(w - 70 * scale, h - 85 * scale),
      Offset(w - 105 * scale, h - 40 * scale),
      Offset(w - 10 * scale, h - 140 * scale),
      Offset(w - 128 * scale, h - 12 * scale),
    ];
    for (final tip in tips) {
      stem.strokeWidth = 2.2 * scale;
      final mid = Offset.lerp(base, tip, 0.5)! + Offset(6 * scale, 0);
      canvas.drawPath(
        Path()
          ..moveTo(base.dx, base.dy)
          ..quadraticBezierTo(mid.dx, mid.dy, tip.dx, tip.dy),
        stem,
      );
      for (var i = 0; i < 52; i++) {
        final t = 0.35 + random.nextDouble() * 0.75;
        final along = Offset.lerp(base, tip, t)!;
        final spread = 18 * scale * t;
        final at =
            along +
            Offset(
              (random.nextDouble() - 0.5) * 2 * spread,
              (random.nextDouble() - 0.5) * 2 * spread,
            );
        final leaf = (2.5 + random.nextDouble() * 3.5) * scale;
        canvas
          ..save()
          ..translate(at.dx, at.dy)
          ..rotate(random.nextDouble() * math.pi)
          ..drawOval(
            Rect.fromCenter(
              center: Offset.zero,
              width: leaf * 2.2,
              height: leaf,
            ),
            ink,
          )
          ..restore();
      }
    }
  }

  @override
  bool shouldRepaint(_DuskPainter oldDelegate) => false;
}
