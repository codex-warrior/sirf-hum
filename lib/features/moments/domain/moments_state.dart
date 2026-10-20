import 'package:sirf_hum/security/moments/moment.dart';
import 'package:sirf_hum/security/moments/moments_service.dart';

/// What the Moments area shows (D-115). A finite set of states; no
/// account, couple, conversation or device identifiers. Moment entries carry
/// only opaque handles that are never rendered. The only producer is
/// `MomentsController`.
sealed class MomentsState {
  const MomentsState();
}

enum MomentsUnavailableReason {
  /// No couple (or the session is still being established).
  notPaired,

  /// Web never holds private content (D-046).
  needsPhone,

  /// No moments backend is wired in this build yet (D-116).
  notYetAvailable,
}

final class MomentsUnavailable extends MomentsState {
  const MomentsUnavailable(this.reason);

  final MomentsUnavailableReason reason;
}

/// Reading this phone's timeline.
final class MomentsLoading extends MomentsState {
  const MomentsLoading();
}

/// Why the newest moments might not be here.
enum MomentsNotice {
  /// The last check for new moments did not reach the server.
  offline,

  /// The two phones are not connected yet (no shared group, or a device
  /// to remove first).
  connecting,
}

/// The timeline. Empty is a normal, honest state.
final class MomentsReady extends MomentsState {
  const MomentsReady({
    required this.entries,
    required this.total,
    required this.hasEarlier,
    this.refreshing = false,
    this.notice,
  });

  /// The visible part, newest first (bounded pages, D-115).
  final List<MomentEntry> entries;

  /// How many moments this phone holds.
  final int total;
  final bool hasEarlier;

  /// A check for new moments is running; what is shown stays.
  final bool refreshing;
  final MomentsNotice? notice;

  bool get isEmpty => entries.isEmpty;
}

/// This phone is not a trusted device any more (revoked, pending, removed
/// from the couple's conversation). Nothing private is shown (D-115).
final class MomentsBlocked extends MomentsState {
  const MomentsBlocked();
}

/// The timeline could not be read at all.
final class MomentsFailed extends MomentsState {
  const MomentsFailed(this.failure);

  /// Null for a local problem that is not a moments category.
  final MomentFailure? failure;
}
