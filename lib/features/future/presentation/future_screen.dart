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

/// Things the two of you want to do (Prompt 16, D-120): a shared private
/// notebook, not a task manager. No progress, counts, streaks, reminders or
/// "overdue": a day that has passed is just a day. The editor is a pushed
/// page, so no plan is ever in a URL.
class FutureScreen extends ConsumerWidget {
  const FutureScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(notebookProvider);
    final controller = ref.read(notebookProvider.notifier);
    final today = MomentDate.of(ref.watch(futureClockProvider)());

    final page = AppPage(
      title: 'Future',
      subtitle: 'Things you want to do together.',
      children: [
        if (state is NotebookReady) ...[
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: FilledButton.icon(
              onPressed: () =>
                  openNotebookEditor(context, section: NotebookSection.future),
              icon: const Icon(Icons.add),
              label: const Text('Add something'),
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
            child: state is NotebookReady
                ? _Notebook(
                    state: state,
                    sections: FutureSections.of(
                      state.snapshot.section(NotebookSection.future),
                      today,
                    ),
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

class _Notebook extends StatelessWidget {
  const _Notebook({
    required this.state,
    required this.sections,
    required this.onRetry,
  });

  final NotebookReady state;
  final FutureSections sections;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    final groups = <(String, List<NotebookEntry>, bool)>[
      ('Coming up', sections.comingUp, true),
      for (final MapEntry(key: c, value: list) in sections.byCategory.entries)
        (c.plural, list, false),
      ('Important dates', sections.importantDates, false),
      ('Done together', sections.done, false),
    ].where((g) => g.$2.isNotEmpty).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        NotebookNotices(state: state, onRetry: onRetry),
        if (sections.isEmpty) const _Empty(),
        for (final (i, (title, entries, showCategory)) in groups.indexed)
          AppSection(
            title: title,
            divider: i > 0,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final e in entries)
                  FutureRow(
                    key: ValueKey(e.handle),
                    entry: e,
                    showCategory: showCategory,
                  ),
              ],
            ),
          ),
      ],
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
