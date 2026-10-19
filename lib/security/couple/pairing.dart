import 'dart:typed_data';

import 'package:sirf_hum/core/logging/app_logger.dart';
import 'package:sirf_hum/core/logging/log_value.dart';
import 'package:sirf_hum/security/device/device_registration.dart';
import 'package:sirf_hum_crypto/sirf_hum_crypto.dart';

/// One signed pairing step (D-101). Each is authorized by this device's key
/// over a single-use server challenge bound to the step and its subject.
enum PairingStep { create, accept, confirm, reject, cancel }

/// Pairing failure categories (functions/src/couple/state.ts plus the device
/// categories a step can hit). Never carries data.
enum PairingFailure {
  /// The invitation cannot be used, for whatever reason (uniform by design:
  /// unknown, used, expired, cancelled, or the inviter cannot pair).
  invitationInvalid,

  /// No such pairing for this account.
  pairingNotFound,

  /// The pairing is not in a state that allows this step.
  pairingNotOpen,
  pairingExpired,

  /// A participant's trust changed (identity reset, device revoked): start
  /// a new invitation.
  pairingInvalidated,

  /// This account already takes part in another open pairing.
  pairingInProgress,
  alreadyPaired,

  /// An identity reset is pending on this account (D-082).
  identityResetPending,

  /// This device is not active, or its proof or challenge was refused.
  deviceNotTrusted,
  challengeRefused,
  rateLimited,
  unauthenticated,
  invalidRequest,

  /// Network, App Check or backend unavailable; safe to retry later.
  unavailable;

  /// Unknown categories are [unavailable] (retryable), never success.
  static PairingFailure fromServer(String? category) => switch (category) {
    'invitation_invalid' => invitationInvalid,
    'pairing_not_found' => pairingNotFound,
    'pairing_not_open' => pairingNotOpen,
    'pairing_expired' => pairingExpired,
    'pairing_invalidated' => pairingInvalidated,
    'pairing_in_progress' => pairingInProgress,
    'already_paired' => alreadyPaired,
    'identity_reset_pending' => identityResetPending,
    'device_not_active' ||
    'device_not_found' ||
    'proof_invalid' ||
    'certificate_invalid' => deviceNotTrusted,
    'challenge_invalid' || 'challenge_expired' => challengeRefused,
    'rate_limited' => rateLimited,
    'unauthenticated' => unauthenticated,
    'invalid_argument' => invalidRequest,
    _ => unavailable,
  };
}

class PairingException implements Exception {
  const PairingException(this.failure);

  final PairingFailure failure;

  @override
  String toString() => 'PairingException(${failure.name})';
}

/// A single-use server challenge. Public values only.
class PairingChallenge {
  const PairingChallenge({required this.challengeId, required this.challenge});

  final String challengeId;
  final Uint8List challenge;

  @override
  String toString() => 'PairingChallenge(<redacted>)';
}

/// What the inviter shares (as a link or QR, UI phase). The token is a
/// bearer secret until redeemed: it is never logged or printed.
class PairingInvitation {
  const PairingInvitation({
    required this.pairingId,
    required this.token,
    required this.expiresAt,
  });

  /// 16 random bytes, base64url without padding.
  static final tokenPattern = RegExp(r'^[A-Za-z0-9_-]{22}$');

  final String pairingId;
  final String token;

  /// Server-decided; for display only.
  final DateTime expiresAt;

  @override
  String toString() => 'PairingInvitation(<redacted>)';
}

/// The invitee's view after accepting: both people compare [code] before
/// the inviter confirms.
class PairingAcceptance {
  const PairingAcceptance({
    required this.pairingId,
    required this.code,
    required this.partnerDisplayName,
    required this.confirmBy,
  });

  final String pairingId;
  final String code;
  final String? partnerDisplayName;
  final DateTime confirmBy;

  @override
  String toString() => 'PairingAcceptance(<redacted>)';
}

/// The couple both accounts now belong to, and its conversation (D-104).
class CoupleMembership {
  const CoupleMembership({
    required this.coupleId,
    required this.conversationId,
  });

  final String coupleId;
  final String conversationId;

  @override
  String toString() => 'CoupleMembership(<redacted>)';
}

/// This account's own pairing state, as the server reports it.
sealed class PairingState {
  const PairingState();

  static final _id = RegExp(r'^[0-9a-f]{32}$');
  static final _code = RegExp(r'^\d{6}$');

  /// Strict parse of `getPairingState`; anything unexpected is a failure,
  /// never a state the UI would act on.
  static PairingState parse(Map<Object?, Object?> data) {
    DateTime at(Object? millis) => millis is int
        ? DateTime.fromMillisecondsSinceEpoch(millis, isUtc: true)
        : throw const PairingException(PairingFailure.unavailable);
    String id(Object? value) => value is String && _id.hasMatch(value)
        ? value
        : throw const PairingException(PairingFailure.unavailable);
    return switch (data['state']) {
      'none' => const PairingNone(),
      'paired' => PairingPaired(
        coupleId: data['coupleId'] == null ? null : id(data['coupleId']),
        conversationId: data['conversationId'] == null
            ? null
            : id(data['conversationId']),
      ),
      'invited' => PairingInvited(
        pairingId: id(data['pairingId']),
        expiresAt: at(data['expiresAtMillis']),
      ),
      'awaiting_confirmation' => PairingAwaitingConfirmation(
        isInviter: switch (data['role']) {
          'inviter' => true,
          'invitee' => false,
          _ => throw const PairingException(PairingFailure.unavailable),
        },
        pairingId: id(data['pairingId']),
        code: switch (data['confirmationCode']) {
          final String c when _code.hasMatch(c) => c,
          _ => throw const PairingException(PairingFailure.unavailable),
        },
        partnerDisplayName: switch (data['partnerDisplayName']) {
          final String name => name,
          null => null,
          _ => throw const PairingException(PairingFailure.unavailable),
        },
        expiresAt: at(data['expiresAtMillis']),
      ),
      _ => throw const PairingException(PairingFailure.unavailable),
    };
  }
}

