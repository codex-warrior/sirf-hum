import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sirf_hum/core/logging/app_logger.dart';
import 'package:sirf_hum/core/logging/log_value.dart';
import 'package:sirf_hum/features/notebook/domain/notebook_state.dart';
import 'package:sirf_hum/security/notebook/notebook.dart';
import 'package:sirf_hum/security/notebook/notebook_payload.dart';
import 'package:sirf_hum/security/notebook/notebook_service.dart';
import 'package:sirf_hum/session/private_services.dart';
import 'package:sirf_hum/session/session_controller.dart';
import 'package:sirf_hum/session/session_state.dart';

/// The notebook port for the signed-in account's couple: the
/// `NotebookService` of this phone's private services, over the same
/// `MessagingService` as Moments. `null` while they open, when they failed,
/// or where nothing private is wired (web, tests).
final notebookBackendProvider = Provider<NotebookBackend?>(
  (ref) => ref.watch(currentPrivateServicesProvider)?.notebook,
);

final notebookProvider = NotifierProvider<NotebookController, NotebookState>(
  NotebookController.new,
);

/// The single producer of [NotebookState] (D-121), shared by Future and Us.
///
/// - Runs only for a paired session on a platform that may hold private
///   content, with a backend. Any session change rebuilds it from nothing;
///   answers for an earlier session are dropped (generation).
/// - Local first: this phone's notebook shows at once (also offline), then
///   a refresh checks device trust and fetches what is new.
/// - A device that is no longer trusted is [NotebookBlocked]: the entries
///   are dropped and no write is accepted.
/// - Writes go only through here, only while [NotebookReady]. A write that
///   finishes after the session changed never touches the new state.
/// - Nothing is persisted outside the sealed core. Logs carry state kinds.
class NotebookController extends Notifier<NotebookState> {
  int _generation = 0;
  NotebookSnapshot _snapshot = NotebookSnapshot.empty;
  NotebookNotice? _notice;

  @override
  NotebookState build() {
    final generation = ++_generation;
    _snapshot = NotebookSnapshot.empty;
    _notice = null;

    final paired = ref.watch(sessionProvider.select((s) => s is SessionPaired));
    if (!paired) return _initial(NotebookUnavailableReason.notPaired);
    if (!ref.watch(privateContentAvailableProvider)) {
      return _initial(NotebookUnavailableReason.needsPhone);
    }
    final backend = ref.watch(notebookBackendProvider);
    if (backend == null) {
      return switch (ref.watch(privateServicesStatusProvider)) {
        PrivateServicesStatus.starting => const NotebookLoading(),
        PrivateServicesStatus.failed => const NotebookFailed(null),
        _ => _initial(NotebookUnavailableReason.notYetAvailable),
      };
    }
    unawaited(Future<void>.microtask(() => _start(backend, generation)));
    _log(const NotebookLoading());
    return const NotebookLoading();
  }

  /// Checks for changes; what is shown stays while it runs.
  Future<void> refresh() async {
    final backend = ref.read(notebookBackendProvider);
    if (state is! NotebookReady || backend == null) return;
    await _refresh(backend, _generation);
  }

  /// Starts over after a failure.
  void retry() {
    if (state is! NotebookFailed) return;
    ref.read(notebookBackendProvider) == null
        ? retryPrivateServices(ref)
        : ref.invalidateSelf();
  }

  Future<NotebookSaveOutcome> create(NotebookFields fields) =>
      _write((backend) => backend.create(fields));

  Future<NotebookSaveOutcome> update(
    NotebookHandle handle,
    NotebookFields fields,
  ) => _write((backend) => backend.update(handle, fields));

  Future<NotebookSaveOutcome> remove(NotebookHandle handle) =>
      _write((backend) => backend.remove(handle));

  /// Marks a plan done or not done again. Nothing else changes.
  Future<NotebookSaveOutcome> setDone(
    NotebookEntry entry, {
    required bool done,
  }) {
    final f = entry.fields;
    return update(
      entry.handle,
      NotebookFields(
        section: f.section,
        category: f.category,
        status: (done ? FutureStatus.done : FutureStatus.planned).wireValue,
        date: f.date,
        title: f.title,
        note: f.note,
        detail: f.detail,
      ),
    );
  }

