import 'package:flutter/foundation.dart';
import 'package:sirf_hum/security/verification/partner_verification.dart';

/// What the partner-verification page shows (D-128). ID-free: the safety
/// number and QR text are shown on screen, never logged or persisted.
@immutable
sealed class VerificationViewState {
  const VerificationViewState();
}

enum VerificationUnavailableReason {
  /// Not paired: there is nobody to verify.
  notPaired,

  /// Web never holds private keys (D-046): verification happens on a phone.
  needsPhone,

  /// No messaging backend is wired in this build (D-116, D-121).
  notYetAvailable,
}

final class VerificationUnavailable extends VerificationViewState {
  const VerificationUnavailable(this.reason);

  final VerificationUnavailableReason reason;
}

final class VerificationLoading extends VerificationViewState {
  const VerificationLoading();
}

/// Something worth saying after an action, shown once.
enum VerificationNotice {
  /// The scanned code is not your safety number: nothing was trusted.
  scanMismatch,

  /// You said the numbers do not match: nothing was trusted.
  reportedMismatch,

  /// The number changed while you were looking at it: compare the new one.
  changedWhileShown,

  /// This identity was removed and can never be verified again.
  revoked,

  /// Just verified.
  verified,
}

final class VerificationReady extends VerificationViewState {
  const VerificationReady({
    required this.status,
    required this.groups,
    required this.qrText,
    required this.partnerResetCount,
    required this.partnerDeviceCount,
    this.notice,
    this.busy = false,
  });

  final VerificationStatus status;

  /// 12 groups of 5 digits.
  final List<String> groups;
  final String qrText;
  final int partnerResetCount;
  final int partnerDeviceCount;
  final VerificationNotice? notice;

  /// A confirmation is running: buttons are disabled.
  final bool busy;

  bool get verified => status == VerificationStatus.verified;
}

enum VerificationFailedReason {
  /// This phone's own identity is not proven (not active or not trusted).
  thisPhone,

  /// The partner has no identity that can be verified right now.
  partner,

  /// The server answered with an older view than this phone has seen.
  staleServer,

  /// Anything else (offline, unexpected answer).
  unknown,
}

final class VerificationFailed extends VerificationViewState {
  const VerificationFailed(this.reason);

  final VerificationFailedReason reason;
}
