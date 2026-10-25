import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/painting.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sirf_hum/core/logging/app_logger.dart';
import 'package:sirf_hum/core/logging/log_value.dart';
import 'package:sirf_hum/features/moments/domain/moments_state.dart';
import 'package:sirf_hum/security/moments/moment.dart';
import 'package:sirf_hum/security/moments/moments_service.dart';
import 'package:sirf_hum/session/private_services.dart';
import 'package:sirf_hum/session/session_controller.dart';
import 'package:sirf_hum/session/session_state.dart';
import 'package:sirf_hum_crypto/sirf_hum_crypto.dart';

/// The moments port for the signed-in account's couple: the
/// `MomentsService` of this phone's private services, built from the
/// server's couple record for exactly this account. `null` while they open,
/// when they failed, or where nothing private is wired (web, tests).
final momentsBackendProvider = Provider<MomentsBackend?>(
  (ref) => ref.watch(currentPrivateServicesProvider)?.moments,
);

final momentsProvider = NotifierProvider<MomentsController, MomentsState>(
  MomentsController.new,
);

/// One photo, decrypted for display (D-115). Plaintext lives only in
/// memory: the bytes are wiped when no widget shows the photo any more, and
/// the provider fails closed whenever the timeline is not ready (sign-out,
/// account switch, a device that lost trust). Never retried by itself: a
/// corrupted photo must not be downloaded again and again.
final momentPhotoProvider = FutureProvider.autoDispose
    .family<Uint8List, MomentPhoto>((ref, photo) async {
      final ready = ref.watch(momentsProvider.select((s) => s is MomentsReady));
      final backend = ref.watch(momentsBackendProvider);
      if (!ready || backend == null) {
        throw const MomentException(MomentFailure.unsupported);
      }
      final bytes = await backend.openPhoto(photo);
      if (!ref.mounted) {
        wipeBytes(bytes);
        throw const MomentException(MomentFailure.unavailable);
      }
      ref.onDispose(() => wipeBytes(bytes));
      return bytes;
    }, retry: (_, _) => null);

/// The single producer of [MomentsState] (D-115).
///
/// - Runs only for a paired session on a platform that may hold private
///   content, with a backend. Any session change rebuilds it from nothing;
///   answers for an earlier session are dropped (generation).
/// - Local first: this phone's timeline shows at once (also offline), then
///   a refresh checks device trust and fetches what is new.
/// - A device that is no longer trusted is [MomentsBlocked]: the timeline is
///   dropped and decoded photos are evicted from memory.
/// - Bounded: [pageSize] moments at a time; "earlier" shows the next page.
/// - Nothing is persisted outside the sealed core. Logs carry state kinds.
class MomentsController extends Notifier<MomentsState> {
  static const int pageSize = 24;

  int _generation = 0;
  int _visible = pageSize;
  List<MomentEntry> _all = const [];
  MomentsNotice? _notice;

  @override
  MomentsState build() {
    final generation = ++_generation;
    _visible = pageSize;
    _all = const [];
    _notice = null;
    // Whatever this session decoded leaves memory with it.
    ref.onDispose(_evictDecodedPhotos);

    final paired = ref.watch(sessionProvider.select((s) => s is SessionPaired));
    if (!paired) return _initial(MomentsUnavailableReason.notPaired);
    if (!ref.watch(privateContentAvailableProvider)) {
      return _initial(MomentsUnavailableReason.needsPhone);
    }
    final backend = ref.watch(momentsBackendProvider);
    if (backend == null) {
      return switch (ref.watch(privateServicesStatusProvider)) {
        PrivateServicesStatus.starting => const MomentsLoading(),
        PrivateServicesStatus.failed => const MomentsFailed(null),
        PrivateServicesStatus.needsSetup => const MomentsBlocked(),
        _ => _initial(MomentsUnavailableReason.notYetAvailable),
      };
    }
    unawaited(Future<void>.microtask(() => _start(backend, generation)));
    _log(const MomentsLoading());
    return const MomentsLoading();
  }

