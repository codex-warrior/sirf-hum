// Platforms without dart:ffi (Web). Web V1 has no private-content E2EE
// (D-046): every operation fails closed. Nothing here degrades to an
// unencrypted path.
import 'dart:typed_data';

import 'package:sirf_hum_crypto/src/types.dart';

const int expectedAbiVersion = 3;

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

  void wipe() => _unsupported();
}
