import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sirf_hum/core/logging/app_logger.dart';
import 'package:sirf_hum/design_system/design_system.dart';
import 'package:sirf_hum/features/notebook/application/notebook_controller.dart';
import 'package:sirf_hum/features/notebook/presentation/notebook_copy.dart';
import 'package:sirf_hum/security/moments/moment_payload.dart';
import 'package:sirf_hum/security/notebook/notebook.dart';
import 'package:sirf_hum/security/notebook/notebook_payload.dart';
import 'package:sirf_hum/security/notebook/notebook_service.dart';
import 'package:sirf_hum/session/session_controller.dart';

/// What the editor did, for the page that opened it to confirm.
class NotebookEditResult {
  const NotebookEditResult(this.outcome, {this.removed = false});

  final NotebookSaveOutcome outcome;
  final bool removed;

  String get message => switch ((removed, outcome)) {
    (true, NotebookSaveOutcome.saved) => 'Removed for both of you.',
    (true, NotebookSaveOutcome.savedOnPhone) =>
      'Removed on this phone. It will finish when you’re back online.',
    (false, _) => saveOutcomeMessage(outcome),
  };
}

/// Opens the editor as a pushed page (never a URL, D-121) and confirms the
/// result with a snack bar on the page that opened it.
Future<void> openNotebookEditor(
  BuildContext context, {
  required NotebookSection section,
  NotebookEntry? entry,
  FutureCategory? category,
}) async {
  final messenger = ScaffoldMessenger.of(context);
  final result = await Navigator.of(context).push<NotebookEditResult>(
    MaterialPageRoute(
      fullscreenDialog: entry == null,
      builder: (_) => NotebookEditorScreen(
        section: section,
        entry: entry,
        category: category,
      ),
    ),
  );
  if (result == null) return;
  messenger.showSnackBar(SnackBar(content: Text(result.message)));
}

/// Adds or changes one notebook record: a plan, part of your story, a
/// little thing, a ritual or the day you got together. One small form; the
/// person sees that it is saving, never how.
///
/// - Single flight: a second tap while saving does nothing, and the page
///   cannot be left mid-save, so one change is never made twice.
/// - A failed save changed nothing; the fields stay for another try.
class NotebookEditorScreen extends ConsumerStatefulWidget {
  const NotebookEditorScreen({
    required this.section,
    this.entry,
    this.category,
    super.key,
  });

  final NotebookSection section;

  /// The record to change; null to add one.
  final NotebookEntry? entry;

  /// For a new Future item: the kind to start with.
  final FutureCategory? category;

  @override
  ConsumerState<NotebookEditorScreen> createState() =>
      _NotebookEditorScreenState();
}

class _NotebookEditorScreenState extends ConsumerState<NotebookEditorScreen> {
  late final TextEditingController _title;
  late final TextEditingController _note;
  late final TextEditingController _detail;
  late int _category;
  late bool _done;

  /// A dream's progress, 0–100 (D-157). Kept while switching kinds; saved
  /// only for a dream.
  late int _progress;
  MomentDate? _date;
  bool _saving = false;
  bool _failed = false;
  NotebookFailure? _failure;

  NotebookSection get _section => widget.section;
  bool get _editing => widget.entry != null;
  bool get _titled => _section != NotebookSection.togetherSince;

  @override
  void initState() {
    super.initState();
    final e = widget.entry;
    _title = TextEditingController(text: e?.title ?? '');
    _note = TextEditingController(text: e?.note ?? '');
    _detail = TextEditingController(text: e?.detail ?? '');
    _category =
        e?.category ??
        switch (_section) {
          NotebookSection.future =>
            (widget.category ?? FutureCategory.plan).wireValue,
          NotebookSection.littleThing =>
            LittleThingKind.favouriteFood.wireValue,
          _ => 0,
        };
    _done = e?.done ?? false;
    _progress = e?.progress ?? 0;
    _date = e?.date;
    for (final c in [_title, _note, _detail]) {
      c.addListener(_changed);
    }
  }

  void _changed() => setState(() {});

