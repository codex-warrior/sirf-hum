import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sirf_hum/design_system/design_system.dart';
import 'package:sirf_hum/features/home/application/home_providers.dart';
import 'package:sirf_hum/features/home/domain/greeting.dart';
import 'package:sirf_hum/features/notebook/application/notebook_controller.dart';
import 'package:sirf_hum/features/notebook/domain/notebook_state.dart';
import 'package:sirf_hum/features/notebook/presentation/notebook_copy.dart';
import 'package:sirf_hum/features/notebook/presentation/notebook_editor_screen.dart';
import 'package:sirf_hum/features/notebook/presentation/notebook_status.dart';
import 'package:sirf_hum/features/verification/application/verification_controller.dart';
import 'package:sirf_hum/features/verification/domain/verification_state.dart';
import 'package:sirf_hum/features/verification/presentation/verification_screen.dart';
import 'package:sirf_hum/security/couple/couple_profiles.dart';
import 'package:sirf_hum/security/moments/moment_payload.dart';
import 'package:sirf_hum/security/notebook/notebook.dart';
import 'package:sirf_hum/security/notebook/notebook_payload.dart';
import 'package:sirf_hum/security/notebook/notebook_service.dart';
import 'package:sirf_hum/session/session_controller.dart';

/// Who the two of you are together (Prompt 16, D-120; visual identity v1,
/// D-156): your story and days together, your profile, safety, devices and
/// settings, and the parts of your notebook — story, little things,
/// rituals. Private to the two of you: not a profile, a feed or a score.
/// Every edit is a pushed page, so nothing here is ever in a URL.
class UsScreen extends ConsumerWidget {
  const UsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final names = ref.watch(pairedCoupleProvider)?.names ?? CoupleNames.unknown;
    final state = ref.watch(notebookProvider);
    final controller = ref.read(notebookProvider.notifier);
    final ready = state is NotebookReady ? state : null;
    final now = ref.watch(homeClockProvider)();

    final page = AppPage(
      title: 'Us',
      subtitle: 'The little things about the two of you.',
      trailing: CoupleMark(
        yours: CoupleMark.initialOf(names.yours),
        partner: CoupleMark.initialOf(names.partner),
      ),
      children: [
        _StoryHero(
          since: ready?.snapshot
              .section(NotebookSection.togetherSince)
              .lastOrNull,
          today: now,
          canEdit: ready != null,
        ),
        const SizedBox(height: Spacing.lg),
        _Cards(names: names),
        const SizedBox(height: Spacing.xxl),
        Semantics(
          header: true,
          child: Text(
            'About Us',
            style: Theme.of(context).textTheme.titleLarge,
          ),
        ),
        const SizedBox(height: Spacing.md),
        if (ready != null) ...[
          NotebookNotices(state: ready, onRetry: controller.refresh),
          _AboutUs(snapshot: ready.snapshot),
        ] else
          NotebookStatusView(
            state: state,
            controller: controller,
            areaName: 'Us',
            empty: const _Empty(),
          ),
      ],
    );
    return ready != null
        ? RefreshIndicator(onRefresh: controller.refresh, child: page)
        : page;
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

/// "Your Story", since when, and how many days: from the date the two of
/// you saved, never invented. Tapping sets or changes that day.
class _StoryHero extends StatelessWidget {
  const _StoryHero({
    required this.since,
    required this.today,
    required this.canEdit,
  });

  final NotebookEntry? since;
  final DateTime today;
  final bool canEdit;

  /// "Oct 20, 2024": short, and with the year that matters here.
  static String _withYear(BuildContext context, MomentDate date) {
    final local = date.toLocal();
    final day = MaterialLocalizations.of(context).formatShortMonthDay(local);
    return '$day, ${local.year}';
  }

