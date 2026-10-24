import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sirf_hum/design_system/design_system.dart';
import 'package:sirf_hum/features/moments/application/moment_photo_picker.dart';
import 'package:sirf_hum/features/moments/application/moments_controller.dart';
import 'package:sirf_hum/features/moments/domain/moments_state.dart';
import 'package:sirf_hum/features/moments/presentation/add_moment_screen.dart';
import 'package:sirf_hum/features/moments/presentation/moment_detail_screen.dart';
import 'package:sirf_hum/features/moments/presentation/moment_photo_view.dart';
import 'package:sirf_hum/features/moments/presentation/moment_tile.dart';
import 'package:sirf_hum/security/moments/moment.dart';
import 'package:sirf_hum/security/moments/moments_service.dart';
import 'package:sirf_hum/session/session_controller.dart';

/// The couple's memories (Prompt 15, D-115; visual identity v1, D-156): a
/// private timeline, newest day first, with your months as highlights. Not
/// a feed — no likes, comments, sharing or suggestions. Detail and "new
/// memory" open as pushed pages, so no moment ever appears in a URL.
class MomentsScreen extends ConsumerWidget {
  const MomentsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(momentsProvider);
    final controller = ref.read(momentsProvider.notifier);
    final names = ref.watch(pairedCoupleProvider)?.names;
    final partner = names?.partner;
    final canAdd =
        state is MomentsReady && ref.watch(momentPhotoPickerProvider) != null;

    final page = AppPage(
      title: 'Moments',
      subtitle: 'Your shared memories, in one place.',
      trailing: CoupleMark(
        yours: CoupleMark.initialOf(names?.yours),
        partner: CoupleMark.initialOf(partner),
      ),
      children: [
        const _Kinds(),
        const SizedBox(height: Spacing.xl),
        if (canAdd) ...[
          _CreateCard(onTap: () => _add(context)),
          const SizedBox(height: Spacing.xxl),
        ],
        AnimatedSwitcher(
          duration: Motion.resolve(context, Motion.standard),
          switchInCurve: Motion.enter,
          switchOutCurve: Motion.exit,
          layoutBuilder: (current, previous) => Stack(
            alignment: AlignmentDirectional.topStart,
            children: [...previous, ?current],
          ),
          child: SizedBox(
            key: ValueKey(state.runtimeType),
            width: double.infinity,
            child: _body(context, state, controller, partner ?? 'your person'),
          ),
        ),
      ],
    );
    return state is MomentsReady
        ? RefreshIndicator(onRefresh: controller.refresh, child: page)
        : page;
  }

  Widget _body(
    BuildContext context,
    MomentsState state,
    MomentsController controller,
    String partnerName,
  ) => switch (state) {
    MomentsUnavailable(:final reason) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const EmptyState(
          icon: Icons.photo_outlined,
          title: 'Your first memory is waiting.',
          message:
              'Photos from the days you want to keep, together in one '
              'place for the two of you.',
        ),
        const SizedBox(height: Spacing.xl),
        Notice(
          icon: reason == MomentsUnavailableReason.needsPhone
              ? Icons.phone_android_outlined
              : Icons.schedule_outlined,
          message: reason == MomentsUnavailableReason.needsPhone
              ? 'Moments stay private to your phones. Open them in the '
                    'Sirf Hum app.'
              : 'Saving memories opens in an upcoming version of Sirf Hum.',
        ),
      ],
    ),
    MomentsLoading() => const _TimelineSkeleton(),
    MomentsBlocked() => const ErrorState(
      title: 'Moments aren’t available on this phone.',
      message:
          'This phone is no longer one of your trusted devices, so it '
          'can’t open or add memories. Use a phone you trust.',
    ),
    MomentsFailed(:final failure) => ErrorState(
      title: 'Your moments couldn’t be opened.',
      message: failure == MomentFailure.notPaired
          ? 'This account isn’t connected to your couple right now.'
          : 'Something went wrong on this phone. Nothing was lost.',
      action: StateAction(label: 'Try again', onPressed: controller.retry),
    ),
    MomentsReady(isEmpty: true, :final notice) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const EmptyState(
          icon: Icons.photo_outlined,
          title: 'Your first memory is waiting.',
          message:
              'Choose a few photos from a day you want to keep. They’ll be '
              'here for the two of you.',
        ),
        if (notice != null) ...[
          const SizedBox(height: Spacing.xl),
          _NoticeLine(notice: notice, onRetry: controller.refresh),
        ],
      ],
    ),
    MomentsReady(:final entries, :final hasEarlier, :final notice) => _Timeline(
      entries: entries,
      hasEarlier: hasEarlier,
      notice: notice,
      partnerName: partnerName,
      onEarlier: controller.showEarlier,
      onRetry: controller.refresh,
    ),
  };

  Future<void> _add(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final outcome = await Navigator.of(context).push<MomentSaveOutcome>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => const AddMomentScreen(),
      ),
    );
    if (outcome == null) return;
    messenger.showSnackBar(
      SnackBar(
        content: Text(switch (outcome) {
          MomentSaveOutcome.saved => 'Saved. It’s here for both of you.',
          MomentSaveOutcome.savedOnPhone =>
            'Saved on this phone. It will finish when you’re back online.',
        }),
      ),
    );
  }
}