  @override
  void dispose() {
    _title.dispose();
    _note.dispose();
    _detail.dispose();
    super.dispose();
  }

  FutureCategory? get _futureCategory => _section == NotebookSection.future
      ? FutureCategory.fromWire(_category)
      : null;

  bool get _canSave =>
      !_saving && (_titled ? _title.text.trim().isNotEmpty : _date != null);

  String get _heading => switch (_section) {
    NotebookSection.future =>
      _editing ? 'Change this plan' : 'Something to look forward to',
    NotebookSection.story => _editing ? 'Your story' : 'Add to your story',
    NotebookSection.littleThing => 'One of your little things',
    NotebookSection.ritual => 'Something you do together',
    NotebookSection.togetherSince => 'The day you got together',
  };

  /// Story days and "together since" have happened; a plan may be any day.
  bool get _pastOnly => switch (_section) {
    NotebookSection.story || NotebookSection.togetherSince => true,
    _ => false,
  };

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final category = _futureCategory;

    return PopScope(
      canPop: !_saving,
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            tooltip: 'Close',
            icon: const Icon(Icons.close),
            onPressed: _saving ? null : () => Navigator.of(context).maybePop(),
          ),
          title: Text(_editing ? 'Edit' : 'New'),
          actions: [
            TextButton(
              onPressed: _canSave ? _save : null,
              child: const Text('Save'),
            ),
            const SizedBox(width: Spacing.sm),
          ],
        ),
        body: AppPage(
          title: _heading,
          children: [
            if (_failed) ...[
              Semantics(
                liveRegion: true,
                child: Text(
                  notebookFailureMessage(_failure),
                  style: textTheme.bodyLarge?.copyWith(
                    color: context.colors.danger,
                  ),
                ),
              ),
              const SizedBox(height: Spacing.lg),
            ],
            if (_saving) ...[
              Semantics(
                liveRegion: true,
                child: Text('Saving…', style: textTheme.bodyLarge),
              ),
              const SizedBox(height: Spacing.sm),
              const LinearProgressIndicator(),
              const SizedBox(height: Spacing.lg),
            ],
            if (_section == NotebookSection.future)
              _Choices(
                label: 'What kind of thing is it?',
                enabled: !_saving,
                selected: _category,
                choices: {
                  for (final c in FutureCategory.values) c.wireValue: c.label,
                },
                onSelected: (v) => setState(() => _category = v),
              ),
            if (_section == NotebookSection.littleThing)
              _Choices(
                label: 'What kind of little thing?',
                enabled: !_saving,
                selected: _category,
                choices: {
                  for (final k in LittleThingKind.values) k.wireValue: k.label,
                },
                onSelected: (v) => setState(() => _category = v),
              ),
            if (_titled) ...[
              TextField(
                controller: _title,
                enabled: !_saving,
                autofocus: !_editing,
                maxLength: 100,
                textInputAction: TextInputAction.next,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(
                  labelText: _titleLabel(category),
                  hintText: _titleHint(category),
                ),
              ),
              if (_section == NotebookSection.story &&
                  !_editing &&
                  _title.text.trim().isEmpty)
                _Suggestions(enabled: !_saving, onPick: (s) => _title.text = s),
              const SizedBox(height: Spacing.md),
            ],
            if (category == FutureCategory.dream) ...[
              _ProgressField(
                value: _progress,
                enabled: !_saving,
                onChanged: (v) => setState(() => _progress = v),
              ),
              const SizedBox(height: Spacing.md),
            ],
            if (_section == NotebookSection.ritual) ...[
              TextField(
                controller: _detail,
                enabled: !_saving,
                maxLength: 40,
                textInputAction: TextInputAction.next,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'How often? (optional)',
                  hintText: 'Every Friday',
                ),
              ),
              const SizedBox(height: Spacing.md),
            ],
            if (_titled) ...[
              TextField(
                controller: _note,
                enabled: !_saving,
                minLines: _section == NotebookSection.story ? 4 : 1,
                maxLines: 10,
                maxLength: _section == NotebookSection.story ? 1500 : 500,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(labelText: _noteLabel),
              ),
              const SizedBox(height: Spacing.lg),
            ],
            if (_section != NotebookSection.littleThing &&
                _section != NotebookSection.ritual)
              _DateField(
                label: switch (_section) {
                  NotebookSection.future => 'When? (optional)',
                  NotebookSection.togetherSince => 'Since',
                  _ => 'When was this? (optional)',
                },
                empty: _section == NotebookSection.togetherSince
                    ? 'Choose the day'
                    : 'No date',
                date: _date,
                enabled: !_saving,
                optional: _section != NotebookSection.togetherSince,
                onPick: _pickDate,
                onClear: () => setState(() => _date = null),
              ),
            if (_editing &&
                _section == NotebookSection.future &&
                category != FutureCategory.importantDate)
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                value: _done,
                onChanged: _saving
                    ? null
                    : (v) => setState(() => _done = v ?? false),
                title: const Text('We’ve done this'),
              ),
            if (_editing) ...[
              const SizedBox(height: Spacing.xl),
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: TextButton(
                  onPressed: _saving ? null : _confirmRemove,
                  child: const Text('Remove'),
                ),
              ),
              const SizedBox(height: Spacing.sm),
              _Byline(entry: widget.entry!),
            ],
          ],
        ),
      ),
    );
  }

  String _titleLabel(FutureCategory? category) => switch (_section) {
    NotebookSection.future => category!.titleLabel,
    NotebookSection.story => 'Give this part a name',
    NotebookSection.littleThing => 'What is it?',
    NotebookSection.ritual => 'What do you do?',
    NotebookSection.togetherSince => '',
  };

  String? _titleHint(FutureCategory? category) => switch (_section) {
    NotebookSection.future => category!.titleHint,
    NotebookSection.littleThing => 'Masala chai at midnight',
    NotebookSection.ritual => 'Friday movie',
    _ => null,
  };

  String get _noteLabel => switch (_section) {
    NotebookSection.story => 'Tell it your way',
    NotebookSection.ritual => 'Anything else about it? (optional)',
    _ => 'Anything to remember? (optional)',
  };

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final initial = _date?.toLocal() ?? now;
    final last = _pastOnly ? now : DateTime(MomentDate.maxYear, 12, 31);
    final picked = await showDatePicker(
      context: context,
      initialDate: initial.isAfter(last) ? last : initial,
      firstDate: DateTime(MomentDate.minYear),
      lastDate: last,
    );
    if (picked != null && mounted) {
      setState(() => _date = MomentDate.of(picked));
    }
  }

  NotebookFields _fields() => NotebookFields(
    section: _section,
    category: _category,
    status: _section == NotebookSection.future
        ? (_done ? FutureStatus.done : FutureStatus.planned).wireValue
        : 0,
    date: _date,
    progress: _futureCategory == FutureCategory.dream ? _progress : null,
    title: _title.text,
    note: _note.text,
    detail: _detail.text,
  );

  Future<void> _save() async {
    if (_saving || !_canSave) return;
    final NotebookFields fields;
    try {
      fields = _fields();
    } on NotebookPayloadException catch (e) {
      setState(() {
        _failed = true;
        _failure = notebookFailureOf(e.failure);
      });
      return;
    }
    final controller = ref.read(notebookProvider.notifier);
    final entry = widget.entry;
    await _run(
      () => entry == null
          ? controller.create(fields)
          : controller.update(entry.handle, fields),
      removed: false,
    );
  }

  Future<void> _confirmRemove() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove this?'),
        content: const Text('It will disappear for both of you.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Keep'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (!(confirmed ?? false) || !mounted) return;
    final controller = ref.read(notebookProvider.notifier);
    await _run(() => controller.remove(widget.entry!.handle), removed: true);
  }

  Future<void> _run(
    Future<NotebookSaveOutcome> Function() action, {
    required bool removed,
  }) async {
    if (_saving) return;
    setState(() {
      _saving = true;
      _failed = false;
      _failure = null;
    });
    try {
      final outcome = await action();
      if (!mounted) return;
      _saving = false;
      Navigator.of(context).pop(NotebookEditResult(outcome, removed: removed));
    } on NotebookException catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _failed = true;
        _failure = e.failure;
      });
    } on Object catch (error) {
      AppLogger.warning('notebook_edit_failed', error: error);
      if (!mounted) return;
      setState(() {
        _saving = false;
        _failed = true;
        _failure = null;
      });
    }
  }
}

