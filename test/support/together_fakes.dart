import 'dart:async';

import 'package:sirf_hum/features/together/domain/together_activity.dart';
import 'package:sirf_hum/features/together/domain/together_backend.dart';

/// A deterministic, test-only [TogetherBackend]. It lives under `test/` so
/// production code cannot import it: the app wires no Together backend
/// (D-112). The test drives the partner's side explicitly.
class FakeTogetherBackend implements TogetherBackend {
  FakeTogetherBackend({
    Set<TogetherActivity>? supported,
    TogetherSnapshot initial = const TogetherNoSession(
      presence: PartnerPresence.online,
    ),
  }) : supportedActivities = supported ?? {TogetherActivity.timeTogether},
       _current = initial;

  @override
  final Set<TogetherActivity> supportedActivities;

  TogetherSnapshot _current;
  final _changes = StreamController<TogetherSnapshot>.broadcast();

  int watches = 0;
  final starts = <TogetherActivity>[];
  int joins = 0;
  int leaves = 0;

  /// When set, the next call fails with it.
  TogetherFailure? failStart;
  TogetherFailure? failJoin;
  TogetherFailure? failLeave;

  /// When set, `start`/`join`/`leave` wait for it before answering.
  Completer<void>? hold;

  TogetherSnapshot get current => _current;

  void emit(TogetherSnapshot snapshot) {
    _current = snapshot;
    _changes.add(snapshot);
  }

  void emitError(TogetherFailure failure) =>
      _changes.addError(TogetherException(failure));

  // The partner's side.
  void partnerJoins({DateTime? at}) => emit(
    TogetherInSession(
      activity: _activity,
      phase: TogetherPhase.active,
      presence: PartnerPresence.inActivity,
      activeSince: at,
    ),
  );

  void partnerStarts([
    TogetherActivity activity = TogetherActivity.timeTogether,
  ]) => emit(
    TogetherInSession(
      activity: activity,
      phase: TogetherPhase.invited,
      presence: PartnerPresence.inActivity,
    ),
  );

  void partnerLeaves() => emit(
    TogetherSessionEnded(
      activity: _activity,
      reason: TogetherEndReason.partnerLeft,
      presence: PartnerPresence.online,
    ),
  );

  void expires() => emit(
    TogetherSessionEnded(
      activity: _activity,
      reason: TogetherEndReason.expired,
      presence: PartnerPresence.online,
    ),
  );

  /// The session disappears without an end (server lost it).
  void vanishes() =>
      emit(const TogetherNoSession(presence: PartnerPresence.online));

  TogetherActivity get _activity => switch (_current) {
    TogetherInSession(:final activity) => activity,
    TogetherSessionEnded(:final activity) => activity,
    TogetherNoSession() => TogetherActivity.timeTogether,
  };

  @override
  Stream<TogetherSnapshot> watch() async* {
    watches++;
    yield _current;
    yield* _changes.stream;
  }

  @override
  Future<void> start(TogetherActivity activity) async {
    starts.add(activity);
    await hold?.future;
    if (failStart case final failure?) throw TogetherException(failure);
    emit(
      TogetherInSession(
        activity: activity,
        phase: TogetherPhase.waitingForPartner,
        presence: PartnerPresence.online,
      ),
    );
  }

  @override
  Future<void> join() async {
    joins++;
    await hold?.future;
    if (failJoin case final failure?) throw TogetherException(failure);
    emit(
      TogetherInSession(
        activity: _activity,
        phase: TogetherPhase.active,
        presence: PartnerPresence.inActivity,
      ),
    );
  }

  @override
  Future<void> leave() async {
    leaves++;
    await hold?.future;
    if (failLeave case final failure?) throw TogetherException(failure);
    emit(const TogetherNoSession(presence: PartnerPresence.online));
  }
}
