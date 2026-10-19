// ABI v5 types without the native library (runs everywhere, Web stub too).
import 'dart:typed_data';

import 'package:sirf_hum_crypto/sirf_hum_crypto.dart';
import 'package:sirf_hum_crypto/src/core_unsupported.dart' as web;
import 'package:test/test.dart';

Matcher _fails(CryptoErrorCode code) =>
    throwsA(isA<CryptoException>().having((e) => e.code, 'code', code));

Uint8List _hex(String s) => Uint8List.fromList([
  for (var i = 0; i < s.length; i += 2)
    int.parse(s.substring(i, i + 2), radix: 16),
]);

/// Shared with native/src/engine/conversation.rs (`golden::HISTORY_RECORD_HEX`).
const _recordHex =
    '01'
    '11111111111111111111111111111111'
    '22222222222222222222222222222222'
    '33333333333333333333333333333333'
    '01'
    '01'
    '0000000000000005'
    '00000000000003e8'
    '0000000000000000'
    '00000002'
    '6869'
    '01'
    '00000002'
    'aabb';

Uint8List _history(List<String> recordsHex) {
  final records = [for (final r in recordsHex) _hex(r)];
  return encodeByteList(records);
}

void main() {
  final conversation = ConversationId(
    Uint8List.fromList(List.filled(16, 0x11)),
  );

  test('the new error codes match native/src/error.rs', () {
    expect(CryptoErrorCode.commitPending.code, -22);
    expect(CryptoErrorCode.noStagedCommit.code, -23);
    expect(CryptoErrorCode.futureEpoch.code, -24);
    expect(CryptoErrorCode.envelopeMismatch.code, -25);
    expect(CryptoErrorCode.fromCode(-26), CryptoErrorCode.internal);
  });

  test('history decodes the shared golden vector exactly', () {
    final list = decodeHistory(_history([_recordHex]), conversation);
    expect(list, hasLength(1));
    final m = list.single;
    expect(m.messageId, MessageId(Uint8List.fromList(List.filled(16, 0x22))));
    expect(
      m.senderDeviceId,
      DeviceId(Uint8List.fromList(List.filled(16, 0x33))),
    );
    expect(m.direction, MessageDirection.outgoing);
    expect(m.state, MessageState.queued);
    expect(m.epoch, 5);
    expect(m.createdAtMs, 1000);
    expect(m.serverTimeMs, 0);
    expect(m.payload, [0x68, 0x69]);
    expect(m.ciphertext, [0xaa, 0xbb]);
    expect(m.toString(), isNot(contains('hi')));
  });

  test('malformed history fails closed, never partially', () {
    final good = _history([_recordHex]);
    final cases = <String, Uint8List>{
      'truncated': Uint8List.sublistView(good, 0, good.length - 1),
      'trailing': Uint8List.fromList([...good, 0]),
      'unknown record version': _history(['02${_recordHex.substring(2)}']),
      'unknown direction': _history([_recordHex.replaceRange(98, 100, '09')]),
      'queued without ciphertext': _history([
        '${_recordHex.substring(0, _recordHex.length - 14)}00',
      ]),
      'count larger than content': Uint8List.fromList([
        0,
        0,
        0,
        2,
        ...good.sublist(4),
      ]),
    };
    for (final MapEntry(:key, :value) in cases.entries) {
      expect(
        () => decodeHistory(value, conversation),
        _fails(CryptoErrorCode.internal),
        reason: key,
      );
    }
    expect(
      () => decodeHistory(
        good,
        ConversationId(Uint8List.fromList(List.filled(16, 0x12))),
      ),
      _fails(CryptoErrorCode.internal),
      reason: 'a record of another conversation',
    );
    expect(decodeHistory(_history([]), conversation), isEmpty);
  });

  test('identifiers validate length and never print', () {
    expect(
      () => ConversationId(Uint8List(15)),
      _fails(CryptoErrorCode.invalidInput),
    );
    expect(
      () => MessageId(Uint8List(17)),
      _fails(CryptoErrorCode.invalidInput),
    );
    final values = <Object>[
      conversation,
      MessageId(Uint8List(16)),
      StagedCommit(fromEpoch: 3, commit: Uint8List(4), welcome: Uint8List(4)),
      SentMessage(
        messageId: MessageId(Uint8List(16)),
        epoch: 1,
        ciphertext: Uint8List(4),
      ),
      ReceivedMessage(
        payload: Uint8List.fromList([104, 105]),
        duplicate: false,
      ),
    ];
    for (final v in values) {
      expect(v.toString(), contains('<redacted>'));
    }
    expect(
      StagedCommit(
        fromEpoch: 0,
        commit: Uint8List(1),
        welcome: Uint8List(0),
      ).welcome,
      isNull,
    );
  });

  test('the list encoding matches the native decode_list', () {
    expect(
      encodeByteList([
        Uint8List.fromList([1, 2]),
        Uint8List(0),
      ]),
      [0, 0, 0, 2, 0, 0, 0, 2, 1, 2, 0, 0, 0, 0],
    );
    expect(MessageVersions.schema, 1);
    expect(MessageVersions.protocol, 1);
  });

  test('Web has no private messaging: every v5 call fails closed', () {
    // The Web stub exposes the same API, but no instance can exist
    // (initialize throws), so every messaging entry point is unreachable.
    expect(
      () => web.CryptoCore.initialize(
        directory: '/x',
        keyStore: KeyStoreKind.insecureTestEphemeral,
      ),
      _fails(CryptoErrorCode.unsupported),
    );
    expect(web.expectedAbiVersion, 6);
  });
}