  static int _days(MomentDate since, DateTime today) {
    final days = DateTime.utc(
      today.year,
      today.month,
      today.day,
    ).difference(DateTime.utc(since.year, since.month, since.day)).inDays;
    return days < 0 ? 0 : days;
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final since = this.since;
    final date = since?.date;
    final days = date == null ? null : _days(date, today);
    final line = date == null
        ? (canEdit ? 'Add the day you got together' : 'Your days, together.')
        : 'Together since ${_withYear(context, date)}';
    // At large text sizes the day count goes under the story, not beside it.
    final stacked = MediaQuery.textScalerOf(context).scale(1) > 1.3;
    final story = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: Spacing.xxxl),
        Row(
          children: [
            Flexible(
              child: Text(
                'Your Story',
                style: textTheme.headlineSmall?.copyWith(
                  color: HeroCard.textColor,
                ),
              ),
            ),
            const SizedBox(width: Spacing.sm),
            const Icon(Icons.favorite_border),
          ],
        ),
        const SizedBox(height: Spacing.xs),
        Text(
          line,
          style: textTheme.bodyLarge?.copyWith(color: HeroCard.mutedTextColor),
        ),
      ],
    );
    final count = days == null
        ? null
        : Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                MaterialLocalizations.of(context).formatDecimal(days),
                style: textTheme.displaySmall?.copyWith(
                  color: HeroCard.textColor,
                ),
              ),
              Text(
                days == 1 ? 'day together' : 'days together',
                style: textTheme.bodyLarge?.copyWith(
                  color: HeroCard.mutedTextColor,
                ),
              ),
            ],
          );
    return HeroCard(
      semanticLabel: [
        'Your story',
        line,
        if (days != null) '$days days together',
      ].join(', '),
      onTap: canEdit
          ? () => openNotebookEditor(
              context,
              section: NotebookSection.togetherSince,
              entry: since,
            )
          : null,
      minHeight: Spacing.xxxl * 4 + Spacing.lg,
      horizon: DuskHorizon.hills,
      child: stacked || count == null
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                story,
                if (count != null) ...[
                  const SizedBox(height: Spacing.lg),
                  count,
                ],
              ],
            )
          : Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(child: story),
                Container(
                  width: 1,
                  height: Spacing.xxxl * 2,
                  margin: const EdgeInsets.symmetric(horizontal: Spacing.lg),
                  color: HeroCard.mutedTextColor.withValues(alpha: 0.4),
                ),
                count,
              ],
            ),
    );
  }
}

/// Profile, safety, devices, settings: two by two, one by one at large
/// text sizes.
class _Cards extends ConsumerWidget {
  const _Cards({required this.names});

