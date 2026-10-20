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
import 'package:sirf_hum/security/couple/couple_profiles.dart';
import 'package:sirf_hum/security/moments/moment_payload.dart';
import 'package:sirf_hum/security/notebook/notebook_payload.dart';
import 'package:sirf_hum/session/session_controller.dart';

/// The couple's front door (PRODUCT-CONSTITUTION §4).
///
/// It shows only what exists. Presence, calls, moments and plans are not
/// built yet, so their places are deliberate empty states that lead to the
/// area where each will live — never sample data.
///
/// Navigation is passed in, so Home does not depend on the router.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({
    required this.onOpenTogether,
    required this.onOpenMoments,
    required this.onOpenFuture,
    super.key,
  });

  final VoidCallback onOpenTogether;
  final VoidCallback onOpenMoments;
  final VoidCallback onOpenFuture;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // The router only opens Home for a paired session; before that answer
    // arrives (or if it changes) nothing about the couple is shown.
    final couple = ref.watch(pairedCoupleProvider);
    if (couple == null) return const HomeSkeleton();

    final now = ref.watch(homeClockProvider)();
    final privateHere = ref.watch(privateContentAvailableProvider);
    final moments = ref.watch(momentsProvider);
    final kept = moments is MomentsReady ? moments.total : 0;
    final notebook = ref.watch(notebookProvider);
    final next = notebook is NotebookReady
        ? FutureSections.of(
            notebook.snapshot.section(NotebookSection.future),
            MomentDate.of(now),
          ).next
        : null;
    final nextDate = next?.date;

    return AppPage(
      header: _Greeting(greeting: greetingFor(now), names: couple.names),
      children: [
        _TogetherEntry(onOpen: onOpenTogether),
        const SizedBox(height: Spacing.xxl),
        AppSection(
          title: 'Recently',
          child: kept == 0
              ? EmptyState(
                  icon: Icons.photo_outlined,
                  title: 'Your first memory is waiting.',
                  message:
                      'Photos, voice notes and letters you keep together '
                      'will appear here.',
                  action: StateAction(
                    label: 'Go to Moments',
                    onPressed: onOpenMoments,
                  ),
                )
              : EmptyState(
                  icon: Icons.photo_library_outlined,
                  title: kept == 1
                      ? 'You’ve kept your first memory.'
                      : 'You’ve kept $kept memories together.',
                  message: 'They’re waiting for you in Moments.',
                  action: StateAction(
                    label: 'Go to Moments',
                    onPressed: onOpenMoments,
                  ),
                ),
        ),
        AppSection(
          title: 'Coming up',
          child: next == null || nextDate == null
              ? EmptyState(
                  icon: Icons.event_outlined,
                  title: 'Make a plan for the two of you.',
                  message: 'Dates, trips and little things to look forward to.',
                  action: StateAction(
                    label: 'Go to Future',
                    onPressed: onOpenFuture,
                  ),
                )
              : EmptyState(
                  icon: Icons.event_outlined,
                  title: next.title,
                  message: MaterialLocalizations.of(
                    context,
                  ).formatMediumDate(nextDate.toLocal()),
                  action: StateAction(
                    label: 'Go to Future',
                    onPressed: onOpenFuture,
                  ),
                ),
        ),
        if (!privateHere)
          const Notice(
            icon: Icons.phone_android_outlined,
            message:
                'Private messages, calls and moments open in the Sirf Hum '
                'app on your phone.',
          ),
      ],
    );
  }
}

class _Greeting extends StatelessWidget {
  const _Greeting({required this.greeting, required this.names});

  final String greeting;
  final CoupleNames names;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CoupleMark(
          yours: CoupleMark.initialOf(names.yours),
          partner: CoupleMark.initialOf(names.partner),
        ),
        const SizedBox(height: Spacing.xl),
        Text(
          greeting,
          style: textTheme.bodyLarge?.copyWith(
            color: context.colors.textSecondary,
          ),
        ),
        const SizedBox(height: Spacing.xs),
        Semantics(
          header: true,
          child: Text(coupleTitle(names), style: textTheme.displaySmall),
        ),
      ],
    );
  }
}

/// The one primary action on Home. Spending time together is the core loop's
/// second step, so it gets the only accent on the screen.
class _TogetherEntry extends StatelessWidget {
  const _TogetherEntry({required this.onOpen});

  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
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
                  Text(
                    'Start something together.',
                    style: textTheme.titleLarge,
                  ),
                  const SizedBox(height: Spacing.sm),
                  Text(
                    'Wherever you both are, this is where you’ll call, '
                    'watch and listen together.',
                    style: textTheme.bodyLarge?.copyWith(
                      color: context.colors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: Spacing.xl),
            FilledButton(
              onPressed: onOpen,
              child: const Text('Go to Together'),
            ),
          ],
        ),
      ),
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
                height: Spacing.xxxl * 3 + Spacing.xxl,
                radius: Radii.lg,
              ),
              const SizedBox(height: Spacing.xxl),
              SkeletonBlock.line(TypeScale.label, widthFactor: 0.25),
              const SizedBox(height: Spacing.md),
              SkeletonBlock.line(TypeScale.heading, widthFactor: 0.8),
              const SizedBox(height: Spacing.xs),
              SkeletonBlock.line(TypeScale.body, widthFactor: 0.6),
            ],
          ),
        ),
      ],
    );
  }
}
