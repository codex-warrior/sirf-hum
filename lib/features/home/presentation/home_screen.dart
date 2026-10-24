import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sirf_hum/design_system/design_system.dart';
import 'package:sirf_hum/features/future/domain/future_sections.dart';
import 'package:sirf_hum/features/home/application/home_providers.dart';
import 'package:sirf_hum/features/home/domain/greeting.dart';
import 'package:sirf_hum/features/moments/application/moments_controller.dart';
import 'package:sirf_hum/features/moments/domain/moments_state.dart';
import 'package:sirf_hum/features/notebook/application/notebook_controller.dart';
import 'package:sirf_hum/features/notebook/domain/notebook_state.dart';
import 'package:sirf_hum/features/phone_setup/presentation/phone_setup_screen.dart';
import 'package:sirf_hum/security/couple/couple_profiles.dart';
import 'package:sirf_hum/security/moments/moment.dart';
import 'package:sirf_hum/security/moments/moment_payload.dart';
import 'package:sirf_hum/security/notebook/notebook.dart';
import 'package:sirf_hum/security/notebook/notebook_payload.dart';
import 'package:sirf_hum/session/private_services.dart';
import 'package:sirf_hum/session/session_controller.dart';

/// The couple's front door (PRODUCT-CONSTITUTION §4; visual identity v1,
/// D-156): how long you've been together, things to do, your memories,
/// your space and what's next.
///
/// Every number is real: days come from the "together since" date in Us,
/// memories from this phone's timeline. Nothing is sample data; what is not
/// set yet invites you to set it.
///
/// Navigation is passed in, so Home does not depend on the router.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({
    required this.onOpenTogether,
    required this.onOpenMoments,
    required this.onOpenFuture,
    required this.onOpenUs,
    super.key,
  });

  final VoidCallback onOpenTogether;
  final VoidCallback onOpenMoments;
  final VoidCallback onOpenFuture;
  final VoidCallback onOpenUs;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // The router only opens Home for a paired session; before that answer
    // arrives (or if it changes) nothing about the couple is shown.
    final couple = ref.watch(pairedCoupleProvider);
    if (couple == null) return const HomeSkeleton();

    final now = ref.watch(homeClockProvider)();
    final privateHere = ref.watch(privateContentAvailableProvider);
    final needsSetup =
        ref.watch(privateServicesStatusProvider) ==
        PrivateServicesStatus.needsSetup;
    final moments = ref.watch(momentsProvider);
    final notebook = ref.watch(notebookProvider);
    final ready = notebook is NotebookReady ? notebook : null;
    final today = MomentDate.of(now);
    final next = ready == null
        ? null
        : FutureSections.of(
            ready.snapshot.section(NotebookSection.future),
            today,
          ).next;
    final since = ready?.snapshot
        .section(NotebookSection.togetherSince)
        .lastOrNull
        ?.date;

    return AppPage(
      header: _Header(
        greeting: greetingFor(now),
        names: couple.names,
        onAddName: onOpenUs,
      ),
      children: [
        if (needsSetup) ...[
          const _SetUpPhone(),
          const SizedBox(height: Spacing.lg),
        ],
        _SinceCard(since: since, today: now, onOpen: onOpenUs),
        const SizedBox(height: Spacing.lg),
        _Activities(onOpen: onOpenTogether),
        const SizedBox(height: Spacing.xl),
        const Divider(height: 1),
        const SizedBox(height: Spacing.md),
        _MomentsRow(state: moments, onOpen: onOpenMoments),
        const SizedBox(height: Spacing.md),
        _RowCard(
          icon: Icons.filter_none_rounded,
          title: 'Our Space',
          subtitle: 'Your story, little things, rituals and more.',
          onTap: onOpenUs,
        ),
        const SizedBox(height: Spacing.xl),
        _Today(next: next, onAll: onOpenFuture, onPlan: onOpenFuture),
        if (!privateHere) ...[
          const SizedBox(height: Spacing.xl),
          const Notice(
            icon: Icons.phone_android_outlined,
            message:
                'Private messages, calls and moments open in the Sirf Hum '
                'app on your phone.',
          ),
        ],
      ],
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.greeting,
    required this.names,
    required this.onAddName,
  });

  final String greeting;
  final CoupleNames names;

  /// While you have no name, a quiet way to add one (in Us).
  final VoidCallback onAddName;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const SirfHumMark(size: IconSizes.lg + Spacing.sm),
            const SizedBox(width: Spacing.md),
            Expanded(
              child: ExcludeSemantics(
                child: Text('Sirf Hum', style: textTheme.titleLarge),
              ),
            ),
            CoupleMark(
              yours: CoupleMark.initialOf(names.yours),
              partner: CoupleMark.initialOf(names.partner),
            ),
          ],
        ),
        const SizedBox(height: Spacing.xxl),
        Text(
          '$greeting,',
          style: textTheme.bodyLarge?.copyWith(
            color: context.colors.textSecondary,
          ),
        ),
        const SizedBox(height: Spacing.xs),
        Semantics(
          header: true,
          child: Text('${coupleTitle(names)}.', style: textTheme.displaySmall),
        ),
        if (names.yours == null)
          TextButton.icon(
            style: TextButton.styleFrom(padding: EdgeInsets.zero),
            onPressed: onAddName,
            icon: const Icon(Icons.edit_outlined, size: IconSizes.sm),
            label: const Text('Add your name'),
          ),
      ],
    );
  }
}

