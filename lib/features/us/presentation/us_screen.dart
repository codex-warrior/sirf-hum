import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sirf_hum/design_system/design_system.dart';
import 'package:sirf_hum/features/home/domain/greeting.dart';
import 'package:sirf_hum/features/notebook/application/notebook_controller.dart';
import 'package:sirf_hum/features/notebook/domain/notebook_state.dart';
import 'package:sirf_hum/features/notebook/presentation/notebook_copy.dart';
import 'package:sirf_hum/features/notebook/presentation/notebook_editor_screen.dart';
import 'package:sirf_hum/features/notebook/presentation/notebook_status.dart';
import 'package:sirf_hum/security/couple/couple_profiles.dart';
import 'package:sirf_hum/security/notebook/notebook.dart';
import 'package:sirf_hum/security/notebook/notebook_payload.dart';
import 'package:sirf_hum/security/notebook/notebook_service.dart';
import 'package:sirf_hum/session/session_controller.dart';

/// Who the two of you are together (Prompt 16, D-120): your names, the day
/// you got together, your story, your little things, your rituals and the
/// days that matter. Private to the two of you — not a profile, a feed or
/// a score. Edits are pushed pages, so nothing here is ever in a URL.
class UsScreen extends ConsumerWidget {
  const UsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final names = ref.watch(pairedCoupleProvider)?.names ?? CoupleNames.unknown;
    final state = ref.watch(notebookProvider);
    final controller = ref.read(notebookProvider.notifier);
    final ready = state is NotebookReady ? state : null;

    final page = AppPage(
      title: 'Us',
      subtitle: 'The two of you.',
      children: [
        _CoupleHeader(
          names: names,
          since: ready?.snapshot
              .section(NotebookSection.togetherSince)
              .lastOrNull,
          canEdit: ready != null,
        ),
        const SizedBox(height: Spacing.xxl),
        if (ready != null)
          _Notebook(state: ready, onRetry: controller.refresh)
        else
          NotebookStatusView(
            state: state,
            controller: controller,
            areaName: 'Us',
            empty: const _Empty(),
          ),
        AppSection(
          title: 'Account',
          child: Align(
            alignment: AlignmentDirectional.centerStart,
            child: OutlinedButton.icon(
              onPressed: () => _confirmSignOut(context, ref),
              icon: const Icon(Icons.logout),
              label: const Text('Sign out'),
            ),
          ),
        ),
      ],
    );
    return ready != null
        ? RefreshIndicator(onRefresh: controller.refresh, child: page)
        : page;
  }

  Future<void> _confirmSignOut(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Sign out of Sirf Hum?'),
        content: const Text('Your couple stays as it is. Nothing is deleted.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Stay'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Sign out'),
          ),
        ],
      ),
    );
    if (confirmed ?? false) {
      await ref.read(sessionProvider.notifier).signOut();
    }
  }
}

class _Empty extends StatelessWidget {
  const _Empty();

  @override
  Widget build(BuildContext context) => const EmptyState(
    icon: Icons.all_inclusive_outlined,
    title: 'This is your space.',
    message: 'Fill it with the little things that are yours.',
  );
}

/// The couple mark, both names and — when you have said it — since when.
class _CoupleHeader extends StatelessWidget {
  const _CoupleHeader({
    required this.names,
    required this.since,
    required this.canEdit,
  });

  final CoupleNames names;
  final NotebookEntry? since;
  final bool canEdit;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final since = this.since;
    final date = since?.date;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CoupleMark(
          yours: CoupleMark.initialOf(names.yours),
          partner: CoupleMark.initialOf(names.partner),
        ),
        const SizedBox(height: Spacing.lg),
        Text(coupleTitle(names), style: textTheme.headlineSmall),
        if (date != null) ...[
          const SizedBox(height: Spacing.xs),
          Text(
            'Together since ${formatDay(context, date)}',
            style: textTheme.bodyLarge?.copyWith(
              color: context.colors.textSecondary,
            ),
          ),
        ],
        if (canEdit)
          TextButton(
            style: TextButton.styleFrom(padding: EdgeInsets.zero),
            onPressed: () => openNotebookEditor(
              context,
              section: NotebookSection.togetherSince,
              entry: since,
            ),
            child: Text(
              since == null
                  ? 'Add the day you got together'
                  : 'Change the day you got together',
            ),
          ),
      ],
    );
  }
}

class _Notebook extends StatelessWidget {
  const _Notebook({required this.state, required this.onRetry});

