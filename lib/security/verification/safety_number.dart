import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:sirf_hum_crypto/sirf_hum_crypto.dart';

/// The couple's safety number (Prompt 17B, D-128).
///
/// What it identifies: each person's **root person key (PIK)** — the key at
/// the top of their signed device lineage (D-084, D-085) — bound to their
/// account. Every other device of a person is trusted only because it
/// descends from that root by signatures, so comparing the two roots once
/// covers every device either person adds later. A server that substitutes
/// either root changes the number.
///
/// ```text
/// fingerprint(account, root) = SHA-256( "SirfHum-SafetyNumber-v1" | u8 1
///                                      | u32 len | account (UTF-8)
///                                      | u32 len | root PIK (32) )
/// digits(fp)  = for i in 0..5: (fp[5i..5i+5] as u40 BE) mod 100000, 5 digits
/// number      = digits(fp of the account that sorts first)
///             ‖ digits(fp of the other)          (60 digits, 12 groups)
/// QR payload  = "SHSN" | u8 1 | fp first (32) | fp second (32)   (69 bytes)
/// ```
///
/// Both phones compute the same number and payload. 30 digits per person
/// (~99.7 bits) make a second key with a matching half infeasible to find;
/// the full 32-byte fingerprints are compared when the QR code is scanned.
/// A hash only: no new primitive, no key material leaves the core.
class SafetyNumber {
  SafetyNumber._(this.groups, this._payload);

  factory SafetyNumber.of({
    required String ownAccount,
    required PersonKey ownRoot,
    required String partnerAccount,
    required PersonKey partnerRoot,
  }) {
    if (ownAccount == partnerAccount) {
      throw ArgumentError('a couple has two accounts');
    }
    final own = personFingerprint(ownAccount, ownRoot);
    final partner = personFingerprint(partnerAccount, partnerRoot);
    final ownFirst = ownAccount.compareTo(partnerAccount) < 0;
    final first = ownFirst ? own : partner;
    final second = ownFirst ? partner : own;
    final payload = BytesBuilder(copy: false)
      ..add(ascii.encode(_magic))
      ..addByte(_version)
      ..add(first)
      ..add(second);
    return SafetyNumber._(
      List.unmodifiable([..._digits(first), ..._digits(second)]),
      payload.takeBytes(),
    );
  }

  static const _magic = 'SHSN';
  static const _version = 1;
  static const payloadLength = 4 + 1 + 32 + 32;

  /// 12 groups of 5 digits, the same on both phones.
  final List<String> groups;
  final Uint8List _payload;

  /// What the QR code identifies (no account IDs, no keys: two hashes).
  Uint8List get qrPayload => Uint8List.fromList(_payload);

  static const _qrPrefix = 'SHSN1:';

  /// The text in the QR code: `SHSN1:` and the 64 fingerprint bytes in
  /// upper-case hex (QR alphanumeric mode, which every scanner reads).
  String get qrText => '$_qrPrefix${_hexUpper(_payload.sublist(5))}';

  /// The payload behind scanned QR [text], or null if it is not a Sirf Hum
  /// safety number. Strict: exact prefix, length and alphabet.
  static Uint8List? payloadFromQrText(String text) {
    if (!text.startsWith(_qrPrefix)) return null;
    final hex = text.substring(_qrPrefix.length);
    if (!RegExp(r'^[0-9A-F]{128}$').hasMatch(hex)) return null;
    return Uint8List.fromList([
      ...ascii.encode(_magic),
      _version,
      for (var i = 0; i < hex.length; i += 2)
        int.parse(hex.substring(i, i + 2), radix: 16),
    ]);
  }

  static String _hexUpper(List<int> bytes) => bytes
      .map((b) => b.toRadixString(16).padLeft(2, '0'))
      .join()
      .toUpperCase();

  /// Whether a scanned QR payload is this exact safety number. Compares
  /// every byte (no early exit).
  bool matchesScanned(Uint8List scanned) {
    if (scanned.length != _payload.length) return false;
    var diff = 0;
    for (var i = 0; i < scanned.length; i++) {
      diff |= scanned[i] ^ _payload[i];
    }
    return diff == 0;
  }

  @override
  bool operator ==(Object other) =>
      other is SafetyNumber && other.matchesScanned(_payload);

  @override
  int get hashCode => Object.hashAll(_payload);

  /// Never prints the number itself (it is shown on screen, not logged).
  @override
  String toString() => 'SafetyNumber(<redacted>)';

  static List<String> _digits(Uint8List fp) => [
    for (var i = 0; i < 6; i++)
      (fp.sublist(i * 5, i * 5 + 5).fold<int>(0, (acc, b) => acc * 256 + b) %
              100000)
          .toString()
          .padLeft(5, '0'),
  ];
}

/// SHA-256 fingerprint of one person's root key, bound to their account.
Uint8List personFingerprint(String account, PersonKey root) {
  final a = utf8.encode(account);
  final out = BytesBuilder(copy: false)
    ..add(ascii.encode('SirfHum-SafetyNumber-v1'))
    ..addByte(1)
    ..add(_u32(a.length))
    ..add(a)
    ..add(_u32(root.bytes.length))
    ..add(root.bytes);
  return Uint8List.fromList(sha256.convert(out.takeBytes()).bytes);
}

/// The person key inside a v1 device certificate (D-064), strictly decoded:
/// `version 1 | u32 len (32) | PIK | device id (16) | u32 len (32) | device
/// key | issued-at u64 | u32 len (64) | signature`. Call only on a
/// certificate the core has verified (e.g. a lineage root after
/// [CryptoCore.verifyLineage]).
PersonKey personKeyOfCertificate(Uint8List certificate) {
  final d = ByteData.sublistView(certificate);
  if (certificate.length != 1 + 4 + 32 + 16 + 4 + 32 + 8 + 4 + 64 ||
      certificate[0] != 1 ||
      d.getUint32(1) != 32 ||
      d.getUint32(1 + 4 + 32 + 16) != 32 ||
      d.getUint32(1 + 4 + 32 + 16 + 4 + 32 + 8) != 64) {
    throw const CryptoException(CryptoErrorCode.invalidInput);
  }
  return PersonKey(Uint8List.fromList(certificate.sublist(5, 37)));
}

/// The device ID inside a v1 device certificate (same strict layout as
/// [personKeyOfCertificate]).
DeviceId deviceIdOfCertificate(Uint8List certificate) {
  personKeyOfCertificate(certificate); // validates the layout
  return DeviceId(Uint8List.fromList(certificate.sublist(37, 53)));
}

Uint8List _u32(int v) => Uint8List(4)..buffer.asByteData().setUint32(0, v);
