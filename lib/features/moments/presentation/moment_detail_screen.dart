import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sirf_hum/design_system/design_system.dart';
import 'package:sirf_hum/features/moments/application/moments_controller.dart';
import 'package:sirf_hum/features/moments/domain/moments_state.dart';
import 'package:sirf_hum/features/moments/presentation/moment_photo_view.dart';
import 'package:sirf_hum/security/moments/moment.dart';
import 'package:sirf_hum/session/session_controller.dart';

/// One memory, focused: its photos, caption and dates. No social controls,
/// no identifiers, no crypto state. If the timeline stops being available
/// (sign-out, account switch, a device that lost trust) nothing private
/// stays on screen.
class MomentDetailScreen extends ConsumerWidget {
  const MomentDetailScreen({required this.entry, super.key});

  final MomentEntry entry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ready = ref.watch(momentsProvider.select((s) => s is MomentsReady));
    final partner =
        ref.watch(pairedCoupleProvider)?.names.partner ?? 'your person';
    final localizations = MaterialLocalizations.of(context);
    final entry = this.entry;

    final List<Widget> children;
    if (!ready) {
      children = const [
        ErrorState(
          title: 'This memory isn’t available right now.',
          message: 'Go back to Moments to see what’s on this phone.',
        ),
      ];
    } else {
      children = switch (entry) {
        UnreadableMoment() => const [
          ErrorState(
            title: 'This memory couldn’t be opened.',
            message:
                'It may have been added with a newer version of Sirf Hum. '
                'Updating the app may help.',
          ),
        ],
        Moment() => _moment(context, entry, partner),
      };
    }

    return Scaffold(
      appBar: AppBar(title: Text(localizations.formatMediumDate(entry.day))),
      body: AppPage(
        title: localizations.formatFullDate(entry.day),
        children: children,
      ),
    );
  }

  List<Widget> _moment(BuildContext context, Moment m, String partner) {
    final textTheme = Theme.of(context).textTheme;
    final secondary = textTheme.bodyLarge?.copyWith(
      color: context.colors.textSecondary,
    );
    final localizations = MaterialLocalizations.of(context);
    final status = switch ((m.status, m.problem)) {
      (MomentStatus.saving, _) =>
        'Saving — it will finish when you’re back online.',
      (_, MomentProblem.photosArriving) =>
        'Some photos are still on their way.',
      (_, MomentProblem.photosMissing) =>
        'Some photos couldn’t be kept on this phone.',
      _ => null,
    };
    return [
      if (m.caption case final caption?) ...[
        Text(caption, style: textTheme.bodyLarge),
        const SizedBox(height: Spacing.lg),
      ],
      Text(
        [
          m.addedByYou ? 'Added by you' : 'Added by $partner',
          localizations.formatMediumDate(m.addedAt.toLocal()),
          m.photoCount == 1 ? '1 photo' : '${m.photoCount} photos',
        ].join(' · '),
        style: secondary,
      ),
      if (status != null) ...[
        const SizedBox(height: Spacing.md),
        Notice(icon: Icons.schedule_outlined, message: status),
      ],
      const SizedBox(height: Spacing.xl),
      if (m.photos.isEmpty)
        const ErrorState(
          title: 'This memory couldn’t be opened.',
          message: 'Its photos aren’t on this phone yet.',
        ),
      LayoutBuilder(
        builder: (context, constraints) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final (i, photo) in m.photos.indexed) ...[
              if (i > 0) const SizedBox(height: Spacing.md),
              Semantics(
                image: true,
                label: 'Photo ${i + 1} of ${m.photoCount}',
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(Radii.sm),
                  child: MomentPhotoView(
                    photo: photo,
                    width: constraints.maxWidth,
                    fit: BoxFit.fitWidth,
                    detailed: true,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    ];
  }
}