  final CoupleNames names;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final safety = switch (ref.watch(partnerVerificationProvider)) {
      VerificationReady(verified: true) => 'Safety number verified',
      VerificationReady() => 'Compare your safety number',
      VerificationLoading() => 'Checking…',
      VerificationUnavailable(
        reason: VerificationUnavailableReason.needsPhone,
      ) =>
        'On your phone',
      VerificationUnavailable() => 'Not available yet',
      VerificationFailed() => 'Couldn’t check',
    };
    void push(Widget page) => Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => page));
    final cards = [
      _InfoCard(
        icon: Icons.people_outline,
        title: 'Our Profile',
        subtitle: coupleTitle(names),
        onTap: () => push(_ProfilePage(names: names)),
      ),
      _InfoCard(
        icon: Icons.lock_outline,
        title: 'Privacy & Safety',
        subtitle: safety,
        onTap: () => push(const VerificationScreen()),
      ),
      _InfoCard(
        icon: Icons.devices_outlined,
        title: 'Devices',
        subtitle: 'Coming soon',
        onTap: () => showSoonSheet(context, 'Managing your devices'),
      ),
      _InfoCard(
        icon: Icons.settings_outlined,
        title: 'Settings',
        subtitle: 'Account and app',
        onTap: () => push(const _SettingsPage()),
      ),
    ];
    final columns = MediaQuery.textScalerOf(context).scale(1) > 1.5 ? 1 : 2;
    return Column(
      children: [
        for (var r = 0; r < cards.length; r += columns) ...[
          if (r > 0) const SizedBox(height: Spacing.md),
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var c = 0; c < columns; c++) ...[
                  if (c > 0) const SizedBox(width: Spacing.md),
                  Expanded(child: cards[r + c]),
                ],
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({
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
            padding: const EdgeInsets.all(Spacing.lg),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon, size: IconSizes.md, color: context.colors.accent),
                const SizedBox(width: Spacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: textTheme.titleMedium),
                      const SizedBox(height: Spacing.xxs),
                      Text(
                        subtitle,
                        style: textTheme.bodyMedium?.copyWith(
                          color: context.colors.textSecondary,
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
  }
}

/// The parts of the notebook that belong to Us.
enum _UsPart {
  story(
    NotebookSection.story,
    Icons.favorite_border,
    'Our Story',
    'How it all started',
  ),
  littleThings(
    NotebookSection.littleThing,
    Icons.star_border,
    'Little Things',
    'Your favourites, quirks and more',
  ),
  rituals(
    NotebookSection.ritual,
    Icons.all_inclusive,
    'Our Rituals',
    'Habits that keep you closer',
  );

  const _UsPart(this.section, this.icon, this.title, this.description);

  final NotebookSection section;
  final IconData icon;
  final String title;
  final String description;
}

class _AboutUs extends StatelessWidget {
  const _AboutUs({required this.snapshot});

  final NotebookSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: context.colors.surface,
        borderRadius: BorderRadius.circular(Radii.lg),
        border: Border.all(color: context.colors.surfaceMuted),
      ),
      child: Column(
        children: [
          for (final (i, part) in _UsPart.values.indexed) ...[
            if (i > 0)
              const Divider(
                height: 1,
                indent: Spacing.lg,
                endIndent: Spacing.lg,
              ),
            Builder(
              builder: (context) {
                final count = snapshot.section(part.section).length;
                final line = count == 0
                    ? part.description
                    : '${part.description} · $count';
                return ListTile(
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: Spacing.lg,
                    vertical: Spacing.xs,
                  ),
                  minTileHeight: TouchTargets.comfortable + Spacing.lg,
                  leading: Icon(
                    part.icon,
                    size: IconSizes.lg,
                    color: context.colors.accent,
                  ),
                  title: Text(part.title, style: textTheme.titleMedium),
                  subtitle: Text(
                    line,
                    style: textTheme.bodyMedium?.copyWith(
                      color: context.colors.textSecondary,
                    ),
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => _PartPage(part: part),
                    ),
                  ),
                );
              },
            ),
          ],
        ],
      ),
    );
  }
}

/// One part of Us on its own page: its entries and a way to add more.
class _PartPage extends ConsumerWidget {
  const _PartPage({required this.part});