/// This phone must be set up again (D-159): the one thing to do first.
class _SetUpPhone extends StatelessWidget {
  const _SetUpPhone();

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: context.colors.surface,
        borderRadius: BorderRadius.circular(Radii.lg),
        border: Border.all(color: context.colors.accent),
      ),
      child: Padding(
        padding: const EdgeInsets.all(Spacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Set up this phone', style: textTheme.titleMedium),
            const SizedBox(height: Spacing.xs),
            Text(
              'Sirf Hum was reinstalled here. Set it up again to open your '
              'memories and plans.',
              style: textTheme.bodyMedium?.copyWith(
                color: context.colors.textSecondary,
              ),
            ),
            const SizedBox(height: Spacing.md),
            OutlinedButton(
              onPressed: () => openPhoneSetup(context),
              child: const Text('Set up'),
            ),
          ],
        ),
      ),
    );
  }
}

/// "Together for 421 days", from the date in Us; an invitation to add it
/// when there is none.
class _SinceCard extends StatelessWidget {
  const _SinceCard({
    required this.since,
    required this.today,
    required this.onOpen,
  });

  final MomentDate? since;
  final DateTime today;
  final VoidCallback onOpen;

  /// Whole days since [since] (the day itself is day 0). Never negative.
  static int daysSince(MomentDate since, DateTime today) {
    final from = DateTime.utc(since.year, since.month, since.day);
    final to = DateTime.utc(today.year, today.month, today.day);
    final days = to.difference(from).inDays;
    return days < 0 ? 0 : days;
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final since = this.since;
    final days = since == null ? null : daysSince(since, today);
    final (eyebrow, headline) = days == null
        ? ('Together since', 'Add your day')
        : ('Together for', days == 1 ? '1 day' : '$days days');
    return HeroCard(
      semanticLabel: '$eyebrow $headline',
      onTap: onOpen,
      child: Align(
        alignment: AlignmentDirectional.bottomStart,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: Spacing.xxxl),
            Text(
              eyebrow,
              style: textTheme.bodyLarge?.copyWith(
                color: HeroCard.mutedTextColor,
              ),
            ),
            const SizedBox(height: Spacing.xs),
            Row(
              children: [
                Flexible(
                  child: Text(
                    headline,
                    style: textTheme.displaySmall?.copyWith(
                      color: HeroCard.textColor,
                    ),
                  ),
                ),
                const SizedBox(width: Spacing.sm),
                const Icon(Icons.chevron_right, size: IconSizes.lg),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Watch, Listen, Call, Play: each opens Together, which says what is ready.
class _Activities extends StatelessWidget {
  const _Activities({required this.onOpen});

  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    const items = [
      (Icons.play_arrow_outlined, 'Watch'),
      (Icons.headphones_outlined, 'Listen'),
      (Icons.videocam_outlined, 'Call'),
      (Icons.sports_esports_outlined, 'Play'),
    ];
    return Row(
      children: [
        for (final (i, (icon, label)) in items.indexed) ...[
          if (i > 0) const SizedBox(width: Spacing.sm),
          Expanded(
            child: ActionTile(
              icon: icon,
              label: label,
              onTap: onOpen,
              height: Spacing.xxxl * 2 + Spacing.md,
            ),
          ),
        ],
      ],
    );
  }
}

/// Two of your latest photos, tilted like prints, beside the count.
class _MomentsRow extends StatelessWidget {
  const _MomentsRow({required this.state, required this.onOpen});

  final MomentsState state;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final ready = state is MomentsReady ? state as MomentsReady : null;
    final total = ready?.total ?? 0;
    final covers = [
      for (final e in ready?.entries ?? const <MomentEntry>[])
        if (e case Moment(:final photos) when photos.isNotEmpty) photos.first,
    ].take(2).toList();
    final subtitle = switch (total) {
      0 => 'Your first memory is waiting.',
      1 => '1 memory',
      _ => '${MaterialLocalizations.of(context).formatDecimal(total)} memories',
    };
    return Semantics(
      button: true,
      label: 'Your Moments, $subtitle',
      excludeSemantics: true,
      child: InkWell(
        onTap: onOpen,
        borderRadius: BorderRadius.circular(Radii.lg),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: Spacing.md),
          child: Row(
            children: [
              _Prints(covers: covers),
              const SizedBox(width: Spacing.xl),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Your Moments', style: textTheme.titleLarge),
                    const SizedBox(height: Spacing.xs),
                    Text(
                      subtitle,
                      style: textTheme.bodyLarge?.copyWith(
                        color: context.colors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right),
            ],
          ),
        ),
      ),
    );
  }
}

class _Prints extends StatelessWidget {
  const _Prints({required this.covers});

  final List<MomentPhoto> covers;

  static const double _print = TouchTargets.comfortable + Spacing.lg;

  @override
  Widget build(BuildContext context) {
    Widget print(int i, double turns) {
      final photo = i < covers.length ? covers[i] : null;
      return RotationTransition(
        turns: AlwaysStoppedAnimation(turns),
        child: Container(
          width: _print,
          height: _print,
          padding: const EdgeInsets.all(Spacing.xxs),
          decoration: BoxDecoration(
            color: context.colors.textPrimary,
            borderRadius: BorderRadius.circular(Radii.sm),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(Radii.sm - Spacing.xxs),
            child: photo == null
                ? const DuskScene()
                : _Cover(photo: photo, width: _print),
          ),
        ),
      );
    }

    return ExcludeSemantics(
      child: SizedBox(
        width: _print * 2 - Spacing.md,
        height: _print + Spacing.md,
        child: Stack(
          alignment: Alignment.center,
          children: [
            PositionedDirectional(start: 0, child: print(1, -0.025)),
            PositionedDirectional(
              start: _print - Spacing.lg,
              child: print(0, 0.025),
            ),
          ],
        ),
      ),
    );
  }
}

/// A decrypted cover photo (memory only, like every moment photo, D-115);
/// the dusk scene while it opens or if it cannot.
class _Cover extends ConsumerWidget {
  const _Cover({required this.photo, required this.width});

  final MomentPhoto photo;
  final double width;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pixels = (width * MediaQuery.devicePixelRatioOf(context)).round();
    return switch (ref.watch(momentPhotoProvider(photo))) {
      AsyncData(:final value) => Image.memory(
        value,
        fit: BoxFit.cover,
        cacheWidth: pixels > 0 ? pixels : null,
        gaplessPlayback: true,
        excludeFromSemantics: true,
        errorBuilder: (_, _, _) => const DuskScene(),
      ),
      _ => const DuskScene(),
    };
  }
}

/// A full-width soft card: icon, title, one line, chevron.
class _RowCard extends StatelessWidget {
  const _RowCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Semantics(
      button: true,
      label: '$title, $subtitle',
      excludeSemantics: true,
      child: Material(
        color: context.colors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Radii.lg),
          side: BorderSide(color: context.colors.surfaceMuted),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(Spacing.xl),
            child: Row(
              children: [
                Icon(icon, size: IconSizes.lg, color: context.colors.accent),
                const SizedBox(width: Spacing.xl),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: textTheme.titleLarge),
                      const SizedBox(height: Spacing.xs),
                      Text(
                        subtitle,
                        style: textTheme.bodyMedium?.copyWith(
                          color: context.colors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The soonest plan ahead, or an invitation to make one. "+ Plan" is the
/// screen's one filled (primary) action.
class _Today extends StatelessWidget {
  const _Today({required this.next, required this.onAll, required this.onPlan});

  final NotebookEntry? next;
  final VoidCallback onAll;
  final VoidCallback onPlan;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final next = this.next;
    final date = next?.date;
    final (title, line) = next == null || date == null
        ? ('No plans yet.', 'Make one together.')
        : (
            next.title,
            MaterialLocalizations.of(context).formatMediumDate(date.toLocal()),
          );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Semantics(
                header: true,
                child: Text('Coming up', style: textTheme.titleLarge),
              ),
            ),
            TextButton(onPressed: onAll, child: const Text('View all')),
          ],
        ),
        const SizedBox(height: Spacing.sm),
        DecoratedBox(
          decoration: BoxDecoration(
            color: context.colors.surface,
            borderRadius: BorderRadius.circular(Radii.lg),
            border: Border.all(color: context.colors.surfaceMuted),
          ),
          child: Padding(
            padding: const EdgeInsets.all(Spacing.xl),
            child: Row(
              children: [
                Icon(
                  Icons.event_outlined,
                  size: IconSizes.lg,
                  color: context.colors.accent,
                ),
                const SizedBox(width: Spacing.lg),
                Expanded(
                  child: MergeSemantics(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(title, style: textTheme.titleMedium),
                        const SizedBox(height: Spacing.xxs),
                        Text(
                          line,
                          style: textTheme.bodyMedium?.copyWith(
                            color: context.colors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: Spacing.sm),
                FilledButton(
                  onPressed: onPlan,
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(
                      TouchTargets.minimum,
                      TouchTargets.minimum,
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: Spacing.lg),
                    shape: const StadiumBorder(),
                  ),
                  child: const Text('+ Plan'),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Home's shape while the session is still being established, so the screen
/// does not jump when it arrives. Also used by the start screen.
class HomeSkeleton extends StatelessWidget {
  const HomeSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return AppPage(
      children: [
        Skeleton(
          label: 'Opening Sirf Hum',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SkeletonBlock(
                height: TouchTargets.comfortable,
                widthFactor: 0.3,
                radius: Radii.pill,
              ),
              const SizedBox(height: Spacing.xl),
              SkeletonBlock.line(TypeScale.body, widthFactor: 0.35),
              const SizedBox(height: Spacing.xs),
              SkeletonBlock.line(TypeScale.display, widthFactor: 0.7),
              const SizedBox(height: Spacing.xxl),
              const SkeletonBlock(
                height: Spacing.xxxl * 3 + Spacing.xl,
                radius: Radii.xl,
              ),
              const SizedBox(height: Spacing.lg),
              const SkeletonBlock(
                height: Spacing.xxxl * 2 + Spacing.md,
                radius: Radii.lg,
              ),
            ],
          ),
        ),
      ],
    );
  }
}
