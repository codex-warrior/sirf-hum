import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:sirf_hum/design_system/tokens/color_palette.dart';

/// The brand's one illustration (D-156): an evening sky over a tree, with a
/// crescent moon — the hour two people far apart still share. Painted, not
/// an image, so it is crisp at any size and costs no asset or network.
/// Decorative: excluded from semantics.
class DuskScene extends StatelessWidget {
  const DuskScene({this.horizon = DuskHorizon.tree, super.key});

  final DuskHorizon horizon;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: CustomPaint(
      painter: _DuskPainter(horizon),
      child: const SizedBox.expand(),
    ),
  );
}

/// What stands against the sky: a tree (being together now) or distant
/// hills (what is ahead of you).
enum DuskHorizon { tree, hills }

class _DuskPainter extends CustomPainter {
  const _DuskPainter(this.horizon);

  final DuskHorizon horizon;

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
    switch (horizon) {
      case DuskHorizon.tree:
        _tree(canvas, size);
      case DuskHorizon.hills:
        _hills(canvas, size);
    }
  }

  /// Two ridges rising to the right, the nearer one darker.
  void _hills(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    Path ridge(double base, List<(double, double)> peaks) {
      final path = Path()..moveTo(0, h);
      path.lineTo(0, h * base);
      var x = 0.0;
      var y = h * base;
      for (final (px, py) in peaks) {
        final nx = w * px;
        final ny = h * py;
        path.quadraticBezierTo((x + nx) / 2, (y + ny) / 2 - h * 0.02, nx, ny);
        x = nx;
        y = ny;
      }
      return path
        ..lineTo(w, h)
        ..close();
    }

    canvas
      ..drawPath(
        ridge(0.98, [(0.45, 0.94), (0.72, 0.7), (0.86, 0.76), (1, 0.66)]),
        Paint()..color = ColorPalette.dusk1.withValues(alpha: 0.85),
      )
      ..drawPath(
        ridge(1.02, [(0.5, 1), (0.78, 0.84), (1, 0.9)]),
        Paint()..color = ColorPalette.duskFoliage,
      );
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
  bool shouldRepaint(_DuskPainter oldDelegate) =>
      oldDelegate.horizon != horizon;
}
