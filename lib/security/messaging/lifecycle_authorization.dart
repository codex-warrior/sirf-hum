import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// The 32 bytes a device signs (device-proof purpose `conversationRecovery`
/// = 7) to retire a stalled conversation and re-provision a new MLS group
/// (Prompt 17C, D-135). Mirrors `recoveryAuthorizationChallenge` in
/// functions/src/conversation/recovery.ts; golden vector:
/// functions/test/vectors/lifecycle_authorization_v1.json.
///
/// ```text
/// SHA-256( "SirfHum-ConversationRecovery-v1" | u8 1 | nonce[32]
///        | u32 len | account (UTF-8) | device id[16] | conversation id[16]
///        | stalled epoch u64 BE | account trust epoch u64 BE )
/// ```
///
/// Binding the epoch and the trust epoch means a recovery signed against
/// one state can never be applied to a later one. Hashing only: the
/// signature is made inside the Rust core (D-070).
Uint8List recoveryAuthorizationChallenge({
  required Uint8List nonce,
  required String accountId,
  required Uint8List deviceId,
  required Uint8List conversationId,
  required int epoch,
  required int trustEpoch,
}) {
  if (nonce.length != 32 ||
      deviceId.length != 16 ||
      conversationId.length != 16 ||
      epoch < 0 ||
      trustEpoch < 0) {
    throw ArgumentError('malformed recovery authorization');
  }
  final account = utf8.encode(accountId);
  final out = BytesBuilder(copy: false)
    ..add(ascii.encode('SirfHum-ConversationRecovery-v1'))
    ..addByte(1)
    ..add(nonce)
    ..add(_u32(account.length))
    ..add(account)
    ..add(deviceId)
    ..add(conversationId)
    ..add(_u64(epoch))
    ..add(_u64(trustEpoch));
  return Uint8List.fromList(sha256.convert(out.takeBytes()).bytes);
}

/// The 32 bytes a device signs (device-proof purpose `unpair` = 8) to end
/// the couple (Prompt 17C, D-136). Mirrors `unpairAuthorizationChallenge`
/// in functions/src/couple/unpair.ts; same golden vector file.
///
/// ```text
/// SHA-256( "SirfHum-Unpair-v1" | u8 1 | nonce[32] | u32 len | account
///        | device id[16] | couple id[16] )
/// ```
Uint8List unpairAuthorizationChallenge({
  required Uint8List nonce,
  required String accountId,
  required Uint8List deviceId,
  required Uint8List coupleId,
}) {
  if (nonce.length != 32 || deviceId.length != 16 || coupleId.length != 16) {
    throw ArgumentError('malformed unpair authorization');
  }
  final account = utf8.encode(accountId);
  final out = BytesBuilder(copy: false)
    ..add(ascii.encode('SirfHum-Unpair-v1'))
    ..addByte(1)
    ..add(nonce)
    ..add(_u32(account.length))
    ..add(account)
    ..add(deviceId)
    ..add(coupleId);
  return Uint8List.fromList(sha256.convert(out.takeBytes()).bytes);
}

Uint8List _u32(int v) => Uint8List(4)..buffer.asByteData().setUint32(0, v);

/// Big-endian u64 from two u32 halves (`setUint64` is unavailable on web;
/// epochs stay far below 2^53).
Uint8List _u64(int v) => Uint8List(8)
  ..buffer.asByteData().setUint32(0, v ~/ 0x100000000)
  ..buffer.asByteData().setUint32(4, v % 0x100000000);