void _open(BuildContext context, MomentEntry entry) =>
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => MomentDetailScreen(entry: entry)),
    );

/// What memories can hold. Photos today; the rest say they are coming.
class _Kinds extends StatelessWidget {
  const _Kinds();

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    const kinds = [
      (null, 'All', true),
      (Icons.image_outlined, 'Photos', false),
      (Icons.videocam_outlined, 'Videos', false),
      (Icons.sticky_note_2_outlined, 'Notes', false),
      (Icons.mic_none_rounded, 'Voice', false),
    ];
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final (i, (icon, label, selected)) in kinds.indexed) ...[
            if (i > 0) const SizedBox(width: Spacing.sm),
            Semantics(
              selected: selected,
              child: ChoiceChip(
                selected: selected,
                showCheckmark: false,
                avatar: icon == null
                    ? null
                    : Icon(icon, size: IconSizes.md, color: colors.textPrimary),
                label: Text(label),
                labelStyle: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: selected ? colors.onAccent : colors.textPrimary,
                ),
                selectedColor: colors.accent,
                backgroundColor: colors.background,
                side: BorderSide(
                  color: selected ? colors.accent : colors.background,
                ),
                shape: const StadiumBorder(),
                padding: const EdgeInsets.symmetric(
                  horizontal: Spacing.md,
                  vertical: Spacing.sm,
                ),
                // All memories are photos for now: "Photos" shows the same
                // timeline; videos, notes and voice are not built yet.
                onSelected: (_) {
                  if (i <= 1) return;
                  ScaffoldMessenger.of(context)
                    ..hideCurrentSnackBar()
                    ..showSnackBar(
                      SnackBar(content: Text('$label are coming soon.')),
                    );
                },
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _CreateCard extends StatelessWidget {
  const _CreateCard({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return HeroCard(
      semanticLabel: 'Add a memory',
      onTap: onTap,
      minHeight: Spacing.xxxl * 3,
      child: Row(
        children: [
          const HeroIcon(Icons.add),
          const SizedBox(width: Spacing.lg),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Create a new memory',
                  style: textTheme.titleLarge?.copyWith(
                    color: HeroCard.textColor,
                  ),
                ),
                const SizedBox(height: Spacing.xs),
                Text(
                  'Add photos and a few words.',
                  style: textTheme.bodyLarge?.copyWith(
                    color: HeroCard.mutedTextColor,
                  ),
                ),
              ],
            ),
          ),
          const Icon(Icons.chevron_right),
        ],
      ),
    );
  }
}

class _Timeline extends StatelessWidget {
  const _Timeline({
    required this.entries,
    required this.hasEarlier,
    required this.notice,
    required this.partnerName,
    required this.onEarlier,
    required this.onRetry,
  });

  final List<MomentEntry> entries;
  final bool hasEarlier;
  final MomentsNotice? notice;
  final String partnerName;
  final VoidCallback onEarlier;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    final notice = this.notice;
    final textTheme = Theme.of(context).textTheme;
    final days = <({DateTime day, List<MomentEntry> entries})>[];
    final months = <({DateTime month, List<MomentEntry> entries})>[];
    for (final e in entries) {
      if (days.isEmpty || days.last.day != e.day) {
        days.add((day: e.day, entries: []));
      }
      days.last.entries.add(e);
      final month = DateTime(e.day.year, e.day.month);
      if (months.isEmpty || months.last.month != month) {
        months.add((month: month, entries: []));
      }
      months.last.entries.add(e);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (notice != null) ...[
          _NoticeLine(notice: notice, onRetry: onRetry),
          const SizedBox(height: Spacing.xl),
        ],
        Semantics(
          header: true,
          child: Text('Highlights', style: textTheme.titleLarge),
        ),
        const SizedBox(height: Spacing.md),
        _Highlights(months: months),
        const SizedBox(height: Spacing.xxl),
        Semantics(
          header: true,
          child: Text('Memory Timeline', style: textTheme.titleLarge),
        ),
        const SizedBox(height: Spacing.lg),
        for (final (i, day) in days.indexed)
          _Day(
            day: day.day,
            entries: day.entries,
            last: i == days.length - 1 && !hasEarlier,
            partnerName: partnerName,
          ),
        if (hasEarlier)
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: OutlinedButton(
              onPressed: onEarlier,
              child: const Text('Show earlier memories'),
            ),
          ),
      ],
    );
  }
}

