import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// One Welcome as it is bound into a commit authorization.
class AuthorizedWelcome {
  const AuthorizedWelcome({
    required this.targetDeviceId,
    required this.welcome,
  });

  /// 16 bytes.
  final Uint8List targetDeviceId;
  final Uint8List welcome;
}

/// The 32 bytes a device signs (device-proof purpose `commit` = 5) to
/// authorize one MLS commit (Prompt 17B, D-127). Mirrors
/// `commitAuthorizationChallenge` in functions/src/conversation/commit.ts;
/// golden vector: functions/test/vectors/commit_authorization_v1.json.
///
/// ```text
/// SHA-256( "SirfHum-CommitAuthorization-v1" | u8 1 | nonce[32]
///        | u32 len | account (UTF-8) | device id[16] | conversation id[16]
///        | fromEpoch u64 BE | toEpoch u64 BE | protocol u16 BE
///        | SHA-256(commit)
///        | SHA-256( u32 n | n × (target id[16] | SHA-256(welcome)) ) )
/// ```
///
/// The nonce is a single-use server challenge, so the signature is good for
/// exactly this commit, by this device, at this epoch. Hashing only: the
/// signature itself is made inside the Rust core (D-070).
Uint8List commitAuthorizationChallenge({
  required Uint8List nonce,
  required String accountId,
  required Uint8List deviceId,
  required Uint8List conversationId,
  required int fromEpoch,
  required int protocolVersion,
  required Uint8List commit,
  required List<AuthorizedWelcome> welcomes,
}) {
  if (nonce.length != 32 ||
      deviceId.length != 16 ||
      conversationId.length != 16 ||
      fromEpoch < 0 ||
      protocolVersion < 0 ||
      protocolVersion > 0xffff) {
    throw ArgumentError('malformed commit authorization');
  }
  final welcomeList = BytesBuilder(copy: false)..add(_u32(welcomes.length));
  for (final w in welcomes) {
    if (w.targetDeviceId.length != 16) {
      throw ArgumentError('malformed commit authorization');
    }
    welcomeList
      ..add(w.targetDeviceId)
      ..add(sha256.convert(w.welcome).bytes);
  }
  final account = utf8.encode(accountId);
  final out = BytesBuilder(copy: false)
    ..add(ascii.encode('SirfHum-CommitAuthorization-v1'))
    ..addByte(1)
    ..add(nonce)
    ..add(_u32(account.length))
    ..add(account)
    ..add(deviceId)
    ..add(conversationId)
    ..add(_u64(fromEpoch))
    ..add(_u64(fromEpoch + 1))
    ..add(Uint8List(2)..buffer.asByteData().setUint16(0, protocolVersion))
    ..add(sha256.convert(commit).bytes)
    ..add(sha256.convert(welcomeList.takeBytes()).bytes);
  return Uint8List.fromList(sha256.convert(out.takeBytes()).bytes);
}

Uint8List _u32(int v) => Uint8List(4)..buffer.asByteData().setUint32(0, v);

/// Big-endian u64 from two u32 halves (`setUint64` is unavailable on web;
/// epochs stay far below 2^53).
Uint8List _u64(int v) => Uint8List(8)
  ..buffer.asByteData().setUint32(0, v ~/ 0x100000000)
  ..buffer.asByteData().setUint32(4, v % 0x100000000);
