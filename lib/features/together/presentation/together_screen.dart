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

/// The Together hub (Prompt 14, D-111; visual identity v1, D-156): things to
/// do together and, while a session runs, exactly where it stands.
///
/// Only activities the backend supports can start. Watch, Listen, Call and
/// Play carry a "Soon" mark and say so when tapped; they never pretend to
/// start. Copy and actions come from [TogetherState] alone; no backend error
/// text reaches the screen.
class TogetherScreen extends ConsumerWidget {
  const TogetherScreen({
    required this.onOpenFuture,
    required this.onOpenUs,
    super.key,
  });

  final VoidCallback onOpenFuture;
  final VoidCallback onOpenUs;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(togetherProvider);
    final names = ref.watch(pairedCoupleProvider)?.names;
    final partner = names?.partner;
    final partnerName = partner ?? 'Your person';

    return AppPage(
      title: 'Together',
      subtitle: 'Things to do, together.',
      trailing: CoupleMark(
        yours: CoupleMark.initialOf(names?.yours),
        partner: CoupleMark.initialOf(partner),
      ),
      children: [
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
      TogetherUnavailable(:final reason) => _Hub(
        supported: const {},
        onStart: null,
        presence: null,
        partnerName: partnerName,
        onOpenFuture: onOpenFuture,
        onOpenUs: onOpenUs,
        notice: switch (reason) {
          TogetherUnavailableReason.needsPhone => const Notice(
            icon: Icons.phone_android_outlined,
            message:
                'Time together happens in the Sirf Hum app on your phone, '
                'where your keys live.',
          ),
          TogetherUnavailableReason.notYetAvailable ||
          TogetherUnavailableReason.notPaired => null,
        },
      ),
      TogetherLoading() => const Skeleton(
        label: 'Loading Together',
        child: Column(
          children: [
            SkeletonBlock(
              height: Spacing.xxxl * 3 + Spacing.xl,
              radius: Radii.xl,
            ),
            SizedBox(height: Spacing.md),
            SkeletonBlock(height: Spacing.xxxl * 2 + Spacing.lg),
          ],
        ),
      ),
      TogetherIdle(:final supported, :final presence) => _Hub(
        supported: supported,
        onStart: controller.start,
        presence: presence,
        partnerName: partnerName,
        onOpenFuture: onOpenFuture,
        onOpenUs: onOpenUs,
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

/// The idle hub: one hero choice, then six tiles.
class _Hub extends StatelessWidget {
  const _Hub({
    required this.supported,
    required this.onStart,
    required this.presence,
    required this.partnerName,
    required this.onOpenFuture,
    required this.onOpenUs,
    this.notice,
  });

  final Set<TogetherActivity> supported;
  final void Function(TogetherActivity)? onStart;

  /// Null when unknown (unavailable): nothing is said about the partner.
  final PartnerPresence? presence;
  final String partnerName;
  final VoidCallback onOpenFuture;
  final VoidCallback onOpenUs;
  final Widget? notice;

  @override
  Widget build(BuildContext context) {
    final onStart = this.onStart;
    bool startable(TogetherActivity a) =>
        onStart != null && supported.contains(a);
    void tap(TogetherActivity activity, String name) =>
        startable(activity) ? onStart!(activity) : showSoonSheet(context, name);
    String? soon(TogetherActivity a) => startable(a) ? null : 'Soon';
    final presenceLine = _presenceLine(presence, partnerName);
    final notice = this.notice;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (presenceLine != null) ...[
          presenceLine,
          const SizedBox(height: Spacing.lg),
        ],
        if (startable(TogetherActivity.timeTogether))
          _HeroChoice(
            icon: Icons.favorite_outline,
            title: 'Spend time together',
            subtitle: TogetherActivity.timeTogether.description,
            onTap: () => onStart!(TogetherActivity.timeTogether),
          )
        else
          _HeroChoice(
            icon: Icons.play_arrow_rounded,
            title: 'Start a Watch Together',
            subtitle: 'Movies, shows and more.',
            badge: soon(TogetherActivity.watch),
            onTap: () => tap(TogetherActivity.watch, 'Watch Together'),
          ),
        const SizedBox(height: Spacing.md),
        _Grid(
          tiles: [
            ActionTile(
              icon: Icons.headphones_outlined,
              label: 'Listen Together',
              badge: soon(TogetherActivity.listen),
              onTap: () => tap(TogetherActivity.listen, 'Listen Together'),
            ),
            ActionTile(
              icon: Icons.videocam_outlined,
              label: 'Call',
              badge: soon(TogetherActivity.call),
              onTap: () => tap(TogetherActivity.call, 'Calling'),
            ),
            ActionTile(
              icon: Icons.sports_esports_outlined,
              label: 'Play',
              badge: 'Soon',
              onTap: () => showSoonSheet(context, 'Playing together'),
            ),
            ActionTile(
              icon: Icons.edit_outlined,
              label: 'Share a Note',
              onTap: onOpenUs,
            ),
            ActionTile(
              icon: Icons.event_outlined,
              label: 'Make a Plan',
              onTap: onOpenFuture,
            ),
            ActionTile(
              icon: Icons.checklist_rounded,
              label: 'Our Lists',
              onTap: onOpenFuture,
            ),
          ],
        ),
        if (notice != null) ...[const SizedBox(height: Spacing.xl), notice],
      ],
    );
  }

  // Shape and words carry the meaning, never colour alone.
  static Widget? _presenceLine(PartnerPresence? presence, String name) {
    final (icon, text) = switch (presence) {
      null || PartnerPresence.unavailable => (null, null),
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
    if (icon == null || text == null) return null;
    return _PresenceLine(
      icon: icon,
      text: text,
      online: presence == PartnerPresence.online,
    );
  }
}

class _PresenceLine extends StatelessWidget {
  const _PresenceLine({
    required this.icon,
    required this.text,
    required this.online,
  });

  final IconData icon;
  final String text;
  final bool online;

  @override
  Widget build(BuildContext context) => MergeSemantics(
    child: Row(
      children: [
        ExcludeSemantics(
          child: Icon(
            icon,
            size: IconSizes.sm,
            color: online
                ? context.colors.success
                : context.colors.textSecondary,
          ),
        ),
        const SizedBox(width: Spacing.sm),
        Expanded(
          child: Text(
            text,
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
              color: context.colors.textSecondary,
            ),
          ),
        ),
      ],
    ),
  );
}

/// The hero card's choice: icon well, title, one line, chevron.
class _HeroChoice extends StatelessWidget {
  const _HeroChoice({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.badge,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final String? badge;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final badge = this.badge;
    return HeroCard(
      semanticLabel: [title, subtitle, ?badge].join(', '),
      onTap: onTap,
      child: Row(
        children: [
          HeroIcon(icon),
          const SizedBox(width: Spacing.lg),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (badge != null) ...[
                  Text(
                    badge,
                    style: textTheme.labelMedium?.copyWith(
                      color: HeroCard.mutedTextColor,
                    ),
                  ),
                  const SizedBox(height: Spacing.xxs),
                ],
                Text(
                  title,
                  style: textTheme.titleLarge?.copyWith(
                    color: HeroCard.textColor,
                  ),
                ),
                const SizedBox(height: Spacing.xs),
                Text(
                  subtitle,
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

/// Three tiles a row (two with very large text); every tile in a row is as
/// tall as the tallest.
class _Grid extends StatelessWidget {
  const _Grid({required this.tiles});

  final List<Widget> tiles;

  @override
  Widget build(BuildContext context) {
    final columns = MediaQuery.textScalerOf(context).scale(1) > 1.5 ? 2 : 3;
    final rows = [
      for (var i = 0; i < tiles.length; i += columns)
        tiles.sublist(i, (i + columns).clamp(0, tiles.length)),
    ];
    return Column(
      children: [
        for (final (r, row) in rows.indexed) ...[
          if (r > 0) const SizedBox(height: Spacing.md),
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var c = 0; c < columns; c++) ...[
                  if (c > 0) const SizedBox(width: Spacing.md),
                  Expanded(
                    child: c < row.length ? row[c] : const SizedBox.shrink(),
                  ),
                ],
              ],
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
