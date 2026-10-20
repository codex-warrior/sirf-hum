import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sirf_hum/core/logging/app_logger.dart';
import 'package:sirf_hum/core/logging/log_value.dart';
import 'package:sirf_hum/features/together/domain/together_activity.dart';
import 'package:sirf_hum/features/together/domain/together_backend.dart';
import 'package:sirf_hum/features/together/domain/together_state.dart';
import 'package:sirf_hum/session/session_controller.dart';
import 'package:sirf_hum/session/session_state.dart';

/// The Together realtime port. `null` — the production value today — means no
/// backend runs Together sessions (D-112); the hub then says so. Only tests
/// override it, with a fake that lives under `test/`.
final togetherBackendProvider = Provider<TogetherBackend?>((ref) => null);

final togetherProvider = NotifierProvider<TogetherController, TogetherState>(
  TogetherController.new,
);

/// The single producer of [TogetherState] (D-111).
///
/// - Runs only for a paired session (Prompt 13, D-106). Any session change —
///   sign-out, account switch, couple lost — rebuilds it from nothing, and the
///   previous subscription and in-flight answers are dropped (generation).
/// - Session state comes from the backend's snapshots; local states
///   (starting, joining, ending) only bridge until the server answers.
/// - Fails closed: an error, an unknown activity or a session that vanishes
///   is never shown as idle or as "together".
/// - Nothing is persisted. Logs carry state kinds and failure categories.
class TogetherController extends Notifier<TogetherState> {
  int _generation = 0;
  PartnerPresence _presence = PartnerPresence.unavailable;

  @override
  TogetherState build() {
    final generation = ++_generation;
    _presence = PartnerPresence.unavailable;

    final paired = ref.watch(sessionProvider.select((s) => s is SessionPaired));
    if (!paired) {
      return _initial(TogetherUnavailableReason.notPaired);
    }
    // Together needs a trusted device identity; web never holds one
    // (WEB-SECURITY, LocalDeviceIdentityService refuses web).
    if (!ref.watch(privateContentAvailableProvider)) {
      return _initial(TogetherUnavailableReason.needsPhone);
    }
    final backend = ref.watch(togetherBackendProvider);
    if (backend == null) {
      return _initial(TogetherUnavailableReason.notYetAvailable);
    }

    final subscription = backend.watch().listen(
      (snapshot) {
        if (_isCurrent(generation)) _onSnapshot(snapshot, backend);
      },
      onError: (Object error) {
        if (_isCurrent(generation)) {
          _fail(_failureOf(error), 'together_watch_failed');
        }
      },
    );
    ref.onDispose(subscription.cancel);
    _log(const TogetherLoading());
    return const TogetherLoading();
  }

  /// Starts [activity]. Ignored unless idle and the backend supports it, so
  /// no button can start what does not exist.
  Future<void> start(TogetherActivity activity) async {
    final current = state;
    final backend = ref.read(togetherBackendProvider);
    if (current is! TogetherIdle ||
        backend == null ||
        !current.supported.contains(activity)) {
      return;
    }
    final generation = _generation;
    _set(TogetherStarting(activity));
    try {
      await backend.start(activity);
    } on Object catch (error) {
      if (_isCurrent(generation)) {
        _fail(_failureOf(error), 'activity_start_failed');
      }
      return;
    }
    // The server accepted; its snapshot may already have moved us on.
    if (_isCurrent(generation) && state is TogetherStarting) {
      _set(TogetherWaiting(activity));
    }
  }

  /// Accepts the partner's invitation.
  Future<void> join() async {
    final current = state;
    final backend = ref.read(togetherBackendProvider);
    if (current is! TogetherInvited || backend == null) return;
    final generation = _generation;
    _set(TogetherJoining(current.activity));
    try {
      await backend.join();
    } on Object catch (error) {
      if (_isCurrent(generation)) {
        _fail(_failureOf(error), 'activity_join_failed');
      }
      return;
    }
    if (_isCurrent(generation) && state is TogetherJoining) {
      _set(TogetherActive(activity: current.activity, since: null));
    }
  }

