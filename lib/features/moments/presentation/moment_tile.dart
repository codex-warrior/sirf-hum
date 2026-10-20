import 'package:flutter/material.dart';
import 'package:sirf_hum/design_system/design_system.dart';
import 'package:sirf_hum/features/moments/presentation/moment_photo_view.dart';
import 'package:sirf_hum/security/moments/moment.dart';

/// What a screen reader hears for an entry. Built from what the person can
/// see; never an identifier.
String momentLabel(
  BuildContext context,
  MomentEntry entry, {
  required String partnerName,
}) {
  final date = MaterialLocalizations.of(context).formatFullDate(entry.day);
  return switch (entry) {
    UnreadableMoment() => 'A memory from $date that couldn’t be opened',
    Moment() => [
      'Memory from $date',
      entry.photoCount == 1 ? '1 photo' : '${entry.photoCount} photos',
      entry.addedByYou ? 'added by you' : 'added by $partnerName',
      if (entry.status == MomentStatus.saving) 'saving',
      if (entry.problem == MomentProblem.photosArriving)
        'some photos are still arriving',
      if (entry.problem == MomentProblem.photosMissing)
        'some photos couldn’t be kept',
      ?entry.caption,
    ].join(', '),
  };
}

/// One square in the timeline: the moment's first photo, a count when it
/// holds more, and a quiet mark while it is saving. No social affordances.
class MomentTile extends StatelessWidget {
  const MomentTile({
    required this.entry,
    required this.size,
    required this.partnerName,
    required this.onOpen,
    super.key,
  });

  final MomentEntry entry;
  final double size;
  final String partnerName;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final entry = this.entry;
    final cover = switch (entry) {
      Moment(:final photos) when photos.isNotEmpty => MomentPhotoView(
        photo: photos.first,
        width: size,
      ),
      Moment() => const _Icon(Icons.hourglass_empty),
      UnreadableMoment() => const _Icon(Icons.image_not_supported_outlined),
    };
    return Semantics(
      button: true,
      label: momentLabel(context, entry, partnerName: partnerName),
      excludeSemantics: true,
      child: Material(
        color: context.colors.surfaceMuted,
        borderRadius: BorderRadius.circular(Radii.sm),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onOpen,
          child: SizedBox.square(
            dimension: size,
            child: Stack(
              fit: StackFit.expand,
              children: [
                cover,
                if (entry case Moment(:final photoCount) when photoCount > 1)
                  PositionedDirectional(
                    top: Spacing.xs,
                    end: Spacing.xs,
                    child: _Mark(
                      icon: Icons.photo_library_outlined,
                      text: '$photoCount',
                    ),
                  ),
                if (entry case Moment(status: MomentStatus.saving))
                  const PositionedDirectional(
                    bottom: Spacing.xs,
                    start: Spacing.xs,
                    child: _Mark(icon: Icons.cloud_upload_outlined),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Icon extends StatelessWidget {
  const _Icon(this.icon);

  final IconData icon;

  @override
  Widget build(BuildContext context) => Center(
    child: Icon(icon, size: IconSizes.md, color: context.colors.textSecondary),
  );
}

/// A small solid label over a photo; solid so it stays legible on any
/// image, in either theme.
class _Mark extends StatelessWidget {
  const _Mark({required this.icon, this.text});

  final IconData icon;
  final String? text;

  @override
  Widget build(BuildContext context) {
    final text = this.text;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: context.colors.surface,
        borderRadius: BorderRadius.circular(Radii.sm),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: Spacing.xs,
          vertical: Spacing.xxs,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: IconSizes.sm, color: context.colors.textPrimary),
            if (text != null) ...[
              const SizedBox(width: Spacing.xxs),
              Text(
                text,
                // Fixed size: it sits inside a fixed square photo.
                textScaler: TextScaler.noScaling,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: context.colors.textPrimary,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
