import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sirf_hum/core/logging/app_logger.dart';
import 'package:sirf_hum/design_system/design_system.dart';
import 'package:sirf_hum/features/future/application/future_providers.dart';
import 'package:sirf_hum/features/future/domain/future_sections.dart';
import 'package:sirf_hum/features/notebook/application/notebook_controller.dart';
import 'package:sirf_hum/features/notebook/domain/notebook_state.dart';
import 'package:sirf_hum/features/notebook/presentation/notebook_copy.dart';
import 'package:sirf_hum/features/notebook/presentation/notebook_editor_screen.dart';
import 'package:sirf_hum/features/notebook/presentation/notebook_status.dart';
import 'package:sirf_hum/security/moments/moment_payload.dart';
import 'package:sirf_hum/security/notebook/notebook.dart';
import 'package:sirf_hum/security/notebook/notebook_payload.dart';
import 'package:sirf_hum/security/notebook/notebook_service.dart';
import 'package:sirf_hum/session/session_controller.dart';

/// Plan, build and dream together (Prompt 16, D-120; visual identity v1,
/// D-156; dreams, D-157): a shared private notebook, not a task manager.
/// Dreams carry the progress the two of you set; plans never become
/// "overdue". Editors are pushed pages, so nothing is ever in a URL.
class FutureScreen extends ConsumerWidget {
  const FutureScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(notebookProvider);
    final controller = ref.read(notebookProvider.notifier);
    final today = MomentDate.of(ref.watch(futureClockProvider)());
    final names = ref.watch(pairedCoupleProvider)?.names;

    final page = AppPage(
      title: 'Future',
      subtitle: 'Plan, build and dream together.',
      trailing: CoupleMark(
        yours: CoupleMark.initialOf(names?.yours),
        partner: CoupleMark.initialOf(names?.partner),
      ),
      children: [
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
            child: state is NotebookReady
                ? _Notebook(
                    state: state,
                    sections: FutureSections.of(
                      state.snapshot.section(NotebookSection.future),
                      today,
                    ),
                    today: today,
                    onRetry: controller.refresh,
                  )
                : NotebookStatusView(
                    state: state,
                    controller: controller,
                    areaName: 'Future',
                    empty: const _Empty(),
                  ),
          ),
        ),
      ],
    );
    return state is NotebookReady
        ? RefreshIndicator(onRefresh: controller.refresh, child: page)
        : page;
  }
}

class _Empty extends StatelessWidget {
  const _Empty();

  @override
  Widget build(BuildContext context) => const EmptyState(
    icon: Icons.explore_outlined,
    title: 'There’s a lot ahead of you.',
    message: 'Save something you want to do together.',
  );
}

void _add(BuildContext context, FutureCategory category) => openNotebookEditor(
  context,
  section: NotebookSection.future,
  category: category,
);

class _Notebook extends StatelessWidget {
  const _Notebook({
    required this.state,
    required this.sections,
    required this.today,
    required this.onRetry,
  });