/// One card per month: its newest photo, the month, how many memories.
class _Highlights extends StatelessWidget {
  const _Highlights({required this.months});

  final List<({DateTime month, List<MomentEntry> entries})> months;

  static const double _width = Spacing.xxxl * 3 + Spacing.xl;
  static const double _height = Spacing.xxxl * 4 + Spacing.xl;

  @override
  Widget build(BuildContext context) {
    final localizations = MaterialLocalizations.of(context);
    final textTheme = Theme.of(context).textTheme;
    return SizedBox(
      height: _height,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: months.length,
        separatorBuilder: (_, _) => const SizedBox(width: Spacing.md),
        itemBuilder: (context, i) {
          final m = months[i];
          final cover = [
            for (final e in m.entries)
              if (e case Moment(:final photos) when photos.isNotEmpty)
                photos.first,
          ].firstOrNull;
          final count = m.entries.length;
          final label = localizations.formatMonthYear(m.month);
          final line = count == 1 ? '1 memory' : '$count memories';
          return Semantics(
            button: true,
            label: '$label, $line',
            excludeSemantics: true,
            child: Material(
              color: context.colors.surface,
              borderRadius: BorderRadius.circular(Radii.lg),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: () => _open(context, m.entries.first),
                child: SizedBox(
                  width: _width,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      if (cover == null)
                        const DuskScene()
                      else
                        MomentPhotoView(photo: cover, width: _width),
                      // A scrim keeps the label legible on any photo.
                      DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              context.colors.background.withValues(alpha: 0),
                              context.colors.background.withValues(alpha: 0.85),
                            ],
                            stops: const [0.45, 1],
                          ),
                        ),
                      ),
                      PositionedDirectional(
                        start: Spacing.md,
                        end: Spacing.md,
                        bottom: Spacing.md,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              label,
                              style: textTheme.titleMedium?.copyWith(
                                color: HeroCard.textColor,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            Text(
                              line,
                              style: textTheme.bodyMedium?.copyWith(
                                color: HeroCard.mutedTextColor,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// One day on the timeline: a dot and the date on the rail, then each
/// memory as a photo mosaic and, when it has words, a note card.
class _Day extends StatelessWidget {
  const _Day({
    required this.day,
    required this.entries,
    required this.last,
    required this.partnerName,
  });

  final DateTime day;
  final List<MomentEntry> entries;
  final bool last;
  final String partnerName;

  static const double _rail = Spacing.xxl;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final date = MaterialLocalizations.of(context).formatMediumDate(day);
    // The rail is drawn behind the day (a line from the dot down to the
    // next day), so the day's height comes from its content alone.
    return Stack(
      children: [
        if (!last)
          PositionedDirectional(
            start: (Spacing.md - Spacing.xxs) / 2,
            top: Spacing.sm,
            bottom: 0,
            child: Container(width: Spacing.xxs, color: colors.border),
          ),
        PositionedDirectional(
          start: 0,
          top: Spacing.sm - Spacing.xxs,
          child: Container(
            width: Spacing.md,
            height: Spacing.md,
            decoration: BoxDecoration(
              color: colors.accent,
              shape: BoxShape.circle,
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsetsDirectional.only(
            start: _rail,
            bottom: Spacing.xl,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                date,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeights.medium,
                ),
              ),
              const SizedBox(height: Spacing.md),
              for (final (i, e) in entries.indexed) ...[
                if (i > 0) const SizedBox(height: Spacing.md),
                _Memory(entry: e, partnerName: partnerName),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// A memory's photos: the cover large, up to two more beside it, "+N" for
/// the rest; then its words. The cover tile carries the memory's label and
/// opens it; the smaller photos open it too but add nothing to read.
class _Memory extends StatelessWidget {
  const _Memory({required this.entry, required this.partnerName});

  final MomentEntry entry;
  final String partnerName;

  @override
  Widget build(BuildContext context) {
    final entry = this.entry;
    final photos = entry is Moment ? entry.photos : const <MomentPhoto>[];
    final count = entry is Moment ? entry.photoCount : 0;
    final caption = entry is Moment ? entry.caption : null;
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final height = (width * 0.56).clamp(0, Spacing.xxxl * 6).toDouble();
        final side = photos.length > 1;
        final sideWidth = (width - Spacing.sm) * 0.38;
        final coverWidth = side ? width - Spacing.sm - sideWidth : width;
        final extras = photos.skip(1).take(2).toList();
        final more = count - 1 - extras.length;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              height: height,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  MomentTile(
                    entry: entry,
                    size: coverWidth,
                    height: height,
                    radius: Radii.lg,
                    showCount: !side,
                    partnerName: partnerName,
                    onOpen: () => _open(context, entry),
                  ),
                  if (side) ...[
                    const SizedBox(width: Spacing.sm),
                    SizedBox(
                      width: sideWidth,
                      child: ExcludeSemantics(
                        child: Column(
                          children: [
                            for (final (i, p) in extras.indexed) ...[
                              if (i > 0) const SizedBox(height: Spacing.sm),
                              Expanded(
                                child: _Small(
                                  photo: p,
                                  width: sideWidth,
                                  more: i == extras.length - 1 && more > 0
                                      ? more
                                      : 0,
                                  onTap: () => _open(context, entry),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (caption != null && caption.isNotEmpty) ...[
              const SizedBox(height: Spacing.sm),
              _Words(caption: caption, onTap: () => _open(context, entry)),
            ],
          ],
        );
      },
    );
  }
}

class _Small extends StatelessWidget {
  const _Small({
    required this.photo,
    required this.width,
    required this.more,
    required this.onTap,
  });

  final MomentPhoto photo;
  final double width;
  final int more;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: context.colors.surfaceMuted,
    borderRadius: BorderRadius.circular(Radii.lg),
    clipBehavior: Clip.antiAlias,
    child: InkWell(
      onTap: onTap,
      child: Stack(
        fit: StackFit.expand,
        children: [
          MomentPhotoView(photo: photo, width: width),
          if (more > 0)
            ColoredBox(
              color: context.colors.background.withValues(alpha: 0.55),
              child: Center(
                child: Text(
                  '+$more',
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(color: HeroCard.textColor),
                ),
              ),
            ),
        ],
      ),
    ),
  );
}

/// A memory's words, as a quiet note card.
class _Words extends StatelessWidget {
  const _Words({required this.caption, required this.onTap});

  final String caption;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    // The cover tile already reads the caption out.
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
          padding: const EdgeInsets.all(Spacing.lg),
          child: Row(
            children: [
              Icon(
                Icons.sticky_note_2_outlined,
                color: context.colors.accent,
                size: IconSizes.md + Spacing.xs,
              ),
              const SizedBox(width: Spacing.md),
              Expanded(
                child: Text(
                  caption,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _NoticeLine extends StatelessWidget {
  const _NoticeLine({required this.notice, required this.onRetry});

  final MomentsNotice notice;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Notice(
          icon: notice == MomentsNotice.offline
              ? Icons.cloud_off_outlined
              : Icons.sync_outlined,
          message: switch (notice) {
            MomentsNotice.offline =>
              'Couldn’t check for new memories. You’re seeing what’s on '
                  'this phone.',
            MomentsNotice.connecting =>
              'Your phones aren’t connected yet. You both compare your '
                  'safety number in Us › Safety; then memories are shared.',
          },
        ),
        if (notice == MomentsNotice.offline)
          TextButton(onPressed: onRetry, child: const Text('Try again')),
      ],
    );
  }
}

/// The timeline's shape while this phone's memories load.
class _TimelineSkeleton extends StatelessWidget {
  const _TimelineSkeleton();

  @override
  Widget build(BuildContext context) {
    return Skeleton(
      label: 'Loading your memories',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SkeletonBlock.line(TypeScale.heading, widthFactor: 0.3),
          const SizedBox(height: Spacing.md),
          const SkeletonBlock(
            height: Spacing.xxxl * 4 + Spacing.xl,
            radius: Radii.lg,
          ),
          const SizedBox(height: Spacing.xxl),
          SkeletonBlock.line(TypeScale.heading, widthFactor: 0.4),
          const SizedBox(height: Spacing.md),
          const SkeletonBlock(height: Spacing.xxxl * 4, radius: Radii.lg),
        ],
      ),
    );
  }
}
