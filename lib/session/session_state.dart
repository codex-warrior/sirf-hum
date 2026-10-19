import 'package:sirf_hum/security/couple/couple_profiles.dart';

/// Where this installation stands: signed in or not, and the account's
/// couple as the **server** reports it (D-106).
///
/// Deliberately ID-free: no account, couple, pairing, conversation or device
/// identifiers, codes or tokens. Everything here is safe to render, and no
/// screen can learn an internal ID from it. The only producer is
/// `SessionController`; widgets never construct these.
sealed class SessionState {
  const SessionState();
}

/// Restoring the session or asking the server. Shown as a skeleton.
final class SessionStarting extends SessionState {
  const SessionStarting();
}

final class SessionSignedOut extends SessionState {
  const SessionSignedOut();
}

/// Signed in, no couple, no open pairing.
final class SessionNotPaired extends SessionState {
  const SessionNotPaired({required this.canPairHere});

  /// False on web: pairing needs this device's key, which web never holds
  /// (WEB-SECURITY, D-046). A UX hint only; the server checks the device.
  final bool canPairHere;
}

enum PairingStage {
  /// This account's invitation is out; nobody has accepted yet.
  invitationSent,

  /// Someone accepted this account's invitation; this account confirms.
  partnerAccepted,

  /// This account accepted; the inviter has not confirmed yet.
  waitingForPartner,
}

/// Signed in with an open pairing.
final class SessionPairing extends SessionState {
  const SessionPairing({required this.stage, required this.canPairHere});

  final PairingStage stage;
  final bool canPairHere;
}

/// The server says this account belongs to a couple.
final class SessionPaired extends SessionState {
  const SessionPaired({required this.names});

  final CoupleNames names;
}

enum SessionProblem {
  /// Network, App Check or backend unavailable. Retryable.
  unreachable,

  /// The account session itself could not start (Firebase failed to
  /// initialize). Not retryable in-process: the app must be reopened.
  startFailed,

  /// The server no longer accepts this sign-in (expired, disabled account).
  signInAgain,
}

/// The account or its couple state could not be established. Never treated
/// as any other state.
final class SessionUnavailable extends SessionState {
  const SessionUnavailable(this.problem);

  final SessionProblem problem;
}
