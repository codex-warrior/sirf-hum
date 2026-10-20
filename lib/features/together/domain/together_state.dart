import 'package:sirf_hum/features/together/domain/together_activity.dart';
import 'package:sirf_hum/features/together/domain/together_backend.dart';

/// What the Together hub shows (D-111). A finite set of states with no
/// booleans that could combine into impossible ones, and no identifiers:
/// rendering any state cannot leak an account, couple, device or session ID.
/// The only producer is `TogetherController`.
sealed class TogetherState {
  const TogetherState();
}

enum TogetherUnavailableReason {
  /// No couple (or the session is still being established).
  notPaired,

  /// Web never holds a device identity, and Together needs a trusted device.
  needsPhone,

  /// No backend runs Together sessions yet (D-112).
  notYetAvailable,
}

final class TogetherUnavailable extends TogetherState {
  const TogetherUnavailable(this.reason);

  final TogetherUnavailableReason reason;
}

/// Waiting for the backend's first answer.
final class TogetherLoading extends TogetherState {
  const TogetherLoading();
}

/// No session: choose something to do.
final class TogetherIdle extends TogetherState {
  const TogetherIdle({required this.presence, required this.supported});

  final PartnerPresence presence;
  final Set<TogetherActivity> supported;
}

/// This account asked to start; the server has not confirmed.
final class TogetherStarting extends TogetherState {
  const TogetherStarting(this.activity);

  final TogetherActivity activity;
}

/// Started; the partner has not joined.
final class TogetherWaiting extends TogetherState {
  const TogetherWaiting(this.activity);

  final TogetherActivity activity;
}

/// The partner started; this account may join.
final class TogetherInvited extends TogetherState {
  const TogetherInvited(this.activity);

  final TogetherActivity activity;
}

/// This account asked to join; the server has not confirmed.
final class TogetherJoining extends TogetherState {
  const TogetherJoining(this.activity);

  final TogetherActivity activity;
}

/// Both are in.
final class TogetherActive extends TogetherState {
  const TogetherActive({required this.activity, required this.since});

  final TogetherActivity activity;

  /// Server time both were in; null if the server did not say.
  final DateTime? since;
}

/// This account asked to leave; the server has not confirmed.
final class TogetherEnding extends TogetherState {
  const TogetherEnding(this.activity);

  final TogetherActivity activity;
}

final class TogetherEnded extends TogetherState {
  const TogetherEnded({required this.activity, required this.reason});

  final TogetherActivity activity;
  final TogetherEndReason reason;
}

final class TogetherFailed extends TogetherState {
  const TogetherFailed(this.failure);

  final TogetherFailure failure;
}