/// A small set of choices as chips: each is a button with its state
/// announced, and selection is shown by a check mark, not colour alone.
class _Choices extends StatelessWidget {
  const _Choices({
    required this.label,
    required this.enabled,
    required this.selected,
    required this.choices,
    required this.onSelected,
  });

  final String label;
  final bool enabled;
  final int selected;
  final Map<int, String> choices;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: Spacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: Spacing.sm),
          Wrap(
            spacing: Spacing.sm,
            runSpacing: Spacing.sm,
            children: [
              for (final MapEntry(key: value, value: text) in choices.entries)
                ChoiceChip(
                  label: Text(text),
                  selected: value == selected,
                  showCheckmark: true,
                  onSelected: enabled ? (_) => onSelected(value) : null,
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Ways to begin a story, offered only while the name is empty. They fill
/// the name; nothing is saved until the person saves.
class _Suggestions extends StatelessWidget {
  const _Suggestions({required this.enabled, required this.onPick});

  final bool enabled;
  final ValueChanged<String> onPick;

  static const _starts = [
    'How we started',
    'Our first date',
    'The day we knew',
  ];

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: Spacing.sm,
      runSpacing: Spacing.sm,
      children: [
        for (final s in _starts)
          ActionChip(
            label: Text(s),
            onPressed: enabled ? () => onPick(s) : null,
          ),
      ],
    );
  }
}

class _DateField extends StatelessWidget {
  const _DateField({
    required this.label,
    required this.empty,
    required this.date,
    required this.enabled,
    required this.optional,
    required this.onPick,
    required this.onClear,
  });

  final String label;
  final String empty;
  final MomentDate? date;
  final bool enabled;
  final bool optional;
  final VoidCallback onPick;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final date = this.date;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        MergeSemantics(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: textTheme.labelLarge),
              const SizedBox(height: Spacing.xs),
              Text(
                date == null ? empty : formatDay(context, date),
                style: textTheme.bodyLarge?.copyWith(
                  color: context.colors.textSecondary,
                ),
              ),
            ],
          ),
        ),
        Wrap(
          spacing: Spacing.sm,
          children: [
            TextButton(
              onPressed: enabled ? onPick : null,
              child: Text(date == null ? 'Choose a date' : 'Change date'),
            ),
            if (date != null && optional)
              TextButton(
                onPressed: enabled ? onClear : null,
                child: const Text('Remove date'),
              ),
          ],
        ),
      ],
    );
  }
}

