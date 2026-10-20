import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sirf_hum/design_system/design_system.dart';
import 'package:sirf_hum/features/together/application/together_clock.dart';
import 'package:sirf_hum/features/together/application/together_controller.dart';
import 'package:sirf_hum/features/together/domain/together_activity.dart';
import 'package:sirf_hum/features/together/domain/together_backend.dart';
import 'package:sirf_hum/features/together/domain/together_state.dart';
import 'package:sirf_hum/session/session_controller.dart';

/// The Together hub (Prompt 14, D-111): who you're with, what you can do,
/// and — while a session runs — exactly where it stands.
///
/// Only activities the backend supports can start. Everything else is shown
/// as coming, never as a button. Copy and actions come from [TogetherState]
/// alone; no backend error text reaches the screen.
class TogetherScreen extends ConsumerWidget {
  const TogetherScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(togetherProvider);
    final names = ref.watch(pairedCoupleProvider)?.names;
    final partner = names?.partner;
    final partnerName = partner ?? 'Your person';

    // Presence belongs to the hub; during a session the panel says it all.
    final presence = switch (state) {
      TogetherIdle(:final presence) => presence,
      TogetherUnavailable() => PartnerPresence.unavailable,
      _ => null,
    };

    return AppPage(
      title: 'Together',
      subtitle: 'Spend time together, wherever you are.',
      children: [
        _PartnerRow(yours: names?.yours, partner: partner, presence: presence),
        const SizedBox(height: Spacing.xxl),
        AnimatedSwitcher(
          duration: Motion.resolve(context, Motion.standard),
          switchInCurve: Motion.enter,
          switchOutCurve: Motion.exit,
          // Full content width, top-aligned: the default switcher layout
          // centres and shrink-wraps.
          layoutBuilder: (current, previous) => Stack(
            alignment: AlignmentDirectional.topStart,
            children: [...previous, ?current],
          ),
          child: SizedBox(
            key: ValueKey(state.runtimeType),
            width: double.infinity,
            child: _body(context, ref, state, partnerName),
          ),
        ),
      ],
    );
  }

  Widget _body(
    BuildContext context,
    WidgetRef ref,
    TogetherState state,
    String partnerName,
  ) {
    final controller = ref.read(togetherProvider.notifier);
    return switch (state) {
      TogetherUnavailable(:final reason) => _Activities(
        supported: const {},
        onStart: null,
        notice: switch (reason) {
          TogetherUnavailableReason.needsPhone => const Notice(
            icon: Icons.phone_android_outlined,
            message:
                'Time together happens in the Sirf Hum app on your phone, '
                'where your keys live.',
          ),
          TogetherUnavailableReason.notYetAvailable ||
          TogetherUnavailableReason.notPaired => const Notice(
            icon: Icons.schedule_outlined,
            message: 'Together opens in an upcoming version of Sirf Hum.',
          ),
        },
      ),
      TogetherLoading() => const Skeleton(
        label: 'Loading Together',
        child: Column(
          children: [
            SkeletonBlock(height: TouchTargets.comfortable),
            SizedBox(height: Spacing.md),
            SkeletonBlock(height: TouchTargets.comfortable),
          ],
        ),
      ),
      TogetherIdle(:final supported) => _Activities(
        supported: supported,
        onStart: controller.start,
      ),
      TogetherStarting(:final activity) => _SessionPanel(
        title: 'Starting ${_lower(activity)}…',
        message: 'Just a moment.',
        busy: true,
      ),
      TogetherWaiting() => _SessionPanel(
        title: 'Waiting for $partnerName…',
        message:
            '$partnerName can join from Together. You’ll be together as '
            'soon as they do.',
        secondary: StateAction(label: 'Cancel', onPressed: controller.leave),
      ),
      TogetherInvited(:final activity) => _SessionPanel(
        title: '$partnerName wants some ${_lower(activity)}.',
        message: 'Join whenever you’re ready.',
        primary: StateAction(label: 'Join', onPressed: controller.join),
        secondary: StateAction(label: 'Not now', onPressed: controller.leave),
      ),
      TogetherJoining() => const _SessionPanel(
        title: 'Joining…',
        message: 'Just a moment.',
        busy: true,
      ),
      TogetherActive(:final since) => _SessionPanel(
        title: 'You’re together.',
        message: 'You and $partnerName, right now.',
        showClock: true,
        clockSince: since,
        secondary: StateAction(
          label: 'End together',
          onPressed: controller.leave,
        ),
      ),
      TogetherEnding() => const _SessionPanel(
        title: 'Ending…',
        message: 'Just a moment.',
        busy: true,
      ),
      TogetherEnded(:final activity, :final reason) => _SessionPanel(
        title: '${activity.label} ended.',
        message: switch (reason) {
          TogetherEndReason.left => 'You ended it.',
          TogetherEndReason.partnerLeft => '$partnerName left.',
          TogetherEndReason.expired => 'It timed out.',
        },
        primary: StateAction(
          label: 'Back to Together',
          onPressed: controller.dismiss,
        ),
      ),
      TogetherFailed(:final failure) => _failure(ref, failure),
    };
  }

  Widget _failure(WidgetRef ref, TogetherFailure failure) {
    final retry = StateAction(
      label: 'Try again',
      onPressed: ref.read(togetherProvider.notifier).retry,
    );
    final (title, message, action) = switch (failure) {
      TogetherFailure.unavailable => (
        'We couldn’t reach Sirf Hum.',
        'Check your connection, then try again.',
        retry,
      ),
      TogetherFailure.startRefused => (
        'That didn’t start.',
        'Try again in a moment.',
        retry,
      ),
      TogetherFailure.sessionGone => (
        'That time together has ended.',
        'You can start a new one.',
        retry,
      ),
      TogetherFailure.deviceNotTrusted => (
        'This phone can’t join Together.',
        'It isn’t a trusted device for your account right now.',
        null,
      ),
      TogetherFailure.notPaired => (
        'Together needs the two of you.',
        'We’re checking your couple again.',
        StateAction(
          label: 'Check again',
          onPressed: ref.read(sessionProvider.notifier).refresh,
        ),
      ),
      TogetherFailure.unexpected => (
        'Something didn’t look right.',
        'Nothing was shared. Try again.',
        retry,
      ),
    };
    return ErrorState(title: title, message: message, action: action);
  }

  static String _lower(TogetherActivity activity) =>
      activity.label.toLowerCase();
}

