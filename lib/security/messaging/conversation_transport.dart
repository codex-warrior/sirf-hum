import 'dart:typed_data';

import 'package:sirf_hum/security/messaging/message_envelope.dart';
import 'package:sirf_hum_crypto/sirf_hum_crypto.dart';

/// The server's view of a conversation (`conversations/{id}`, D-086).
class ConversationRecord {
  const ConversationRecord({
    required this.members,
    required this.epoch,
    required this.active,
  });

  /// The two member accounts (server-authoritative).
  final List<String> members;

  /// The last epoch whose commit the server accepted, plus one (0 before
  /// the group exists).
  final int epoch;
  final bool active;

  @override
  String toString() => 'ConversationRecord(epoch: $epoch, active: $active)';
}

/// A device's published KeyPackage (public).
class PublishedKeyPackage {
  PublishedKeyPackage({
    required this.accountId,
    required this.deviceIdHex,
    required Uint8List keyPackage,
  }) : keyPackage = Uint8List.fromList(keyPackage);

  final String accountId;
  final String deviceIdHex;
  final Uint8List keyPackage;

  @override
  String toString() => 'PublishedKeyPackage(<redacted>)';
}

/// The accepted commit for one epoch (create-only, first wins, D-088).
class CommitRecord {
  CommitRecord({
    required this.epoch,
    required this.senderAccountId,
    required this.senderDeviceIdHex,
    required Uint8List commit,
  }) : commit = Uint8List.fromList(commit);

  final int epoch;
  final String senderAccountId;
  final String senderDeviceIdHex;
  final Uint8List commit;

  @override
  String toString() => 'CommitRecord(epoch: $epoch, <redacted>)';
}

/// A Welcome for one new device, written beside its commit.
class WelcomeRecord {
  WelcomeRecord({
    required this.epoch,
    required this.targetDeviceIdHex,
    required Uint8List welcome,
  }) : welcome = Uint8List.fromList(welcome);

  /// The epoch of the commit it belongs to; the device joins at epoch + 1.
  final int epoch;
  final String targetDeviceIdHex;
  final Uint8List welcome;

  @override
  String toString() => 'WelcomeRecord(epoch: $epoch, <redacted>)';
}

/// A single-use server challenge for one commit, by one device, at one
/// epoch (Prompt 17B, D-127). Its [nonce] goes into
/// `commitAuthorizationChallenge`; the device key signs the result.
class CommitChallenge {
  CommitChallenge({required this.challengeId, required Uint8List nonce})
    : nonce = Uint8List.fromList(nonce);

  final String challengeId;
  final Uint8List nonce;

  @override
  String toString() => 'CommitChallenge(<redacted>)';
}

/// The device's signed authorization for exactly one commit (D-127).
class CommitAuthorization {
  CommitAuthorization({required this.challengeId, required Uint8List proof})
    : proof = Uint8List.fromList(proof);

  final String challengeId;

  /// Device proof, purpose `commit` (64 bytes).
  final Uint8List proof;

  @override
  String toString() => 'CommitAuthorization(<redacted>)';
}

/// How the server answered a create-only write.
enum WriteOutcome {
  /// Written.
  accepted,

  /// Refused by the server's rules (document exists, epoch moved, device
  /// not active, …). The caller re-reads to learn which.
  refused,

  /// Not reached (offline, timeout): retry later. The write may or may not
  /// have landed; the caller resolves that by reading.
  unavailable,
}

class WriteResult {
  const WriteResult(this.outcome, {this.serverTimeMs});

  final WriteOutcome outcome;

  /// The server's time for an accepted message, when known.
  final int? serverTimeMs;
}

/// Why a transport call failed (categories only, never data).
enum TransportFailure { unavailable, denied, malformed }

class TransportException implements Exception {
  const TransportException(this.failure);

  final TransportFailure failure;

  @override
  String toString() => 'TransportException(${failure.name})';
}

/// Port to the server (D-072): implemented by
/// `lib/infrastructure/firebase/firestore_conversation_transport.dart`.
/// Carries ciphertext, MLS handshake bytes and public metadata only.
abstract interface class ConversationTransport {
  Future<ConversationRecord> conversation(ConversationId id);

  /// Publishes (or replaces) this account's device KeyPackage.
  Future<void> publishKeyPackage(ConversationId id, PublishedKeyPackage kp);

  Future<List<PublishedKeyPackage>> keyPackages(ConversationId id);

  /// A single-use challenge for this device to authorize a commit from
  /// [fromEpoch] (D-127). Throws [TransportException] when refused (device
  /// not active, epoch already moved, not a member) or unreachable.
  Future<CommitChallenge> requestCommitChallenge(
    ConversationId id, {
    required String deviceIdHex,
    required int fromEpoch,
  });

  /// Asks the server to accept the commit for `commit.epoch`, the epoch move
  /// and the Welcomes in one transaction (first commit wins, D-088). The
  /// server verifies [authorization] against this device's key first: a
  /// Firebase session alone can never move the epoch (D-127).
  Future<WriteResult> submitCommit(
    ConversationId id,
    CommitRecord commit,
    List<WelcomeRecord> welcomes,
    CommitAuthorization authorization,
  );

  Future<CommitRecord?> commit(ConversationId id, int epoch);

  Future<List<WelcomeRecord>> welcomesFor(ConversationId id, String deviceHex);

  Future<WriteResult> submitMessage(
    ConversationId id,
    EncryptedMessageEnvelope envelope,
  );

  Future<EncryptedMessageEnvelope?> message(ConversationId id, String hexId);

  /// Every stored message of one epoch, in server-time order. Documents
  /// that do not parse are skipped and counted ([malformedCount]).
  Future<({List<EncryptedMessageEnvelope> messages, int malformedCount})>
  messagesAtEpoch(ConversationId id, int epoch);
}
