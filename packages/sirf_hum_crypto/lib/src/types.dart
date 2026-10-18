import 'dart:convert';
import 'dart:typed_data';

/// Stable error categories. Codes match `native/src/error.rs` (`CoreError`)
/// and never change meaning; new categories get new codes.
enum CryptoErrorCode {
  invalidInput(-1),
  inputTooLarge(-2),
  invalidCredential(-3),
  unauthorizedDevice(-4),
  malformedMessage(-5),
  authenticationFailure(-6),
  replay(-7),
  staleEpoch(-8),
  unknownGroup(-9),
  protocolViolation(-10),
  stateCorruption(-11),
  persistenceFailure(-12),
  rollbackFailure(-13),
  unsupported(-14),
  internalCryptoFailure(-15),
  identityState(-16),
  internal(-17),
  accountMismatch(-18);

  const CryptoErrorCode(this.code);

  final int code;

  /// Unknown codes map to [internal]: never guess a more specific meaning.
  static CryptoErrorCode fromCode(int code) => values.firstWhere(
    (e) => e.code == code,
    orElse: () => CryptoErrorCode.internal,
  );
}

/// A crypto-core failure. Carries only the category: no message bytes, keys
/// or native strings, so it is safe to log and to report.
class CryptoException implements Exception {
  const CryptoException(this.code);

  final CryptoErrorCode code;

  @override
  String toString() => 'CryptoException(${code.name})';
}

/// Where the core's key-encryption key comes from.
///
/// The test adapters are **insecure** and refused in release builds; never
/// use them for real users. [platform] is the Android Keystore / iOS Keychain
/// adapter (D-066), whose key the app passes in.
enum KeyStoreKind {
  /// KEK lives in memory only; state is unreadable after restart.
  insecureTestEphemeral(1),

  /// KEK is a plaintext file next to the state. Restart-capable tests only.
  insecureTestFile(2),

  /// The platform key store (Android Keystore / iOS Keychain, D-066). Opened
  /// through `CryptoCore.initializeWithPlatformKey`, never `initialize`.
  platform(100);

  const KeyStoreKind(this.wireValue);

  final int wireValue;
}

/// What a device proof of possession is for (D-070). Each purpose is a
/// separate signed domain; values match the native ABI.
enum DeviceProofPurpose {
  activation(1);

  const DeviceProofPurpose(this.wireValue);

  final int wireValue;
}

/// The account a device belongs to (validated: 1–128 UTF-8 bytes).
class AccountId {
  AccountId(this.value) {
    final length = utf8.encode(value).length;
    if (length == 0 || length > 128) {
      throw const CryptoException(CryptoErrorCode.invalidInput);
    }
  }

  final String value;

  @override
  bool operator ==(Object other) => other is AccountId && other.value == value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => 'AccountId(<redacted>)';
}

/// Fixed-length public identifier wrapper with defensive copies and
/// redacted printing.
abstract class ByteIdentifier {
  ByteIdentifier(Uint8List bytes, int length)
    : bytes = Uint8List.fromList(bytes) {
    if (length >= 0 && bytes.length != length) {
      throw const CryptoException(CryptoErrorCode.invalidInput);
    }
  }

  final Uint8List bytes;

  @override
  bool operator ==(Object other) =>
      other.runtimeType == runtimeType &&
      other is ByteIdentifier &&
      _equal(other.bytes, bytes);

  @override
  int get hashCode => Object.hashAll(bytes);
}

bool _equal(Uint8List a, Uint8List b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// One device's identifier (16 bytes, derived from its MLS signature key).
class DeviceId extends ByteIdentifier {
  DeviceId(Uint8List bytes) : super(bytes, 16);

  @override
  String toString() => 'DeviceId(<redacted>)';
}

/// A person's public identity key (Ed25519, 32 bytes). Public, but still an
/// identifier: not printed.
class PersonKey extends ByteIdentifier {
  PersonKey(Uint8List bytes) : super(bytes, 32);

  @override
  String toString() => 'PersonKey(<redacted>)';
}

/// An MLS group identifier (opaque).
class GroupId extends ByteIdentifier {
  GroupId(Uint8List bytes) : super(bytes, -1) {
    if (bytes.isEmpty) {
      throw const CryptoException(CryptoErrorCode.invalidInput);
    }
  }

  @override
  String toString() => 'GroupId(<redacted>)';
}

/// Public identity material of this device. Contains no private key.
class PublicIdentity {
  PublicIdentity({
    required this.deviceId,
    required this.personKey,
    required Uint8List certificate,
  }) : certificate = Uint8List.fromList(certificate);

  final DeviceId deviceId;
  final PersonKey personKey;

  /// Device certificate signed by the person key (public).
  final Uint8List certificate;

  @override
  String toString() => 'PublicIdentity(<redacted>)';
}

/// One group member.
class RosterEntry {
  const RosterEntry({required this.deviceId, required this.personKey});

  final DeviceId deviceId;
  final PersonKey personKey;

  @override
  String toString() => 'RosterEntry(<redacted>)';
}

/// Outputs of adding a member: the commit for existing members and the
/// Welcome for the new device. Both are MLS wire messages (not secrets).
class AddMemberResult {
  AddMemberResult({required Uint8List commit, required Uint8List welcome})
    : commit = Uint8List.fromList(commit),
      welcome = Uint8List.fromList(welcome);

  final Uint8List commit;
  final Uint8List welcome;

  @override
  String toString() => 'AddMemberResult(<redacted>)';
}

/// The result of processing one incoming MLS message.
sealed class IncomingResult {
  const IncomingResult();
}

/// A decrypted application message. [plaintext] is private content: never
/// log, persist unencrypted, or send it anywhere.
final class IncomingApplication extends IncomingResult {
  IncomingApplication(this.plaintext);

  final Uint8List plaintext;

  @override
  String toString() => 'IncomingApplication(<redacted>)';
}

/// A commit was validated and applied; the group is now at [epoch].
final class IncomingCommit extends IncomingResult {
  const IncomingCommit(this.epoch);

  final int epoch;

  @override
  String toString() => 'IncomingCommit(epoch: $epoch)';
}

/// This device was removed; its local group state has been deleted.
final class IncomingRemoved extends IncomingResult {
  const IncomingRemoved();

  @override
  String toString() => 'IncomingRemoved()';
}
