import 'dart:async';

import 'package:sirf_hum/security/moments/moment_payload.dart';
import 'package:sirf_hum/security/notebook/notebook.dart';
import 'package:sirf_hum/security/notebook/notebook_payload.dart';
import 'package:sirf_hum/security/notebook/notebook_service.dart';

/// Handle values look like real message IDs, so tests can prove they never
/// reach the screen or the logs.
String fakeNotebookId(int n) => 'beef${n.toRadixString(16).padLeft(28, '0')}';

NotebookEntry fakeEntry(
  int n,
  NotebookFields fields, {
  bool addedByYou = true,
  bool saving = false,
  DateTime? addedAt,
}) {
  final at = addedAt ?? DateTime(2026, 10, 1).add(Duration(hours: n));
  return NotebookEntry(
    handle: NotebookHandle(fakeNotebookId(n)),
    section: fields.section,
    category: fields.category,
    status: fields.status,
    title: fields.title,
    note: fields.note,
    detail: fields.detail,
    date: fields.date,
    addedByYou: addedByYou,
    changedByYou: addedByYou,
    addedAt: at,
    changedAt: at,
    saving: saving,
  );
}

NotebookFields plan(
  String title, {
  FutureCategory category = FutureCategory.plan,
  bool done = false,
  MomentDate? date,
  String? note,
}) => NotebookFields(
  section: NotebookSection.future,
  category: category.wireValue,
  status: (done ? FutureStatus.done : FutureStatus.planned).wireValue,
  title: title,
  date: date,
  note: note,
);

/// A deterministic [NotebookBackend] the test drives. It applies writes to
/// [entries] the way the real service would (full replacement, remove).
/// Test-only: the app never imports it (D-121).
class FakeNotebookBackend implements NotebookBackend {
  FakeNotebookBackend([List<NotebookEntry>? entries]) : entries = entries ?? [];

  List<NotebookEntry> entries;
  int unreadable = 0;
  var _next = 1000;

  /// Thrown by [notebook] (e.g. local state corruption).
  Object? loadError;

  /// Thrown by [refresh].
  NotebookException? refreshError;

  /// When set, [refresh] waits for it.
  Completer<void>? refreshGate;
  int refreshes = 0;

  /// Thrown by the next write, then cleared.
  NotebookException? writeError;

  /// When set, writes wait for it.
  Completer<void>? writeGate;
  NotebookSaveOutcome outcome = NotebookSaveOutcome.saved;

  final created = <NotebookFields>[];
  final updated = <(NotebookHandle, NotebookFields)>[];
  final removed = <NotebookHandle>[];

  @override
  NotebookSnapshot notebook() {
    final error = loadError;
    if (error != null) throw error;
    return NotebookSnapshot(
      entries: List.unmodifiable(entries),
      unreadable: unreadable,
    );
  }

  @override
  Future<void> refresh() async {
    refreshes++;
    await refreshGate?.future;
    final error = refreshError;
    if (error != null) throw error;
  }

  @override
  Future<void> retryPending() async {}

  Future<void> _gate() async {
    await writeGate?.future;
    final error = writeError;
    writeError = null;
    if (error != null) throw error;
  }

  @override
  Future<NotebookSaveOutcome> create(NotebookFields fields) async {
    created.add(fields);
    await _gate();
    entries = [...entries, fakeEntry(_next++, fields)];
    return outcome;
  }

  @override
  Future<NotebookSaveOutcome> update(
    NotebookHandle handle,
    NotebookFields fields,
  ) async {
    updated.add((handle, fields));
    await _gate();
    final i = entries.indexWhere((e) => e.handle == handle);
    if (i < 0) throw const NotebookException(NotebookFailure.notFound);
    final old = entries[i];
    entries = [...entries]
      ..[i] = NotebookEntry(
        handle: handle,
        section: fields.section,
        category: fields.category,
        status: fields.status,
        title: fields.title,
        note: fields.note,
        detail: fields.detail,
        date: fields.date,
        addedByYou: old.addedByYou,
        changedByYou: true,
        addedAt: old.addedAt,
        changedAt: old.changedAt.add(const Duration(minutes: 1)),
        saving: false,
      );
    return outcome;
  }

  @override
  Future<NotebookSaveOutcome> remove(NotebookHandle handle) async {
    removed.add(handle);
    await _gate();
    if (!entries.any((e) => e.handle == handle)) {
      throw const NotebookException(NotebookFailure.notFound);
    }
    entries = [
      for (final e in entries)
        if (e.handle != handle) e,
    ];
    return outcome;
  }
}