  final NotebookReady state;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    final snap = state.snapshot;
    final story = snap.section(NotebookSection.story).toList()
      ..sort((a, b) {
        final ad = a.date;
        final bd = b.date;
        if (ad != null && bd != null && ad != bd) return ad.compareTo(bd);
        if ((ad == null) != (bd == null)) return ad == null ? 1 : -1;
        return a.addedAt.compareTo(b.addedAt);
      });
    final things = snap.section(NotebookSection.littleThing).toList();
    final rituals = snap.section(NotebookSection.ritual).toList();
    final dates =
        snap
            .section(NotebookSection.future)
            .where((e) => e.futureCategory == FutureCategory.importantDate)
            .toList()
          ..sort((a, b) {
            final d = _byDate(a, b);
            return d != 0 ? d : a.addedAt.compareTo(b.addedAt);
          });
    final nothingYet =
        story.isEmpty &&
        things.isEmpty &&
        rituals.isEmpty &&
        dates.isEmpty &&
        snap.section(NotebookSection.togetherSince).isEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        NotebookNotices(state: state, onRetry: onRetry),
        if (nothingYet) ...[const _Empty(), const SizedBox(height: Spacing.xl)],
        _Part(
          title: 'Our story',
          divider: false,
          hint: 'How did it all begin? Write it down together.',
          addLabel: 'Add to your story',
          full: story.length >= NotebookService.limits[NotebookSection.story]!,
          onAdd: () =>
              openNotebookEditor(context, section: NotebookSection.story),
          children: [
            for (final e in story)
              _Row(
                key: ValueKey(e.handle),
                entry: e,
                title: e.title,
                subtitle: [
                  if (e.date != null) formatDay(context, e.date!),
                  if (e.note.isNotEmpty) e.note,
                ].join('\n'),
                maxSubtitleLines: 4,
              ),
          ],
        ),
        _Part(
          title: 'Our little things',
          hint: 'Your song, your food, the joke nobody else gets.',
          addLabel: 'Add a little thing',
          full:
              things.length >=
              NotebookService.limits[NotebookSection.littleThing]!,
          onAdd: () =>
              openNotebookEditor(context, section: NotebookSection.littleThing),
          children: [
            for (final e in things)
              _Row(
                key: ValueKey(e.handle),
                entry: e,
                title: e.title,
                overline: e.littleThingKind?.label,
                subtitle: e.note,
              ),
          ],
        ),
        _Part(
          title: 'Rituals',
          hint: 'The things you keep doing together, like a Friday movie.',
          addLabel: 'Add a ritual',
          full:
              rituals.length >= NotebookService.limits[NotebookSection.ritual]!,
          onAdd: () =>
              openNotebookEditor(context, section: NotebookSection.ritual),
          children: [
            for (final e in rituals)
              _Row(
                key: ValueKey(e.handle),
                entry: e,
                title: e.title,
                subtitle: [
                  if (e.detail.isNotEmpty) e.detail,
                  if (e.note.isNotEmpty) e.note,
                ].join('\n'),
              ),
          ],
        ),
        _Part(
          title: 'Important dates',
          hint: 'Anniversaries, birthdays, the days that are yours.',
          addLabel: 'Add an important date',
          full: false,
          onAdd: () => openNotebookEditor(
            context,
            section: NotebookSection.future,
            category: FutureCategory.importantDate,
          ),
          children: [
            for (final e in dates)
              _Row(
                key: ValueKey(e.handle),
                entry: e,
                title: e.title,
                subtitle: e.date == null ? '' : formatDay(context, e.date!),
              ),
          ],
        ),
      ],
    );
  }

  static int _byDate(NotebookEntry a, NotebookEntry b) {
    final ad = a.date;
    final bd = b.date;
    if (ad == null || bd == null) return ad == bd ? 0 : (ad == null ? 1 : -1);
    return ad.compareTo(bd);
  }
}

/// One part of Us: its entries, a quiet hint while it is empty, and one way
/// to add more while there is room.
class _Part extends StatelessWidget {
  const _Part({
    required this.title,
    required this.hint,
    required this.addLabel,
    required this.full,
    required this.onAdd,
    required this.children,
    this.divider = true,
  });

  final String title;
  final String hint;
  final String addLabel;
  final bool full;
  final VoidCallback onAdd;
  final List<Widget> children;
  final bool divider;

  @override
  Widget build(BuildContext context) {
    return AppSection(
      title: title,
      divider: divider,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (children.isEmpty)
            Text(
              hint,
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                color: context.colors.textSecondary,
              ),
            ),
          ...children,
          if (full)
            Padding(
              padding: const EdgeInsets.only(top: Spacing.sm),
              child: Text(
                'That’s all the room there is here for now.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: context.colors.textSecondary,
                ),
              ),
            )
          else
            TextButton.icon(
              style: TextButton.styleFrom(padding: EdgeInsets.zero),
              onPressed: onAdd,
              icon: const Icon(Icons.add),
              label: Text(addLabel),
            ),
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({
    required this.entry,
    required this.title,
    required this.subtitle,
    this.overline,
    this.maxSubtitleLines = 2,
    super.key,
  });

  final NotebookEntry entry;
  final String title;
  final String subtitle;
  final String? overline;
  final int maxSubtitleLines;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final overline = this.overline;
    final secondary = textTheme.bodyMedium?.copyWith(
      color: context.colors.textSecondary,
    );
    final details = [
      if (subtitle.isNotEmpty) subtitle,
      if (entry.saving) 'Saving…',
    ].join('\n');
    return ListTile(
      contentPadding: EdgeInsets.zero,
      minTileHeight: TouchTargets.comfortable,
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (overline != null) Text(overline, style: secondary),
          Text(title, style: textTheme.bodyLarge),
        ],
      ),
      subtitle: details.isEmpty
          ? null
          : Text(
              details,
              maxLines: maxSubtitleLines + (entry.saving ? 1 : 0),
              overflow: TextOverflow.ellipsis,
              style: secondary,
            ),
      onTap: () =>
          openNotebookEditor(context, section: entry.section, entry: entry),
    );
  }
}
