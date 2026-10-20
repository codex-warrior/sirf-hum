import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sirf_hum/design_system/design_system.dart';
import 'package:sirf_hum/features/moments/application/moments_controller.dart';
import 'package:sirf_hum/security/moments/moment.dart';
import 'package:sirf_hum/security/moments/moments_service.dart';

/// One decrypted photo. The plaintext comes from [momentPhotoProvider]
/// (memory only) and is decoded at the size it is shown, never larger.
/// While it opens, a quiet block holds its place; if it cannot open, a calm
/// placeholder says so — never a broken or blank image.
class MomentPhotoView extends ConsumerWidget {
  const MomentPhotoView({
    required this.photo,
    required this.width,
    this.fit = BoxFit.cover,
    this.detailed = false,
    super.key,
  });

  final MomentPhoto photo;

  /// Logical width it is shown at: the decode size.
  final double width;
  final BoxFit fit;

  /// In the detail view: say what happened and offer a retry when one can
  /// help. In the grid: an icon only (the tile's label says the rest).
  final bool detailed;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final value = ref.watch(momentPhotoProvider(photo));
    final pixels = (width * MediaQuery.devicePixelRatioOf(context)).round();
    return AnimatedSwitcher(
      duration: Motion.resolve(context, Motion.standard),
      switchInCurve: Motion.enter,
      child: switch (value) {
        AsyncData(:final value) => Image.memory(
          value,
          key: const ValueKey('photo'),
          fit: fit,
          width: width,
          cacheWidth: pixels > 0 ? pixels : null,
          gaplessPlayback: true,
          excludeFromSemantics: true,
          errorBuilder: (context, _, _) =>
              _Unopened(detailed: detailed, width: width, onRetry: null),
        ),
        AsyncError(:final error) => _Unopened(
          key: const ValueKey('error'),
          detailed: detailed,
          width: width,
          onRetry:
              error is MomentException &&
                  error.failure == MomentFailure.unavailable
              ? () => ref.invalidate(momentPhotoProvider(photo))
              : null,
        ),
        _ => _Placeholder(
          key: const ValueKey('loading'),
          width: width,
          detailed: detailed,
          busy: true,
        ),
      },
    );
  }
}

class _Placeholder extends StatelessWidget {
  const _Placeholder({
    required this.width,
    required this.detailed,
    this.busy = false,
    this.icon,
    super.key,
  });

  final double width;
  final bool detailed;
  final bool busy;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final icon = this.icon;
    final box = ColoredBox(
      color: context.colors.surfaceMuted,
      child: Center(
        child: icon == null
            ? null
            : ExcludeSemantics(
                child: Icon(
                  icon,
                  size: IconSizes.md,
                  color: context.colors.textSecondary,
                ),
              ),
      ),
    );
    final shaped = detailed
        ? AspectRatio(aspectRatio: 4 / 3, child: box)
        : SizedBox.expand(child: box);
    return busy && detailed
        ? Semantics(label: 'Opening photo', liveRegion: true, child: shaped)
        : shaped;
  }
}

class _Unopened extends StatelessWidget {
  const _Unopened({
    required this.detailed,
    required this.width,
    required this.onRetry,
    super.key,
  });

  final bool detailed;
  final double width;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final placeholder = _Placeholder(
      width: width,
      detailed: detailed,
      icon: Icons.image_not_supported_outlined,
    );
    if (!detailed) return placeholder;
    final onRetry = this.onRetry;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        placeholder,
        const SizedBox(height: Spacing.sm),
        Semantics(
          liveRegion: true,
          child: Text(
            onRetry == null
                ? 'This photo couldn’t be opened.'
                : 'This photo isn’t on this phone yet.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: context.colors.textSecondary,
            ),
          ),
        ),
        if (onRetry != null)
          TextButton(
            onPressed: onRetry,
            style: TextButton.styleFrom(padding: EdgeInsets.zero),
            child: const Text('Try again'),
          ),
      ],
    );
  }
}
