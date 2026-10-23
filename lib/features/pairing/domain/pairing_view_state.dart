import 'package:sirf_hum/security/couple/pairing.dart';

/// What the pairing screen shows (COUPLE-AND-PAIRING.md, D-101–D-104,
/// D-131). Produced only by `PairingController`; the couple itself exists
/// only once the server says so (the session then becomes paired).
sealed class PairingViewState {
  const PairingViewState();
}

/// Opening this phone's keys and registering it with the server.
final class PairingSettingUp extends PairingViewState {
  const PairingSettingUp();
}

/// This account already has a trusted phone: this one waits for it to
/// approve, showing the code the other phone must show too (D-075).
final class PairingDeviceWaiting extends PairingViewState {
  const PairingDeviceWaiting({required this.code});

  final int code;
}

enum PairingDeviceProblem {
  /// Not a phone (web): keys never live here (D-046).
  needsPhone,

  /// This phone's identity was revoked, rejected or expired on the server.
  removed,

  /// The keys on this phone cannot be opened.
  unreadable,

  /// Network or server; safe to retry.
  failed,
}

final class PairingDeviceUnavailable extends PairingViewState {
  const PairingDeviceUnavailable(this.problem);

  final PairingDeviceProblem problem;
}

/// Nothing open: invite your person, or use their invitation.
final class PairingChoose extends PairingViewState {
  const PairingChoose({this.failure, this.busy = false});

  final PairingFailure? failure;
  final bool busy;
}

/// Entering the invitation someone sent.
final class PairingJoin extends PairingViewState {
  const PairingJoin({this.failure, this.busy = false});

  final PairingFailure? failure;
  final bool busy;
}

/// An invitation is out. [token] is known only on the phone that just
/// created it (the server returns it once); after a restart it is null and
/// the person cancels and invites again if they lost it.
final class PairingInviteOut extends PairingViewState {
  const PairingInviteOut({
    required this.pairingId,
    required this.expiresAt,
    this.token,
    this.failure,
    this.busy = false,
  });

  final String pairingId;
  final DateTime expiresAt;
  final String? token;
  final PairingFailure? failure;
  final bool busy;

  @override
  String toString() => 'PairingInviteOut(<redacted>)';
}

/// The invitee: read [code] out to the inviter, who types it (D-131).
final class PairingShowCode extends PairingViewState {
  const PairingShowCode({
    required this.pairingId,
    required this.code,
    this.partnerName,
    this.failure,
    this.busy = false,
  });

  final String pairingId;
  final String code;
  final String? partnerName;
  final PairingFailure? failure;
  final bool busy;

  @override
  String toString() => 'PairingShowCode(<redacted>)';
}

/// The inviter: someone accepted; type the code their phone shows, or
/// refuse them.
final class PairingEnterCode extends PairingViewState {
  const PairingEnterCode({
    required this.pairingId,
    this.partnerName,
    this.failure,
    this.busy = false,
  });

  final String pairingId;
  final String? partnerName;
  final PairingFailure? failure;
  final bool busy;

  @override
  String toString() => 'PairingEnterCode(<redacted>)';
}
