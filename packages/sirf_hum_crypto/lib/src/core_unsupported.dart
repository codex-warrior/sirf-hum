// Platforms without dart:ffi (Web). Web V1 has no private-content E2EE
// (D-046): every operation fails closed. Nothing here degrades to an
// unencrypted path.
import 'dart:typed_data';

import 'package:sirf_hum_crypto/src/lineage.dart';
import 'package:sirf_hum_crypto/src/types.dart';

const int expectedAbiVersion = 6;

Never _unsupported() =>
    throw const CryptoException(CryptoErrorCode.unsupported);

final class CryptoCore {
  CryptoCore._();

  static bool get isAvailable => false;

  static CryptoCore initialize({
    required String directory,
    required KeyStoreKind keyStore,
  }) => _unsupported();

  static CryptoCore initializeWithPlatformKey({
    required String directory,
    required Uint8List storeKey,
  }) {
    wipeBytes(storeKey);
    return _unsupported();
  }

  void close() {}

  void checkAccount(AccountId account) => _unsupported();

  Uint8List deviceProof(DeviceProofPurpose purpose, Uint8List challenge) =>
      _unsupported();

  Uint8List approveDevice({
    required Uint8List newCertificate,
    required Uint8List challenge,
    required int expiresAtUnix,
  }) => _unsupported();

  static int approvalCode({
    required Uint8List newCertificate,
    required Uint8List challenge,
  }) => _unsupported();

  RecoveryKeyBundle createRecoveryKey({
    required Uint8List challenge,
    required int expiresAtUnix,
  }) => _unsupported();

  RecoveryApprovalResult recoveryApproval({
    required String recoveryKey,
    required Uint8List challenge,
    required int expiresAtUnix,
  }) => _unsupported();

  Uint8List signRevocation({
    required Uint8List revokedCertificate,
    required RevocationReason reason,
    required Uint8List challenge,
    required int expiresAtUnix,
  }) => _unsupported();

  Uint8List signResetCancellation({
    required Uint8List challenge,
    required int expiresAtUnix,
  }) => _unsupported();

  int observeTrustEpoch(int epoch) => _unsupported();

  static List<DeviceId> verifyLineage(LineageRequest request) => _unsupported();

  PublicIdentity createIdentity(AccountId account) => _unsupported();

  PublicIdentity publicIdentity() => _unsupported();

  void trustVerifiedPersonKey(PersonKey key) => _unsupported();

  void revokeDevice(DeviceId device) => _unsupported();

  Uint8List keyPackage() => _unsupported();

  GroupId createGroup() => _unsupported();

  AddMemberResult addMember(GroupId group, Uint8List keyPackage) =>
      _unsupported();

  Uint8List removeMember(GroupId group, DeviceId device) => _unsupported();

  Uint8List selfUpdate(GroupId group) => _unsupported();

  GroupId join(Uint8List welcome) => _unsupported();

  Uint8List encrypt(GroupId group, Uint8List plaintext) => _unsupported();

  IncomingResult processIncoming(Uint8List message) => _unsupported();

  int epoch(GroupId group) => _unsupported();

  List<RosterEntry> roster(GroupId group) => _unsupported();

  int trustLineage(LineageRequest request, int trustEpoch) => _unsupported();

  StagedCommit createConversationGroup(
    ConversationId conversation,
    List<Uint8List> keyPackages,
  ) => _unsupported();

  StagedCommit stageAddMembers(
    ConversationId conversation,
    List<Uint8List> keyPackages,
  ) => _unsupported();

  StagedCommit stageRemoveMembers(
    ConversationId conversation,
    List<DeviceId> devices,
  ) => _unsupported();

  StagedCommit stageSelfUpdate(ConversationId conversation) => _unsupported();

  int? stagedCommitEpoch(ConversationId conversation) => _unsupported();

  int confirmCommit(ConversationId conversation, int fromEpoch) =>
      _unsupported();

  void discardCommit(ConversationId conversation, int fromEpoch) =>
      _unsupported();

  IncomingResult processCommit(
    ConversationId conversation, {
    required int epoch,
    required DeviceId sender,
    required Uint8List commit,
  }) => _unsupported();

  int joinConversation(ConversationId conversation, Uint8List welcome) =>
      _unsupported();

  SentMessage sendMessage(ConversationId conversation, Uint8List payload) =>
      _unsupported();

  SentMessage reencryptMessage(ConversationId conversation, MessageId id) =>
      _unsupported();

  void markMessageSent(
    ConversationId conversation,
    MessageId id, {
    required int serverTimeMs,
  }) => _unsupported();

  ReceivedMessage receiveMessage(
    ConversationId conversation, {
    required MessageId messageId,
    required DeviceId sender,
    required int epoch,
    required int schemaVersion,
    required int protocolVersion,
    required Uint8List ciphertext,
    required int serverTimeMs,
  }) => _unsupported();

  String? deviceAccount(DeviceId device) => _unsupported();

  List<LocalMessage> history(ConversationId conversation) => _unsupported();

  void deleteLocalMessage(ConversationId conversation, MessageId id) =>
      _unsupported();

  SentMedia sendMedia(
    ConversationId conversation, {
    required String inputPath,
    required String mediaDirectory,
    required MediaClass mediaClass,
  }) => _unsupported();

  Uint8List openMedia(ConversationId conversation, MessageId id, String path) =>
      _unsupported();

  void wipe() => _unsupported();
}