  final NotebookReady state;
  final FutureSections sections;
  final MomentDate today;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final all = state.snapshot.section(NotebookSection.future).toList();
    final upcoming = sections.comingUp;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        NotebookNotices(state: state, onRetry: onRetry),
        HeroCard(
          semanticLabel: 'Our shared goals: add a dream',
          horizon: DuskHorizon.hills,
          onTap: () => _add(context, FutureCategory.dream),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: Spacing.xxl),
                    Text(
                      'Our Shared Goals',
                      style: textTheme.headlineSmall?.copyWith(
                        color: HeroCard.textColor,
                      ),
                    ),
                    const SizedBox(height: Spacing.xs),
                    Text(
                      'Dreams, plans and milestones — together.',
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
        ),
        const SizedBox(height: Spacing.lg),
        _Counts(all: all, sections: sections),
        const SizedBox(height: Spacing.xxl),
        _Header(
          title: 'Our Dreams',
          onAdd: () => _add(context, FutureCategory.dream),
        ),
        const SizedBox(height: Spacing.sm),
        if (sections.dreams.isEmpty)
          Text(
            'A home, a trip, a life you’re building. Name one and track it '
            'together.',
            style: textTheme.bodyLarge?.copyWith(
              color: context.colors.textSecondary,
            ),
          )
        else
          _Card(
            children: [
              for (final e in sections.dreams)
                DreamRow(key: ValueKey(e.handle), entry: e),
            ],
          ),
        const SizedBox(height: Spacing.xxl),
        _Header(
          title: 'Upcoming',
          onAdd: () => _add(context, FutureCategory.plan),
        ),
        const SizedBox(height: Spacing.sm),
        if (upcoming.isEmpty)
          Text(
            'Nothing planned yet. Give a plan a day and it shows here.',
            style: textTheme.bodyLarge?.copyWith(
              color: context.colors.textSecondary,
            ),
          )
        else
          for (final e in upcoming)
            Padding(
              padding: const EdgeInsets.only(bottom: Spacing.md),
              child: UpcomingCard(
                key: ValueKey(e.handle),
                entry: e,
                today: today,
              ),
            ),
        // Undated (or already passed) plans, places and things to try,
        // by kind: a passed day is just a day, never "missed".
        for (final MapEntry(key: c, value: list) in sections.byCategory.entries)
          if (list.isNotEmpty)
            AppSection(
              title: c.plural,
              child: Column(
                children: [
                  for (final e in list)
                    FutureRow(key: ValueKey(e.handle), entry: e),
                ],
              ),
            ),
        if (sections.importantDates.isNotEmpty)
          AppSection(
            title: 'Important dates',
            child: Column(
              children: [
                for (final e in sections.importantDates)
                  FutureRow(key: ValueKey(e.handle), entry: e),
              ],
            ),
          ),
        if (sections.done.isNotEmpty)
          AppSection(
            title: 'Done together',
            child: Column(
              children: [
                for (final e in sections.done)
                  FutureRow(key: ValueKey(e.handle), entry: e),
              ],
            ),
          ),
      ],
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.title, required this.onAdd});

  final String title;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(
        child: Semantics(
          header: true,
          child: Text(title, style: Theme.of(context).textTheme.titleLarge),
        ),
      ),
      TextButton(
        onPressed: onAdd,
        child: Semantics(
          label: 'Add to $title',
          excludeSemantics: true,
          child: const Text('+ Add'),
        ),
      ),
    ],
  );
}

class _Card extends StatelessWidget {
  const _Card({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: context.colors.surface,
      borderRadius: BorderRadius.circular(Radii.lg),
      border: Border.all(color: context.colors.surfaceMuted),
    ),
    child: Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: Spacing.lg,
        vertical: Spacing.sm,
      ),
      child: Column(
        children: [
          for (final (i, child) in children.indexed) ...[
            if (i > 0) const Divider(height: 1),
            child,
          ],
        ],
      ),
    ),
  );
}

/// Goals, Plans, Places, Things to try: real counts, each opening its list.
class _Counts extends StatelessWidget {
  const _Counts({required this.all, required this.sections});

  final List<NotebookEntry> all;
  final FutureSections sections;

  @override
  Widget build(BuildContext context) {
    int open(FutureCategory c) =>
        all.where((e) => e.futureCategory == c && !e.done).length;
    final activeDreams = open(FutureCategory.dream);
    final upcomingPlans = sections.comingUp
        .where((e) => e.futureCategory == FutureCategory.plan)
        .length;
    String count(int n, String what, String none) => n == 0 ? none : '$n $what';
    final tiles = [
      (
        FutureCategory.dream,
        Icons.track_changes_outlined,
        'Goals',
        count(activeDreams, 'active', 'Dream big'),
      ),
      (
        FutureCategory.plan,
        Icons.event_note_outlined,
        'Plans',
        upcomingPlans > 0
            ? '$upcomingPlans upcoming'
            : count(open(FutureCategory.plan), 'saved', 'None yet'),
      ),
      (
        FutureCategory.place,
        Icons.place_outlined,
        'Places',
        count(open(FutureCategory.place), 'to visit', 'None yet'),
      ),
      (
        FutureCategory.tryThing,
        Icons.auto_awesome_outlined,
        'To try',
        count(open(FutureCategory.tryThing), 'to try', 'None yet'),
      ),
    ];
    final columns = MediaQuery.textScalerOf(context).scale(1) > 1.5 ? 2 : 4;
    return Wrap(
      spacing: Spacing.sm,
      runSpacing: Spacing.sm,
      children: [
        for (final (category, icon, label, line) in tiles)
          Builder(
            builder: (context) {
              final width = MediaQuery.sizeOf(context).width;
              return SizedBox(
                width: _tileWidth(context, width, columns),
                child: ActionTile(
                  icon: icon,
                  label: label,
                  caption: line,
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => FutureCategoryPage(category: category),
                    ),
                  ),
                ),
              );
            },
          ),
      ],
    );
  }

  /// The page's content width (gutters and the readable maximum), split
  /// into [columns].
  static double _tileWidth(BuildContext context, double window, int columns) {
    final gutter = WindowSize.of(context) == WindowSize.compact
        ? Spacing.pageGutterCompact
        : Spacing.pageGutterWide;
    final content = (window - gutter * 2).clamp(0, WindowSize.maxContentWidth);
    return (content - Spacing.sm * (columns - 1)) / columns;
  }
}