class PairingNone extends PairingState {
  const PairingNone();
}

/// An invitation is out; nobody has accepted it yet.
class PairingInvited extends PairingState {
  const PairingInvited({required this.pairingId, required this.expiresAt});

  final String pairingId;
  final DateTime expiresAt;
}

/// Someone accepted; the inviter decides. Both sides show [code].
class PairingAwaitingConfirmation extends PairingState {
  const PairingAwaitingConfirmation({
    required this.isInviter,
    required this.pairingId,
    required this.code,
    required this.partnerDisplayName,
    required this.expiresAt,
  });

  final bool isInviter;
  final String pairingId;
  final String code;
  final String? partnerDisplayName;
  final DateTime expiresAt;

  @override
  String toString() => 'PairingAwaitingConfirmation(<redacted>)';
}

class PairingPaired extends PairingState {
  const PairingPaired({required this.coupleId, required this.conversationId});

  final String? coupleId;
  final String? conversationId;
}

/// Port to the pairing callables (functions/src/couple/pairing.ts).
/// Failures are [PairingException]s.
abstract interface class PairingBackend {
  Future<PairingChallenge> requestChallenge({
    required String deviceIdHex,
    required PairingStep step,
    String? token,
    String? pairingId,
  });

  Future<PairingInvitation> create(SignedPairingStep step);

  Future<PairingAcceptance> accept(SignedPairingStep step, String token);

  Future<CoupleMembership> confirm(SignedPairingStep step, String pairingId);

  Future<void> reject(SignedPairingStep step, String pairingId);

  Future<void> cancel(SignedPairingStep step, String pairingId);

  Future<PairingState> state();
}

/// A challenge answered with this device's key (64-byte proof).
class SignedPairingStep {
  const SignedPairingStep({
    required this.deviceIdHex,
    required this.challengeId,
    required this.proof,
  });

  final String deviceIdHex;
  final String challengeId;
  final Uint8List proof;

  @override
  String toString() => 'SignedPairingStep(<redacted>)';
}

/// Drives pairing for this device (Prompt 12, D-101–D-104). Every step asks
/// for a fresh challenge and answers it with the device key under the
/// `pairing` proof purpose, so the server can tell an active, trusted device
/// from a stolen session. This class never decides trust or membership: the
/// server does, transactionally. No UI yet.
class PairingService {
  PairingService({required this.core, required PairingBackend backend})
    : _backend = backend;

  final CryptoCore core;
  final PairingBackend _backend;

  String get _deviceHex =>
      PendingDeviceRegistration.hexOf(core.publicIdentity().deviceId);

  /// Starts an invitation; share its token out of band (UI phase).
  Future<PairingInvitation> createInvitation() =>
      _run(PairingStep.create, _backend.create);

  /// Redeems a partner's invitation token. Malformed tokens fail locally,
  /// with the same category as any unusable invitation.
  Future<PairingAcceptance> acceptInvitation(String token) async {
    if (!PairingInvitation.tokenPattern.hasMatch(token)) {
      _log(PairingStep.accept, PairingFailure.invitationInvalid.name);
      throw const PairingException(PairingFailure.invitationInvalid);
    }
    return _run(
      PairingStep.accept,
      (s) => _backend.accept(s, token),
      token: token,
    );
  }

  /// The inviter confirms the account that accepted (after comparing codes).
  Future<CoupleMembership> confirm(String pairingId) => _run(
    PairingStep.confirm,
    (s) => _backend.confirm(s, pairingId),
    pairingId: pairingId,
  );

  /// The inviter refuses the account that accepted.
  Future<void> reject(String pairingId) => _run(
    PairingStep.reject,
    (s) => _backend.reject(s, pairingId),
    pairingId: pairingId,
  );

  /// Either participant withdraws an open pairing.
  Future<void> cancel(String pairingId) => _run(
    PairingStep.cancel,
    (s) => _backend.cancel(s, pairingId),
    pairingId: pairingId,
  );

  Future<PairingState> state() => _backend.state();

  Future<T> _run<T>(
    PairingStep step,
    Future<T> Function(SignedPairingStep) send, {
    String? token,
    String? pairingId,
  }) async {
    try {
      final device = _deviceHex;
      final c = await _backend.requestChallenge(
        deviceIdHex: device,
        step: step,
        token: token,
        pairingId: pairingId,
      );
      final result = await send(
        SignedPairingStep(
          deviceIdHex: device,
          challengeId: c.challengeId,
          proof: core.deviceProof(DeviceProofPurpose.pairing, c.challenge),
        ),
      );
      _log(step, 'ok');
      return result;
    } on PairingException catch (e) {
      _log(step, e.failure.name);
      rethrow;
    }
  }

  // Step and outcome category only: never tokens, codes, IDs or names.
  static void _log(PairingStep step, String outcome) => AppLogger.info(
    'pairing_step',
    fields: {
      'step': SafeLogString(step.name),
      'outcome': SafeLogString(outcome),
    },
  );
}
