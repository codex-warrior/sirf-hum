// ABI v6 media types without the native library (runs everywhere, Web stub
// too). Prompt 11, docs/security/E2EE-MEDIA-AND-NOTIFICATIONS.md.
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

/// Shared with native/src/engine/media.rs (`tests::MEDIA_VIEW_HEX`).
const _viewHex =
    '01'
    '02'
    '00000000000003e8'
    '44444444444444444444444444444444'
    '02'
    '0000000000011170'
    '00000000000111a9';

void main() {
  test('the key-free view decodes the shared golden vector exactly', () {
    final view = MediaRefView.decode(_hex(_viewHex));
    expect(view.clientTimeMs, 1000);
    expect(view.mediaId, MediaId(Uint8List.fromList(List.filled(16, 0x44))));
    expect(view.mediaClass, MediaClass.video);
    expect(view.plaintextLength, 70000);
    expect(view.objectLength, 70057);
    expect(view.toString(), 'MediaRefView(video, <redacted>)');
    expect(MediaRefView.isMedia(_hex(_viewHex)), isTrue);
  });

  test('the view decodes strictly (never a guess)', () {
    final good = _hex(_viewHex);
    Uint8List mutate(int at, int value) =>
        Uint8List.fromList(good)..[at] = value;
    final bad = _fails(CryptoErrorCode.internal);
    expect(() => MediaRefView.decode(mutate(0, 2)), bad, reason: 'version');
    expect(() => MediaRefView.decode(mutate(1, 1)), bad, reason: 'kind');
    expect(() => MediaRefView.decode(mutate(26, 0)), bad, reason: 'class');
    expect(() => MediaRefView.decode(mutate(26, 5)), bad, reason: 'class');
    expect(() => MediaRefView.decode(mutate(42, 0)), bad, reason: 'length');
    expect(() => MediaRefView.decode(good.sublist(0, 42)), bad);
    expect(
      () => MediaRefView.decode(Uint8List.fromList([...good, 0])),
      bad,
      reason: 'a full reference (with key) is never accepted as a view',
    );
    final empty = Uint8List.fromList(good)
      ..setRange(27, 43, Uint8List(16)..[15] = 25);
    expect(() => MediaRefView.decode(empty), bad, reason: 'empty media');
    // Text payloads are not media.
    expect(MediaRefView.isMedia(Uint8List.fromList([1, 1, 0])), isFalse);
    expect(MediaRefView.isMedia(Uint8List.fromList([1])), isFalse);
  });

  test('object file names match native media_object_file_name', () {
    expect(
      mediaObjectFileName(
        ConversationId(Uint8List.fromList(List.filled(16, 0x11))),
        MediaId(Uint8List.fromList(List.filled(16, 0x44))),
      ),
      '11111111111111111111111111111111_44444444444444444444444444444444.shm',
    );
  });

  test('object sizes and limits match native/src/limits.rs', () {
    expect(MediaLimits.objectLength(1), 25 + 1 + 16);
    expect(MediaLimits.objectLength(65536), 25 + 65536 + 16);
    expect(MediaLimits.objectLength(65537), 25 + 65537 + 32);
    expect(MediaLimits.maxPlaintextBytes, 64 * 1024 * 1024);
    expect(
      MediaLimits.objectLength(MediaLimits.maxPlaintextBytes),
      MediaLimits.maxObjectBytes,
    );
    expect(MediaLimits.maxObjectBytes, 67125273, reason: 'Storage rule');
  });

  test('wire values match the native ABI', () {
    expect([for (final c in MediaClass.values) c.wireValue], [1, 2, 3, 4]);
    expect(DeviceProofPurpose.pushToken.wireValue, 3);
    expect(expectedAbiVersion, 6);
  });

  test('media types never print their bytes', () {
    final id = MediaId(Uint8List.fromList(List.filled(16, 0xab)));
    expect(id.toString(), 'MediaId(<redacted>)');
    final sent = SentMedia(
      message: SentMessage(
        messageId: MessageId(Uint8List(16)),
        epoch: 3,
        ciphertext: Uint8List.fromList([1, 2, 3]),
      ),
      mediaId: id,
      objectLength: 42,
    );
    expect(sent.toString(), 'SentMedia(epoch: 3, <redacted>)');
  });

  test('Web has no private media: the stub cannot even be opened', () {
    expect(
      () => web.CryptoCore.initialize(
        directory: '/x',
        keyStore: KeyStoreKind.insecureTestEphemeral,
      ),
      _fails(CryptoErrorCode.unsupported),
    );
    expect(web.CryptoCore.isAvailable, isFalse);
  });
}