  /// Cancels a pending session, declines an invitation, or ends an active
  /// one.
  Future<void> leave() async {
    final current = state;
    final backend = ref.read(togetherBackendProvider);
    final activity = switch (current) {
      TogetherWaiting(:final activity) ||
      TogetherInvited(:final activity) ||
      TogetherActive(:final activity) => activity,
      _ => null,
    };
    if (activity == null || backend == null) return;
    final generation = _generation;
    _set(TogetherEnding(activity));
    try {
      await backend.leave();
    } on Object catch (error) {
      if (_isCurrent(generation)) {
        _fail(_failureOf(error), 'activity_leave_failed');
      }
      return;
    }
    if (!_isCurrent(generation) || state is! TogetherEnding) return;
    // Only a session both were in "ends"; a cancelled or declined one simply
    // returns to the choices.
    _set(
      current is TogetherActive
          ? TogetherEnded(activity: activity, reason: TogetherEndReason.left)
          : _idle(),
    );
  }

  /// "Back to Together" after an ended session: shows what the server says
  /// now (a new invitation may have arrived while the end was on screen).
  void dismiss() {
    if (state is TogetherEnded) ref.invalidateSelf();
  }

  /// Starts over from the backend's current state.
  void retry() {
    if (state is TogetherFailed) ref.invalidateSelf();
  }

  void _onSnapshot(TogetherSnapshot snapshot, TogetherBackend backend) {
    final current = state;
    // A failure or an end holds until the user retries or dismisses it,
    // which starts a new subscription: nothing more on this stream can make a
    // refused or revoked device, or a finished session, "together" again.
    if (current is TogetherFailed || current is TogetherEnded) return;
    _presence = snapshot.presence;
    final supported = backend.supportedActivities;

    final TogetherState next;
    switch (snapshot) {
      case TogetherNoSession():
        next = switch (current) {
          // Our own request is still with the server.
          TogetherStarting() || TogetherEnding() => current,
          // A session both were in disappeared without an end: say it ended,
          // never pretend it is still on.
          TogetherActive(:final activity) ||
          TogetherJoining(:final activity) => TogetherEnded(
            activity: activity,
            reason: TogetherEndReason.expired,
          ),
          TogetherWaiting(:final activity) ||
          TogetherInvited(:final activity) => TogetherEnded(
            activity: activity,
            reason: TogetherEndReason.expired,
          ),
          _ => _idle(),
        };
      case TogetherInSession(:final activity, :final phase, :final activeSince):
        if (!supported.contains(activity)) {
          _fail(TogetherFailure.unexpected, 'together_unexpected_state');
          return;
        }
        next = switch (phase) {
          _ when current is TogetherEnding => current,
          TogetherPhase.waitingForPartner => TogetherWaiting(activity),
          TogetherPhase.invited when current is TogetherJoining => current,
          TogetherPhase.invited => TogetherInvited(activity),
          TogetherPhase.active => TogetherActive(
            activity: activity,
            since: activeSince,
          ),
        };
      case TogetherSessionEnded(:final activity, :final reason):
        next = TogetherEnded(activity: activity, reason: reason);
    }
    // Presence-only changes of an unchanged state are not re-announced.
    if (next is TogetherIdle && current is TogetherIdle) {
      state = next;
      return;
    }
    if (!identical(next, current)) _set(next);
  }

  TogetherIdle _idle() => TogetherIdle(
    presence: _presence,
    supported: ref.read(togetherBackendProvider)?.supportedActivities ?? {},
  );

  TogetherState _initial(TogetherUnavailableReason reason) {
    final next = TogetherUnavailable(reason);
    _log(next);
    return next;
  }

  bool _isCurrent(int generation) => ref.mounted && generation == _generation;

  void _fail(TogetherFailure failure, String event) {
    AppLogger.warning(event, fields: {'failure': failure});
    _set(TogetherFailed(failure));
  }

  void _set(TogetherState next) {
    state = next;
    _log(next);
  }

  static TogetherFailure _failureOf(Object error) =>
      error is TogetherException ? error.failure : TogetherFailure.unexpected;

  // The state's kind and, at most, the activity and a category: never IDs,
  // names or content.
  static void _log(TogetherState state) => AppLogger.info(
    'together_state_changed',
    fields: {
      'state': SafeLogString(switch (state) {
        TogetherUnavailable(:final reason) => 'unavailable_${reason.name}',
        TogetherLoading() => 'loading',
        TogetherIdle() => 'idle',
        TogetherStarting() => 'starting',
        TogetherWaiting() => 'waiting',
        TogetherInvited() => 'invited',
        TogetherJoining() => 'joining',
        TogetherActive() => 'active',
        TogetherEnding() => 'ending',
        TogetherEnded(:final reason) => 'ended_${reason.name}',
        TogetherFailed(:final failure) => 'failed_${failure.name}',
      }),
    },
  );
}