  final _UsPart part;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(notebookProvider);
    final controller = ref.read(notebookProvider.notifier);
    return Scaffold(
      appBar: AppBar(),
      body: AppPage(
        title: part.title,
        subtitle: part.description,
        children: [
          if (state is NotebookReady)
            _part(context, state.snapshot)
          else
            NotebookStatusView(
              state: state,
              controller: controller,
              areaName: 'Us',
              empty: const _Empty(),
            ),
        ],
      ),
    );
  }

  Widget _part(BuildContext context, NotebookSnapshot snap) => switch (part) {
    _UsPart.story => _Part(
      title: 'Our story',
      divider: false,
      hint: 'How did it all begin? Write it down together.',
      addLabel: 'Add to your story',
      full:
          snap.section(NotebookSection.story).length >=
          NotebookService.limits[NotebookSection.story]!,
      onAdd: () => openNotebookEditor(context, section: NotebookSection.story),
      children: [
        for (final e
            in (snap.section(NotebookSection.story).toList()
              ..sort(_storyOrder)))
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
    _UsPart.littleThings => _Part(
      title: 'Our little things',
      divider: false,
      hint: 'Your song, your food, the joke nobody else gets.',
      addLabel: 'Add a little thing',
      full:
          snap.section(NotebookSection.littleThing).length >=
          NotebookService.limits[NotebookSection.littleThing]!,
      onAdd: () =>
          openNotebookEditor(context, section: NotebookSection.littleThing),
      children: [
        for (final e in snap.section(NotebookSection.littleThing))
          _Row(
            key: ValueKey(e.handle),
            entry: e,
            title: e.title,
            overline: e.littleThingKind?.label,
            subtitle: e.note,
          ),
      ],
    ),
    _UsPart.rituals => _Part(
      title: 'Rituals',
      divider: false,
      hint: 'The things you keep doing together, like a Friday movie.',
      addLabel: 'Add a ritual',
      full:
          snap.section(NotebookSection.ritual).length >=
          NotebookService.limits[NotebookSection.ritual]!,
      onAdd: () => openNotebookEditor(context, section: NotebookSection.ritual),
      children: [
        for (final e in snap.section(NotebookSection.ritual))
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
  };

  static int _storyOrder(NotebookEntry a, NotebookEntry b) {
    final ad = a.date;
    final bd = b.date;
    if (ad != null && bd != null && ad != bd) return ad.compareTo(bd);
    if ((ad == null) != (bd == null)) return ad == null ? 1 : -1;
    return a.addedAt.compareTo(b.addedAt);
  }
}

/// Your names as your accounts give them. Editing them is not built yet,
/// and the page says so.
class _ProfilePage extends StatelessWidget {
  const _ProfilePage({required this.names});

  final CoupleNames names;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final secondary = textTheme.bodyLarge?.copyWith(
      color: context.colors.textSecondary,
    );
    return Scaffold(
      appBar: AppBar(),
      body: AppPage(
        title: 'Our Profile',
        subtitle: 'You two, in one place.',
        children: [
          CoupleMark(
            yours: CoupleMark.initialOf(names.yours),
            partner: CoupleMark.initialOf(names.partner),
          ),
          const SizedBox(height: Spacing.lg),
          Text(coupleTitle(names), style: textTheme.headlineSmall),
          const SizedBox(height: Spacing.xl),
          Text('You', style: secondary),
          Text(names.yours ?? 'No name yet', style: textTheme.titleMedium),
          const SizedBox(height: Spacing.md),
          Text('Your person', style: secondary),
          Text(names.partner ?? 'No name yet', style: textTheme.titleMedium),
          const SizedBox(height: Spacing.xl),
          const Notice(
            icon: Icons.schedule_outlined,
            message:
                'Names come from your accounts. Changing them and adding '
                'photos are coming soon.',
          ),
        ],
      ),
    );
  }
}

/// Account and app: licences and signing out.
class _SettingsPage extends ConsumerWidget {
  const _SettingsPage();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(),
      body: AppPage(
        title: 'Settings',
        children: [
          ListTile(
            contentPadding: EdgeInsets.zero,
            minTileHeight: TouchTargets.comfortable,
            leading: const Icon(Icons.notifications_none),
            title: const Text('Notifications'),
            subtitle: const Text('Coming soon'),
            onTap: () => showSoonSheet(context, 'Notifications'),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            minTileHeight: TouchTargets.comfortable,
            leading: const Icon(Icons.description_outlined),
            title: const Text('Licences'),
            onTap: () =>
                showLicensePage(context: context, applicationName: 'Sirf Hum'),
          ),
          const SizedBox(height: Spacing.xl),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: OutlinedButton.icon(
              onPressed: () => _confirmSignOut(context, ref),
              icon: const Icon(Icons.logout),
              label: const Text('Sign out'),
            ),
          ),
        ],
      ),
    );
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
    if (!(confirmed ?? false) || !context.mounted) return;
    // Leave this pushed page first, and let that frame finish: signing out
    // replaces the whole shell, this page included.
    final session = ref.read(sessionProvider.notifier);
    Navigator.of(context).popUntil((route) => route.isFirst);
    await WidgetsBinding.instance.endOfFrame;
    await session.signOut();
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