  Future<NotebookSaveOutcome> _write(
    Future<NotebookSaveOutcome> Function(NotebookBackend backend) action,
  ) async {
    final backend = ref.read(notebookBackendProvider);
    if (state is! NotebookReady || backend == null) {
      throw const NotebookException(NotebookFailure.unsupported);
    }
    final generation = _generation;
    try {
      final outcome = await action(backend);
      _load(backend, generation);
      return outcome;
    } on NotebookException catch (e) {
      if (_isCurrent(generation)) {
        switch (e.failure) {
          case NotebookFailure.deviceNotTrusted:
            _snapshot = NotebookSnapshot.empty;
            _set(const NotebookBlocked());
          case NotebookFailure.notPaired:
            _snapshot = NotebookSnapshot.empty;
            _set(const NotebookFailed(NotebookFailure.notPaired));
          default:
            // A change may have arrived meanwhile ("not found").
            _load(backend, generation);
        }
      }
      rethrow;
    }
  }

  Future<void> _start(NotebookBackend backend, int generation) async {
    if (!_load(backend, generation)) return;
    await _refresh(backend, generation);
  }

  bool _load(NotebookBackend backend, int generation) {
    if (!_isCurrent(generation)) return false;
    final current = state;
    if (current is! NotebookReady && current is! NotebookLoading) return false;
    try {
      _snapshot = backend.notebook();
    } on Object catch (error) {
      AppLogger.warning('notebook_load_failed', error: error);
      _snapshot = NotebookSnapshot.empty;
      _set(NotebookFailed(error is NotebookException ? error.failure : null));
      return false;
    }
    _publish();
    return true;
  }

  Future<void> _refresh(NotebookBackend backend, int generation) async {
    _publish(refreshing: true);
    try {
      await backend.refresh();
      _notice = null;
    } on NotebookException catch (e) {
      if (!_isCurrent(generation)) return;
      switch (e.failure) {
        case NotebookFailure.deviceNotTrusted:
          _snapshot = NotebookSnapshot.empty;
          _set(const NotebookBlocked());
          return;
        case NotebookFailure.notPaired:
          _snapshot = NotebookSnapshot.empty;
          _set(const NotebookFailed(NotebookFailure.notPaired));
          return;
        case NotebookFailure.notReady:
          _notice = NotebookNotice.connecting;
        default:
          _notice = NotebookNotice.offline;
      }
    } on Object catch (error) {
      if (!_isCurrent(generation)) return;
      AppLogger.warning('notebook_refresh_failed', error: error);
      _snapshot = NotebookSnapshot.empty;
      _set(const NotebookFailed(null));
      return;
    }
    _load(backend, generation);
  }

  void _publish({bool refreshing = false}) {
    final current = state;
    if (current is! NotebookReady && current is! NotebookLoading) return;
    final next = NotebookReady(
      snapshot: _snapshot,
      refreshing: refreshing,
      notice: _notice,
    );
    final sameKind =
        current is NotebookReady &&
        current.refreshing == next.refreshing &&
        current.notice == next.notice;
    // New content in the same kind of state is not re-announced in logs.
    sameKind ? state = next : _set(next);
  }

  NotebookState _initial(NotebookUnavailableReason reason) {
    final next = NotebookUnavailable(reason);
    _log(next);
    return next;
  }

  bool _isCurrent(int generation) => ref.mounted && generation == _generation;

  void _set(NotebookState next) {
    state = next;
    _log(next);
  }

  // The state's kind and a count at most: never text, dates or handles.
  static void _log(NotebookState state) => AppLogger.info(
    'notebook_state_changed',
    fields: {
      'state': SafeLogString(switch (state) {
        NotebookUnavailable(:final reason) => 'unavailable_${reason.name}',
        NotebookLoading() => 'loading',
        NotebookReady(:final refreshing, :final notice) =>
          refreshing ? 'refreshing' : 'ready_${notice?.name ?? 'current'}',
        NotebookBlocked() => 'blocked',
        NotebookFailed(:final failure) => 'failed_${failure?.name ?? 'local'}',
      }),
      if (state is NotebookReady) 'entries': state.entries.length,
    },
  );
}
