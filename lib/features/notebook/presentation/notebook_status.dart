import 'package:flutter/material.dart';
import 'package:sirf_hum/design_system/design_system.dart';
import 'package:sirf_hum/features/notebook/application/notebook_controller.dart';
import 'package:sirf_hum/features/notebook/domain/notebook_state.dart';
import 'package:sirf_hum/security/notebook/notebook_service.dart';

/// Every notebook state except [NotebookReady], the same way in Future and
/// Us. [empty] is the area's own empty state, shown above an honest notice
/// while nothing can be kept yet.
class NotebookStatusView extends StatelessWidget {
  const NotebookStatusView({
    required this.state,
    required this.controller,
    required this.empty,
    required this.areaName,
    super.key,
  });

  final NotebookState state;
  final NotebookController controller;
  final Widget empty;

  /// "Future" or "Us", for the copy.
  final String areaName;

  @override
  Widget build(BuildContext context) => switch (state) {
    NotebookUnavailable(:final reason) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        empty,
        const SizedBox(height: Spacing.xl),
        Notice(
          icon: reason == NotebookUnavailableReason.needsPhone
              ? Icons.phone_android_outlined
              : Icons.schedule_outlined,
          message: reason == NotebookUnavailableReason.needsPhone
              ? '$areaName stays private to your phones. Open it in the '
                    'Sirf Hum app.'
              : 'Saving to $areaName opens in an upcoming version of Sirf '
                    'Hum.',
        ),
      ],
    ),
    NotebookLoading() => const NotebookSkeleton(),
    NotebookBlocked() => ErrorState(
      title: '$areaName isn’t available on this phone.',
      message:
          'This phone is no longer one of your trusted devices, so it can’t '
          'open or change what you’ve saved together. Use a phone you trust.',
    ),
    NotebookFailed(:final failure) => ErrorState(
      title: '$areaName couldn’t be opened.',
      message: failure == NotebookFailure.notPaired
          ? 'This account isn’t connected to your couple right now.'
          : 'Something went wrong on this phone. Nothing was lost.',
      action: StateAction(label: 'Try again', onPressed: controller.retry),
    ),
    NotebookReady() => const SizedBox.shrink(),
  };
}

/// Why the newest changes might be missing, and anything that could not be
/// opened. Nothing when all is well.
class NotebookNotices extends StatelessWidget {
  const NotebookNotices({
    required this.state,
    required this.onRetry,
    super.key,
  });

  final NotebookReady state;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    final notice = state.notice;
    final unreadable = state.snapshot.unreadable;
    if (notice == null && unreadable == 0) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: Spacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (notice != null) ...[
            Notice(
              icon: notice == NotebookNotice.offline
                  ? Icons.cloud_off_outlined
                  : Icons.sync_outlined,
              message: switch (notice) {
                NotebookNotice.offline =>
                  'Couldn’t check for changes. You’re seeing what’s on this '
                      'phone.',
                NotebookNotice.connecting =>
                  'Your phones aren’t connected yet. You both compare your '
                      'safety number in Us › Safety; then changes are shared.',
              },
            ),
            if (notice == NotebookNotice.offline)
              TextButton(onPressed: onRetry, child: const Text('Try again')),
          ],
          if (unreadable > 0) ...[
            if (notice != null) const SizedBox(height: Spacing.sm),
            Notice(
              icon: Icons.help_outline,
              message: unreadable == 1
                  ? 'One change couldn’t be opened on this phone.'
                  : '$unreadable changes couldn’t be opened on this phone.',
            ),
          ],
        ],
      ),
    );
  }
}

/// The shape of a list while this phone's notebook loads.
class NotebookSkeleton extends StatelessWidget {
  const NotebookSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return Skeleton(
      label: 'Loading',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < 3; i++) ...[
            SkeletonBlock.line(TypeScale.label, widthFactor: 0.3),
            const SizedBox(height: Spacing.md),
            SkeletonBlock.line(TypeScale.body, widthFactor: 0.8),
            const SizedBox(height: Spacing.sm),
            SkeletonBlock.line(TypeScale.body, widthFactor: 0.6),
            const SizedBox(height: Spacing.xl),
          ],
        ],
      ),
    );
  }
}
