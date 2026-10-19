import 'package:flutter/material.dart';
import 'package:sirf_hum/design_system/theme/app_theme.dart';
import 'package:sirf_hum/design_system/tokens/layout_tokens.dart';
import 'package:sirf_hum/design_system/tokens/motion.dart';

/// Loading placeholder shaped like the content it stands for, so nothing
/// jumps when the content arrives. Screen readers hear [label] once, not
/// every block.
class Skeleton extends StatefulWidget {
  const Skeleton({required this.label, required this.child, super.key});

  final String label;
  final Widget child;

  @override
  State<Skeleton> createState() => _SkeletonState();
}

class _SkeletonState extends State<Skeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(vsync: this);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // The pulse says "still working". With reduced motion it is still.
    final period = Motion.resolve(context, Motion.expressive * 2);
    if (period == Duration.zero) {
      _pulse
        ..stop()
        ..value = 1;
    } else {
      _pulse.duration = period;
      if (!_pulse.isAnimating) _pulse.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: widget.label,
      liveRegion: true,
      child: ExcludeSemantics(
        child: FadeTransition(
          opacity: Tween<double>(
            begin: 0.55,
            end: 1,
          ).animate(CurvedAnimation(parent: _pulse, curve: Motion.move)),
          child: widget.child,
        ),
      ),
    );
  }
}

/// One block inside a [Skeleton].
class SkeletonBlock extends StatelessWidget {
  const SkeletonBlock({
    required this.height,
    this.widthFactor = 1,
    this.radius = Radii.sm,
    super.key,
  });

  /// A block the height of one line of [style].
  SkeletonBlock.line(TextStyle style, {double widthFactor = 1, Key? key})
    : this(
        height: (style.fontSize ?? 0) * (style.height ?? 1),
        widthFactor: widthFactor,
        key: key,
      );

  final double height;

  /// Fraction of the available width, so the shape holds on any screen.
  final double widthFactor;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return FractionallySizedBox(
      alignment: AlignmentDirectional.centerStart,
      widthFactor: widthFactor,
      child: Container(
        height: height,
        decoration: BoxDecoration(
          color: context.colors.surfaceMuted,
          borderRadius: BorderRadius.circular(radius),
        ),
      ),
    );
  }
}