class _PartnerRow extends StatelessWidget {
  const _PartnerRow({
    required this.yours,
    required this.partner,
    required this.presence,
  });

  final String? yours;
  final String? partner;

  /// Null outside the idle hub, where presence is not the point.
  final PartnerPresence? presence;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final name = partner ?? 'Your person';
    final presence = this.presence;
    // Shape and words carry the meaning, never colour alone.
    final (icon, text) = switch (presence) {
      null => (null, null),
      PartnerPresence.unavailable => (
        Icons.remove_circle_outline,
        'Presence isn’t shared yet',
      ),
      PartnerPresence.online => (Icons.circle, '$name is here'),
      PartnerPresence.away => (Icons.dark_mode_outlined, '$name is away'),
      PartnerPresence.offline => (
        Icons.circle_outlined,
        '$name isn’t around right now',
      ),
      PartnerPresence.inActivity => (
        Icons.timelapse,
        '$name is in time together',
      ),
    };
    return MergeSemantics(
      child: Row(
        children: [
          CoupleMark(
            yours: CoupleMark.initialOf(yours),
            partner: CoupleMark.initialOf(partner),
          ),
          const SizedBox(width: Spacing.lg),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name, style: textTheme.titleMedium),
                if (icon != null && text != null) ...[
                  const SizedBox(height: Spacing.xxs),
                  Row(
                    children: [
                      ExcludeSemantics(
                        child: Icon(
                          icon,
                          size: IconSizes.sm,
                          color: presence == PartnerPresence.online
                              ? context.colors.success
                              : context.colors.textSecondary,
                        ),
                      ),
                      const SizedBox(width: Spacing.xs),
                      Expanded(
                        child: Text(
                          text,
                          style: textTheme.bodyMedium?.copyWith(
                            color: context.colors.textSecondary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The choices. Only [supported] activities get a button.
class _Activities extends StatelessWidget {
  const _Activities({
    required this.supported,
    required this.onStart,
    this.notice,
  });

  final Set<TogetherActivity> supported;
  final void Function(TogetherActivity)? onStart;
  final Widget? notice;

  @override
  Widget build(BuildContext context) {
    final notice = this.notice;
    return AppSection(
      title: 'What do you want to do?',
      divider: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final (i, activity) in TogetherActivity.values.indexed) ...[
            if (i > 0) const Divider(height: Spacing.xl),
            _ActivityRow(
              activity: activity,
              onStart: supported.contains(activity) && onStart != null
                  ? () => onStart!(activity)
                  : null,
            ),
          ],
          if (notice != null) ...[const SizedBox(height: Spacing.xl), notice],
        ],
      ),
    );
  }
}

class _ActivityRow extends StatelessWidget {
  const _ActivityRow({required this.activity, required this.onStart});

  final TogetherActivity activity;
  final VoidCallback? onStart;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final onStart = this.onStart;
    final muted = context.colors.textSecondary;
    return Row(
      children: [
        Expanded(
          child: MergeSemantics(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  activity.label,
                  style: textTheme.titleMedium?.copyWith(
                    color: onStart == null ? muted : null,
                  ),
                ),
                const SizedBox(height: Spacing.xxs),
                Text(
                  activity.description,
                  style: textTheme.bodyMedium?.copyWith(color: muted),
                ),
                if (onStart == null) ...[
                  const SizedBox(height: Spacing.xxs),
                  Text(
                    activity == TogetherActivity.timeTogether
                        ? 'Not available yet'
                        : 'Coming soon',
                    style: textTheme.labelMedium?.copyWith(color: muted),
                  ),
                ],
              ],
            ),
          ),
        ),
        if (onStart != null) ...[
          const SizedBox(width: Spacing.lg),
          FilledButton(
            onPressed: onStart,
            child: Semantics(
              label: 'Start ${activity.label.toLowerCase()}',
              excludeSemantics: true,
              child: const Text('Start'),
            ),
          ),
        ],
      ],
    );
  }
}

/// A running or changing session: what is happening, and what you can do.
class _SessionPanel extends StatelessWidget {
  const _SessionPanel({
    required this.title,
    required this.message,
    this.primary,
    this.secondary,
    this.busy = false,
    this.showClock = false,
    this.clockSince,
  });

  final String title;
  final String message;
  final StateAction? primary;
  final StateAction? secondary;
  final bool busy;

  /// Shows how long you've been together, from [clockSince] when the
  /// server said.
  final bool showClock;
  final DateTime? clockSince;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final primary = this.primary;
    final secondary = this.secondary;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: context.colors.surfaceMuted,
        borderRadius: BorderRadius.circular(Radii.lg),
      ),
      child: Padding(
        padding: const EdgeInsets.all(Spacing.xl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            MergeSemantics(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Semantics(
                    liveRegion: true,
                    child: Text(title, style: textTheme.titleLarge),
                  ),
                  const SizedBox(height: Spacing.sm),
                  Text(
                    message,
                    style: textTheme.bodyLarge?.copyWith(
                      color: context.colors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            if (showClock) ...[
              const SizedBox(height: Spacing.xl),
              _TogetherClock(since: clockSince),
            ],
            if (busy) ...[
              const SizedBox(height: Spacing.xl),
              Semantics(
                label: 'Working',
                child: LinearProgressIndicator(
                  color: context.colors.accent,
                  backgroundColor: context.colors.border,
                ),
              ),
            ],
            if (primary != null || secondary != null) ...[
              const SizedBox(height: Spacing.xl),
              Wrap(
                spacing: Spacing.sm,
                runSpacing: Spacing.sm,
                children: [
                  if (primary != null)
                    FilledButton(
                      onPressed: primary.onPressed,
                      child: Text(primary.label),
                    ),
                  if (secondary != null)
                    OutlinedButton(
                      onPressed: secondary.onPressed,
                      child: Text(secondary.label),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// "12:03" since [since] (server time), or since this screen saw the session
/// start when the server has not said. Never negative.
class _TogetherClock extends ConsumerStatefulWidget {
  const _TogetherClock({required this.since});

  final DateTime? since;

  @override
  ConsumerState<_TogetherClock> createState() => _TogetherClockState();
}

class _TogetherClockState extends ConsumerState<_TogetherClock> {
  late final DateTime _seenAt;
  late final Timer _tick;

  @override
  void initState() {
    super.initState();
    _seenAt = ref.read(togetherClockProvider)();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) => setState(() {}));
  }

  @override
  void dispose() {
    _tick.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final now = ref.read(togetherClockProvider)();
    final from = widget.since?.toLocal() ?? _seenAt;
    final elapsed = now.isBefore(from) ? Duration.zero : now.difference(from);
    final minutes = elapsed.inMinutes;
    final hours = elapsed.inHours;
    String two(int n) => n.toString().padLeft(2, '0');
    final text = hours > 0
        ? '$hours:${two(minutes % 60)}:${two(elapsed.inSeconds % 60)}'
        : '${two(minutes)}:${two(elapsed.inSeconds % 60)}';
    // Read out in words, not digits every second.
    return Semantics(
      label: minutes == 0
          ? 'Together for less than a minute'
          : 'Together for $minutes minute${minutes == 1 ? '' : 's'}',
      excludeSemantics: true,
      child: Text(
        text,
        style: Theme.of(context).textTheme.displaySmall?.copyWith(
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
    );
  }
}
