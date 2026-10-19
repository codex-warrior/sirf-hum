import 'dart:convert';
import 'dart:typed_data';

/// One activation in an account's trust chain (D-084), as stored by the
/// server next to the activated device. Public material only.
sealed class LineageLink {
  const LineageLink({this.protocolVersion = 1});

  final int protocolVersion;
}

/// [newCertificate] was approved by [approverCertificate]'s PIK.
final class ApprovalLink extends LineageLink {
  const ApprovalLink({
    super.protocolVersion,
    required this.approverCertificate,
    required this.newCertificate,
    required this.challenge,
    required this.expiresAtUnix,
    required this.signature,
  });

  final Uint8List approverCertificate;
  final Uint8List newCertificate;
  final Uint8List challenge;
  final int expiresAtUnix;
  final Uint8List signature;
}

/// [newCertificate] was approved by a recovery key that
/// [registrarCertificate]'s PIK registered.
final class RecoveryLink extends LineageLink {
  const RecoveryLink({
    super.protocolVersion,
    required this.registrarCertificate,
    required this.recoveryPublicKey,
    required this.registrationChallenge,
    required this.registrationExpiresAtUnix,
    required this.registrationSignature,
    required this.newCertificate,
    required this.challenge,
    required this.expiresAtUnix,
    required this.signature,
  });

  final Uint8List registrarCertificate;
  final Uint8List recoveryPublicKey;
  final Uint8List registrationChallenge;
  final int registrationExpiresAtUnix;
  final Uint8List registrationSignature;
  final Uint8List newCertificate;
  final Uint8List challenge;
  final int expiresAtUnix;
  final Uint8List signature;
}

/// A signed revocation (D-081).
final class SignedRevocation {
  const SignedRevocation({
    this.protocolVersion = 1,
    required this.revokerCertificate,
    required this.revokedCertificate,
    required this.reason,
    required this.challenge,
    required this.expiresAtUnix,
    required this.signature,
  });

  final int protocolVersion;
  final Uint8List revokerCertificate;
  final Uint8List revokedCertificate;

  /// Wire value (1 removed, 2 lost, 3 stolen, 4 compromised).
  final int reason;
  final Uint8List challenge;
  final int expiresAtUnix;
  final Uint8List signature;
}

/// Everything the Rust core needs to verify an account's lineage on the
/// device. Encodes to the format in native/src/lineage.rs (an encoding, not
/// cryptography; all verification happens in Rust).
final class LineageRequest {
  const LineageRequest({
    required this.accountId,
    required this.rootCertificate,
    this.links = const [],
    this.revocations = const [],
    this.revokedDeviceIds = const [],
  });

  final String accountId;

  /// The account's first device. Its trust comes from partner verification
  /// of its PIK, never from the server.
  final Uint8List rootCertificate;
  final List<LineageLink> links;
  final List<SignedRevocation> revocations;

  /// Server-asserted revocations (e.g. identity reset), 16 bytes each.
  final List<Uint8List> revokedDeviceIds;

  Uint8List encode() {
    final out = BytesBuilder(copy: false)
      ..addByte(1)
      .._var(utf8.encode(accountId))
      .._var(rootCertificate)
      .._u32(links.length);
    for (final link in links) {
      switch (link) {
        case ApprovalLink():
          out
            ..addByte(1)
            ..addByte(link.protocolVersion)
            .._var(link.approverCertificate)
            .._var(link.newCertificate)
            .._var(link.challenge)
            .._u64(link.expiresAtUnix)
            .._var(link.signature);
        case RecoveryLink():
          out
            ..addByte(2)
            ..addByte(link.protocolVersion)
            .._var(link.registrarCertificate)
            .._var(link.recoveryPublicKey)
            .._var(link.registrationChallenge)
            .._u64(link.registrationExpiresAtUnix)
            .._var(link.registrationSignature)
            .._var(link.newCertificate)
            .._var(link.challenge)
            .._u64(link.expiresAtUnix)
            .._var(link.signature);
      }
    }
    out._u32(revocations.length);
    for (final r in revocations) {
      out
        ..addByte(r.protocolVersion)
        .._var(r.revokerCertificate)
        .._var(r.revokedCertificate)
        ..addByte(r.reason)
        .._var(r.challenge)
        .._u64(r.expiresAtUnix)
        .._var(r.signature);
    }
    out._u32(revokedDeviceIds.length);
    for (final id in revokedDeviceIds) {
      out.add(id);
    }
    return out.takeBytes();
  }

  @override
  String toString() => 'LineageRequest(<redacted>)';
}

extension on BytesBuilder {
  void _u32(int value) =>
      add((ByteData(4)..setUint32(0, value, Endian.big)).buffer.asUint8List());

  void _u64(int value) =>
      add((ByteData(8)..setUint64(0, value, Endian.big)).buffer.asUint8List());

  void _var(List<int> bytes) {
    _u32(bytes.length);
    add(bytes);
  }
}