  /// Checks for new moments; what is shown stays while it runs.
  Future<void> refresh() async {
    final backend = ref.read(momentsBackendProvider);
    if (state is! MomentsReady || backend == null) return;
    await _refresh(backend, _generation);
  }

  /// Shows the next page of earlier moments.
  void showEarlier() {
    if (state case MomentsReady(hasEarlier: true)) {
      _visible += pageSize;
      _publish();
    }
  }

  /// Re-reads this phone's timeline (after a save) and finishes uploads.
  Future<void> saved() async {
    final backend = ref.read(momentsBackendProvider);
    if (state is! MomentsReady || backend == null) return;
    if (!_load(backend, _generation)) return;
    await _refresh(backend, _generation);
  }

  /// Starts over after a failure.
  void retry() {
    if (state is! MomentsFailed) return;
    ref.read(momentsBackendProvider) == null
        ? retryPrivateServices(ref)
        : ref.invalidateSelf();
  }

  Future<void> _start(MomentsBackend backend, int generation) async {
    if (!_load(backend, generation)) return;
    await _refresh(backend, generation);
  }

  bool _load(MomentsBackend backend, int generation) {
    if (!_isCurrent(generation)) return false;
    try {
      _all = backend.moments();
    } on Object catch (error) {
      AppLogger.warning('moments_load_failed', error: error);
      _set(MomentsFailed(error is MomentException ? error.failure : null));
      return false;
    }
    _publish();
    return true;
  }

  Future<void> _refresh(MomentsBackend backend, int generation) async {
    _publish(refreshing: true);
    try {
      await backend.refresh();
      _notice = null;
    } on MomentException catch (e) {
      if (!_isCurrent(generation)) return;
      switch (e.failure) {
        case MomentFailure.deviceNotTrusted:
          _all = const [];
          _evictDecodedPhotos();
          _set(const MomentsBlocked());
          return;
        case MomentFailure.notPaired:
          _all = const [];
          _set(const MomentsFailed(MomentFailure.notPaired));
          return;
        case MomentFailure.notReady:
          _notice = MomentsNotice.connecting;
        default:
          _notice = MomentsNotice.offline;
      }
    } on Object catch (error) {
      if (!_isCurrent(generation)) return;
      AppLogger.warning('moments_refresh_failed', error: error);
      _set(const MomentsFailed(null));
      return;
    }
    _load(backend, generation);
  }

  void _publish({bool refreshing = false}) {
    final current = state;
    if (current is! MomentsReady && current is! MomentsLoading) return;
    final shown = _all.length <= _visible ? _all : _all.sublist(0, _visible);
    final next = MomentsReady(
      entries: List.unmodifiable(shown),
      total: _all.length,
      hasEarlier: _all.length > _visible,
      refreshing: refreshing,
      notice: _notice,
    );
    final sameKind =
        current is MomentsReady &&
        current.refreshing == next.refreshing &&
        current.notice == next.notice;
    // New content in the same kind of state is not re-announced in logs.
    sameKind ? state = next : _set(next);
  }

  MomentsState _initial(MomentsUnavailableReason reason) {
    final next = MomentsUnavailable(reason);
    _log(next);
    return next;
  }

  bool _isCurrent(int generation) => ref.mounted && generation == _generation;

  void _set(MomentsState next) {
    state = next;
    _log(next);
  }

  static void _evictDecodedPhotos() {
    PaintingBinding.instance.imageCache
      ..clear()
      ..clearLiveImages();
  }

  // The state's kind and counts at most: never captions, dates or handles.
  static void _log(MomentsState state) => AppLogger.info(
    'moments_state_changed',
    fields: {
      'state': SafeLogString(switch (state) {
        MomentsUnavailable(:final reason) => 'unavailable_${reason.name}',
        MomentsLoading() => 'loading',
        MomentsReady(:final refreshing, :final notice) =>
          refreshing ? 'refreshing' : 'ready_${notice?.name ?? 'current'}',
        MomentsBlocked() => 'blocked',
        MomentsFailed(:final failure) => 'failed_${failure?.name ?? 'local'}',
      }),
      if (state is MomentsReady) 'shown': state.entries.length,
    },
  );
}