/// One dream: its name, the progress the two of you set, and the number.
/// Tapping opens it to change the progress.
class DreamRow extends StatelessWidget {
  const DreamRow({required this.entry, super.key});

  final NotebookEntry entry;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final progress = entry.done ? 100 : (entry.progress ?? 0);
    return Semantics(
      button: true,
      label: [
        entry.title,
        entry.done ? 'done' : '$progress percent',
        if (entry.saving) 'saving',
      ].join(', '),
      excludeSemantics: true,
      child: InkWell(
        onTap: () => openNotebookEditor(
          context,
          section: NotebookSection.future,
          entry: entry,
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: Spacing.lg),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(Radii.md),
                child: SizedBox.square(
                  dimension: TouchTargets.comfortable + Spacing.lg,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      const DuskScene(horizon: DuskHorizon.hills),
                      Icon(
                        entry.done
                            ? Icons.check_circle_outline
                            : Icons.favorite_border,
                        color: HeroCard.textColor,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: Spacing.lg),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(entry.title, style: textTheme.titleMedium),
                    const SizedBox(height: Spacing.sm),
                    Row(
                      children: [
                        Expanded(
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(Radii.pill),
                            child: LinearProgressIndicator(
                              value: progress / NotebookFields.maxProgress,
                              minHeight: Spacing.sm,
                              color: context.colors.textPrimary,
                              backgroundColor: context.colors.surfaceMuted,
                            ),
                          ),
                        ),
                        const SizedBox(width: Spacing.md),
                        Text('$progress%', style: textTheme.bodyLarge),
                      ],
                    ),
                    if (entry.saving) ...[
                      const SizedBox(height: Spacing.xxs),
                      Text(
                        'Saving…',
                        style: textTheme.bodyMedium?.copyWith(
                          color: context.colors.textSecondary,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A plan with a day ahead: a calendar leaf, the name, when, and a menu.
class UpcomingCard extends ConsumerWidget {
  const UpcomingCard({required this.entry, required this.today, super.key});

  final NotebookEntry entry;
  final MomentDate today;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final textTheme = Theme.of(context).textTheme;
    final date = entry.date!;
    final localizations = MaterialLocalizations.of(context);
    final local = date.toLocal();
    final days = DateTime.utc(
      date.year,
      date.month,
      date.day,
    ).difference(DateTime.utc(today.year, today.month, today.day)).inDays;
    final when = switch (days) {
      0 => 'Today',
      1 => 'Tomorrow',
      _ => formatDay(context, date),
    };
    final month = localizations.formatShortMonthDay(local).split(' ').first;
    return Material(
      color: context.colors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Radii.lg),
        side: BorderSide(color: context.colors.surfaceMuted),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => openNotebookEditor(
          context,
          section: NotebookSection.future,
          entry: entry,
        ),
        child: Padding(
          padding: const EdgeInsets.all(Spacing.lg),
          child: Row(
            children: [
              ExcludeSemantics(
                child: Container(
                  width: TouchTargets.comfortable + Spacing.lg,
                  padding: const EdgeInsets.symmetric(vertical: Spacing.sm),
                  decoration: BoxDecoration(
                    color: context.colors.surfaceMuted,
                    borderRadius: BorderRadius.circular(Radii.md),
                  ),
                  child: Column(
                    children: [
                      Text(
                        month.toUpperCase(),
                        style: textTheme.bodyMedium?.copyWith(
                          color: context.colors.textSecondary,
                        ),
                      ),
                      Text('${date.day}', style: textTheme.headlineSmall),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: Spacing.lg),
              Expanded(
                child: MergeSemantics(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(entry.title, style: textTheme.titleMedium),
                      const SizedBox(height: Spacing.xxs),
                      Text(
                        [when, if (entry.saving) 'Saving…'].join(' · '),
                        style: textTheme.bodyMedium?.copyWith(
                          color: context.colors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              PopupMenuButton<bool>(
                tooltip: 'More',
                icon: const Icon(Icons.more_horiz),
                onSelected: (edit) => edit
                    ? openNotebookEditor(
                        context,
                        section: NotebookSection.future,
                        entry: entry,
                      )
                    : _markDone(context, ref),
                itemBuilder: (_) => const [
                  PopupMenuItem(value: false, child: Text('Mark as done')),
                  PopupMenuItem(value: true, child: Text('Edit')),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _markDone(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(notebookProvider.notifier).setDone(entry, done: true);
    } on NotebookException catch (error) {
      messenger.showSnackBar(
        SnackBar(content: Text(notebookFailureMessage(error.failure))),
      );
    } on Object catch (error) {
      AppLogger.warning('future_toggle_failed', error: error);
      messenger.showSnackBar(
        SnackBar(content: Text(notebookFailureMessage(null))),
      );
    }
  }
}

/// Everything of one kind (goals, plans, places, things to try), with a
/// way to add another.
class FutureCategoryPage extends ConsumerWidget {
  const FutureCategoryPage({required this.category, super.key});

  final FutureCategory category;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(notebookProvider);
    final entries = state is NotebookReady
        ? (state.snapshot
              .section(NotebookSection.future)
              .where((e) => e.futureCategory == category)
              .toList()
            ..sort((a, b) {
              if (a.done != b.done) return a.done ? 1 : -1;
              return b.addedAt.compareTo(a.addedAt);
            }))
        : const <NotebookEntry>[];
    final title = category == FutureCategory.dream
        ? 'Our goals'
        : category.plural;
    return Scaffold(
      appBar: AppBar(
        actions: [
          if (state is NotebookReady)
            TextButton(
              onPressed: () => _add(context, category),
              child: const Text('+ Add'),
            ),
          const SizedBox(width: Spacing.sm),
        ],
      ),
      body: AppPage(
        title: title,
        children: [
          if (state is! NotebookReady)
            NotebookStatusView(
              state: state,
              controller: ref.read(notebookProvider.notifier),
              areaName: 'Future',
              empty: const _Empty(),
            )
          else if (entries.isEmpty)
            Text(
              'Nothing here yet.',
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                color: context.colors.textSecondary,
              ),
            )
          else
            for (final e in entries)
              category == FutureCategory.dream
                  ? DreamRow(key: ValueKey(e.handle), entry: e)
                  : FutureRow(key: ValueKey(e.handle), entry: e),
        ],
      ),
    );
  }
}

/// One plan. Tapping opens it; the circle marks it done (or not), shown by
/// shape and words, not colour alone. Nothing celebrates or counts.
class FutureRow extends ConsumerStatefulWidget {
  const FutureRow({required this.entry, this.showCategory = false, super.key});

  final NotebookEntry entry;

  /// In "Coming up", say what kind of plan it is.
  final bool showCategory;

  @override
  ConsumerState<FutureRow> createState() => _FutureRowState();
}

class _FutureRowState extends ConsumerState<FutureRow> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final e = widget.entry;
    final textTheme = Theme.of(context).textTheme;
    final category = e.futureCategory!;
    final date = e.date;
    final details = [
      if (widget.showCategory) category.label,
      if (date != null) formatDay(context, date),
      if (e.done) 'Done',
      if (e.saving) 'Saving…',
    ];
    final datedOnly = category == FutureCategory.importantDate;

    return ListTile(
      contentPadding: EdgeInsets.zero,
      minTileHeight: TouchTargets.comfortable,
      leading: datedOnly
          ? ExcludeSemantics(
              child: Icon(category.icon, color: context.colors.textSecondary),
            )
          : IconButton(
              tooltip: e.done ? 'Mark as not done' : 'Mark as done',
              onPressed: _busy ? null : () => _toggle(e),
              icon: AnimatedSwitcher(
                duration: Motion.resolve(context, Motion.fast),
                child: Icon(
                  e.done ? Icons.check_circle : Icons.radio_button_unchecked,
                  key: ValueKey(e.done),
                ),
              ),
            ),
      title: Text(
        e.title,
        style: textTheme.bodyLarge?.copyWith(
          decoration: e.done ? TextDecoration.lineThrough : null,
          color: e.done ? context.colors.textSecondary : null,
        ),
      ),
      subtitle: details.isEmpty
          ? null
          : Text(
              details.join(' · '),
              style: textTheme.bodyMedium?.copyWith(
                color: context.colors.textSecondary,
              ),
            ),
      onTap: () => openNotebookEditor(
        context,
        section: NotebookSection.future,
        entry: e,
      ),
    );
  }

  Future<void> _toggle(NotebookEntry e) async {
    if (_busy) return;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      await ref.read(notebookProvider.notifier).setDone(e, done: !e.done);
    } on NotebookException catch (error) {
      messenger.showSnackBar(
        SnackBar(content: Text(notebookFailureMessage(error.failure))),
      );
    } on Object catch (error) {
      AppLogger.warning('future_toggle_failed', error: error);
      messenger.showSnackBar(
        SnackBar(content: Text(notebookFailureMessage(null))),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}
