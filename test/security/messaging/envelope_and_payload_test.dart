// Text payload and message envelope: strict formats, limits, redaction.
// Pure Dart (no native core).
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sirf_hum/infrastructure/firebase/firestore_conversation_transport.dart';
import 'package:sirf_hum/security/messaging/conversation_transport.dart';
import 'package:sirf_hum/security/messaging/message_envelope.dart';
import 'package:sirf_hum/security/messaging/text_payload.dart';
import 'package:sirf_hum_crypto/sirf_hum_crypto.dart';

Matcher _payload(TextPayloadFailure f) =>
    throwsA(isA<TextPayloadException>().having((e) => e.failure, 'failure', f));

const _id = '0123456789abcdef0123456789abcdef';
const _device = 'a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1';

Map<String, Object?> _doc([Map<String, Object?> overrides = const {}]) => {
  'schemaVersion': 1,
  'protocolVersion': 1,
  'senderAccountId': 'accountA',
  'senderDeviceId': _device,
  'epoch': 3,
  'ciphertext': Uint8List(64),
  'serverTime': 1234,
  ...overrides,
};

EncryptedMessageEnvelope _parse(Map<String, Object?> data, [String id = _id]) =>
    EncryptedMessageEnvelope.fromFields(
      id,
      data,
      bytesOf: (v) => v is Uint8List ? v : throw const FormatException(),
      timeOf: (v) => v is int ? v : null,
    );

String get _rules => File('firebase/firestore.rules').readAsStringSync();

/// The exact field list a rule allows, read from firebase/firestore.rules.
Set<String> _ruleFields(String function) {
  final rules = _rules;
  final body = rules.substring(rules.indexOf('function $function('));
  final list = RegExp(r'hasOnly\(\[([^\]]*)\]\)').firstMatch(body)!.group(1)!;
  return {for (final m in RegExp(r"'(\w+)'").allMatches(list)) m.group(1)!};
}

