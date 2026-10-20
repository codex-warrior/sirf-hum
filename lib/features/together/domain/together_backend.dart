import 'package:sirf_hum/features/together/domain/together_activity.dart';

/// The realtime boundary for Together (D-111).
///
/// It takes no identifiers at all: no account, couple, partner, device or
/// session ID. A real implementation derives the account from the
/// authenticated server context, the couple from the server's couple record,
/// and requires an **active** device (D-069–D-085) for every step, so the
/// client cannot point Together at anyone but its own partner.
///
/// No production implementation exists yet (D-112): the server stores no
/// presence or activity (D-100, THREAT-MODEL T10), and device trust cannot
/// be enforced without Functions (Blaze, D-025). Production wires none, and
/// Together reports itself unavailable.
abstract interface class TogetherBackend {
  /// Activities this backend can actually run. Anything else is never
  /// startable, whatever the UI shows.
  Set<TogetherActivity> get supportedActivities;

  /// The couple's Together state as the server sees it: the current value
  /// first, then every change. Errors are [TogetherException]s.
  Stream<TogetherSnapshot> watch();

  /// Starts [activity] and invites the partner. Failures are
  /// [TogetherException]s.
  Future<void> start(TogetherActivity activity);

  /// Accepts the partner's invitation.
  Future<void> join();

  /// Leaves the current session: cancels a pending one, declines an
  /// invitation, or ends an active one.
  Future<void> leave();
}

/// How the partner appears, as far as they allow (D-112). No timestamps,
/// location, device or network details, ever.
enum PartnerPresence { unavailable, online, away, offline, inActivity }

enum TogetherPhase {
  /// This account started; the partner has not joined.
  waitingForPartner,

  /// The partner started; this account has not joined.
  invited,

  /// Both are in.
  active,
}

enum TogetherEndReason {
  /// This account left or cancelled.
  left,

  /// The partner left, cancelled or declined.
  partnerLeft,

  /// Nobody joined in time, or the session timed out.
  expired,
}

/// The server's view. ID-free, like every Together type.
sealed class TogetherSnapshot {
  const TogetherSnapshot({required this.presence});

  final PartnerPresence presence;
}

final class TogetherNoSession extends TogetherSnapshot {
  const TogetherNoSession({required super.presence});
}

final class TogetherInSession extends TogetherSnapshot {
  const TogetherInSession({
    required this.activity,
    required this.phase,
    required super.presence,
    this.activeSince,
  });

  final TogetherActivity activity;
  final TogetherPhase phase;

  /// When both were in (server clock). Only for [TogetherPhase.active].
  final DateTime? activeSince;
}

/// The session ended. Shown once, then the hub returns to idle.
final class TogetherSessionEnded extends TogetherSnapshot {
  const TogetherSessionEnded({
    required this.activity,
    required this.reason,
    required super.presence,
  });

  final TogetherActivity activity;
  final TogetherEndReason reason;
}

/// Failure categories. Never carries data.
enum TogetherFailure {
  /// Network or backend unavailable; retryable.
  unavailable,

  /// The server refused to start (rate limit, already in a session, …).
  startRefused,

  /// The session no longer exists (expired, already ended).
  sessionGone,

  /// This device is not an active, trusted device (revoked, pending, …).
  deviceNotTrusted,

  /// The account has no couple (any more).
  notPaired,

  /// The server answered something this client does not understand.
  unexpected,
}

class TogetherException implements Exception {
  const TogetherException(this.failure);

  final TogetherFailure failure;

  @override
  String toString() => 'TogetherException(${failure.name})';
}
