import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sirf_hum/design_system/design_system.dart';
import 'package:sirf_hum/features/moments/application/moment_photo_picker.dart';
import 'package:sirf_hum/features/moments/application/moments_controller.dart';
import 'package:sirf_hum/features/moments/domain/moments_state.dart';
import 'package:sirf_hum/features/moments/presentation/add_moment_screen.dart';
import 'package:sirf_hum/features/moments/presentation/moment_detail_screen.dart';
import 'package:sirf_hum/features/moments/presentation/moment_tile.dart';
import 'package:sirf_hum/security/moments/moment.dart';
import 'package:sirf_hum/security/moments/moments_service.dart';
import 'package:sirf_hum/session/session_controller.dart';

/// The couple's memories (Prompt 15, D-115): a private photo timeline,
/// newest first, filed by month. Not a feed — no likes, comments, sharing
/// or suggestions. Detail and "new memory" open as pushed pages, so no
/// moment ever appears in a URL.
class MomentsScreen extends ConsumerWidget {
  const MomentsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(momentsProvider);
    final controller = ref.read(momentsProvider.notifier);
    final partner = ref.watch(pairedCoupleProvider)?.names.partner;
    final canAdd =
        state is MomentsReady && ref.watch(momentPhotoPickerProvider) != null;

    final page = AppPage(
      title: 'Moments',
      subtitle: 'Your memories, just for the two of you.',
      children: [
        if (canAdd) ...[
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: FilledButton.icon(
              onPressed: () => _add(context),
              icon: const Icon(Icons.add_photo_alternate_outlined),
              label: const Text('Add a memory'),
            ),
          ),
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
    final localizations = MaterialLocalizations.of(context);
    final months = <({DateTime month, List<MomentEntry> entries})>[];
    for (final e in entries) {
      final month = DateTime(e.day.year, e.day.month);
      if (months.isEmpty || months.last.month != month) {
        months.add((month: month, entries: []));
      }
      months.last.entries.add(e);
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = WindowSize.of(context) == WindowSize.compact ? 3 : 4;
        final size =
            (constraints.maxWidth - Spacing.xs * (columns - 1)) / columns;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (notice != null) ...[
              _NoticeLine(notice: notice, onRetry: onRetry),
              const SizedBox(height: Spacing.xl),
            ],
            for (final (i, group) in months.indexed)
              AppSection(
                title: localizations.formatMonthYear(group.month),
                divider: i > 0,
                child: Wrap(
                  spacing: Spacing.xs,
                  runSpacing: Spacing.xs,
                  children: [
                    for (final e in group.entries)
                      MomentTile(
                        key: ValueKey(e.handle),
                        entry: e,
                        size: size,
                        partnerName: partnerName,
                        onOpen: () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => MomentDetailScreen(entry: e),
                          ),
                        ),
                      ),
                  ],
                ),
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
      },
    );
  }
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
              'Your phones are still connecting. New memories will appear '
                  'soon.',
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
          SkeletonBlock.line(TypeScale.label, widthFactor: 0.3),
          const SizedBox(height: Spacing.md),
          LayoutBuilder(
            builder: (context, constraints) {
              final size = (constraints.maxWidth - Spacing.xs * 2) / 3;
              return Wrap(
                spacing: Spacing.xs,
                runSpacing: Spacing.xs,
                children: [
                  for (var i = 0; i < 6; i++)
                    SizedBox.square(
                      dimension: size,
                      child: SkeletonBlock(height: size),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}