void main() {
  group('TextPayload', () {
    test('round-trips text, including emoji and the exact limit', () {
      for (final text in [
        'hi',
        'I love you ❤️',
        'x' * TextPayload.maxTextBytes,
      ]) {
        final bytes = TextPayload(text: text, clientTimeMs: 42).encode();
        final back = TextPayload.decode(bytes);
        expect(back.text, text);
        expect(back.clientTimeMs, 42);
      }
      expect(TextPayload(text: 'hi', clientTimeMs: 7).encode(), [
        1,
        1,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        7,
        0,
        0,
        0,
        2,
        104,
        105,
      ]);
    });

    test('limits: empty, whitespace and oversized text are refused', () {
      expect(
        () => TextPayload(text: '', clientTimeMs: 0),
        _payload(TextPayloadFailure.empty),
      );
      expect(
        () => TextPayload(text: '  \n', clientTimeMs: 0),
        _payload(TextPayloadFailure.empty),
      );
      expect(
        () => TextPayload(
          text: 'x' * (TextPayload.maxTextBytes + 1),
          clientTimeMs: 0,
        ),
        _payload(TextPayloadFailure.tooLong),
      );
      // Multi-byte characters count in bytes, not characters.
      expect(
        () => TextPayload(text: '❤' * 5400, clientTimeMs: 0),
        _payload(TextPayloadFailure.tooLong),
      );
    });

    test('decoding fails closed on anything unexpected', () {
      final good = TextPayload(text: 'hi', clientTimeMs: 1).encode();
      expect(
        () => TextPayload.decode(Uint8List(3)),
        _payload(TextPayloadFailure.malformed),
      );
      expect(
        () => TextPayload.decode(Uint8List.fromList([2, ...good.sublist(1)])),
        _payload(TextPayloadFailure.unsupported),
      );
      expect(
        () =>
            TextPayload.decode(Uint8List.fromList([1, 9, ...good.sublist(2)])),
        _payload(TextPayloadFailure.unsupported),
        reason: 'media kinds come later',
      );
      expect(
        () => TextPayload.decode(Uint8List.fromList([...good, 0])),
        _payload(TextPayloadFailure.malformed),
      );
      final badUtf8 = Uint8List.fromList([...good.sublist(0, 14 - 1), 1, 0xff]);
      expect(
        () => TextPayload.decode(badUtf8),
        _payload(TextPayloadFailure.malformed),
      );
      expect(
        TextPayload(text: 'secret', clientTimeMs: 0).toString(),
        isNot(contains('secret')),
      );
    });
  });

  group('EncryptedMessageEnvelope', () {
    test('parses a stored document exactly', () {
      final e = _parse(_doc());
      expect(e.messageIdHex, _id);
      expect(e.senderDeviceIdHex, _device);
      expect(e.epoch, 3);
      expect(e.serverTimeMs, 1234);
      expect(e.opaque.protocolVersion, 1);
      expect(e.toString(), isNot(contains(_id)));
      expect(e.toString(), isNot(contains(_device)));
    });

    test('malformed remote documents never parse', () {
      final cases = <String, Map<String, Object?>>{
        'plaintext field': _doc({'text': 'I love you'}),
        'missing ciphertext': {..._doc()}..remove('ciphertext'),
        'string epoch': _doc({'epoch': '3'}),
        'epoch 0': _doc({'epoch': 0}),
        'bad device': _doc({'senderDeviceId': 'XYZ'}),
        'bad account': _doc({'senderAccountId': 'a/b'}),
        'huge ciphertext': _doc({'ciphertext': Uint8List(32 * 1024 + 1)}),
        'empty ciphertext': _doc({'ciphertext': Uint8List(0)}),
        'string ciphertext': _doc({'ciphertext': 'aGk='}),
        'version overflow': _doc({'protocolVersion': 70000}),
      };
      for (final MapEntry(:key, :value) in cases.entries) {
        expect(
          () => _parse(value),
          throwsA(isA<EnvelopeFormatException>()),
          reason: key,
        );
      }
      expect(
        () => _parse(_doc(), 'NOT-HEX'),
        throwsA(isA<EnvelopeFormatException>()),
      );
      // Unknown versions parse: the core rejects them (forged → mismatch,
      // genuine → unsupported), never this parser guessing.
      expect(_parse(_doc({'protocolVersion': 2})).protocolVersion, 2);
    });

    test('the written fields are exactly what the rules allow', () {
      final e = _parse(_doc());
      expect(
        FirestoreConversationTransport.messageFields(e).keys.toSet(),
        _ruleFields('validMessage'),
      );
      // Commits are no longer written by clients (D-127): the rules have
      // no client shape for them, and the callable request is exact.
      expect(_rules, isNot(contains('validCommit')));
      expect(_rules, isNot(contains('validWelcome')));
      final commit = CommitRecord(
        epoch: 1,
        senderAccountId: 'accountA',
        senderDeviceIdHex: _device,
        commit: Uint8List(4),
      );
      final request = FirestoreConversationTransport.commitRequest(
        ConversationId(Uint8List(16)),
        commit,
        [
          WelcomeRecord(
            epoch: 1,
            targetDeviceIdHex: _device,
            welcome: Uint8List(4),
          ),
        ],
        CommitAuthorization(challengeId: 'c', proof: Uint8List(64)),
      );
      expect(request.keys.toSet(), {
        'deviceId',
        'conversationId',
        'fromEpoch',
        'challengeId',
        'proof',
        'commit',
        'welcomes',
      });
      expect(
        ((request['welcomes']! as List).single as Map<String, Object>).keys
            .toSet(),
        {'targetDeviceId', 'welcome'},
      );
      // No field can carry readable content.
      final encoded = jsonEncode(e.toFields().map((k, v) => MapEntry(k, '$v')));
      expect(encoded, isNot(contains('love')));
    });
  });

  test('records never print their bytes', () {
    final values = <Object>[
      PublishedKeyPackage(
        accountId: 'accountA',
        deviceIdHex: _device,
        keyPackage: Uint8List(3),
      ),
      CommitRecord(
        epoch: 1,
        senderAccountId: 'accountA',
        senderDeviceIdHex: _device,
        commit: Uint8List(3),
      ),
      WelcomeRecord(
        epoch: 1,
        targetDeviceIdHex: _device,
        welcome: Uint8List(3),
      ),
    ];
    for (final v in values) {
      expect(v.toString(), contains('<redacted>'));
      expect(v.toString(), isNot(contains(_device)));
    }
    expect(ConversationId(Uint8List(16)).toString(), contains('<redacted>'));
  });
}