/// Who added it — the only "who" shown. No times, no history, no counts.
class _Byline extends ConsumerWidget {
  const _Byline({required this.entry});

  final NotebookEntry entry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final partner = ref.watch(pairedCoupleProvider)?.names.partner;
    return Text(
      entry.addedByYou
          ? 'Added by you'
          : 'Added by ${partner ?? 'your person'}',
      style: Theme.of(
        context,
      ).textTheme.bodyMedium?.copyWith(color: context.colors.textSecondary),
    );
  }
}

/// How far a dream has come, in steps of 5%. The value is said in words.
class _ProgressField extends StatelessWidget {
  const _ProgressField({
    required this.value,
    required this.enabled,
    required this.onChanged,
  });

  final int value;
  final bool enabled;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text('How far along are you?', style: textTheme.bodyLarge),
            ),
            ExcludeSemantics(
              child: Text('$value%', style: textTheme.titleMedium),
            ),
          ],
        ),
        Slider(
          value: value.toDouble(),
          max: NotebookFields.maxProgress.toDouble(),
          divisions: NotebookFields.maxProgress ~/ 5,
          label: '$value%',
          semanticFormatterCallback: (v) => '${v.round()} percent',
          onChanged: enabled ? (v) => onChanged(v.round()) : null,
        ),
      ],
    );
  }
}
