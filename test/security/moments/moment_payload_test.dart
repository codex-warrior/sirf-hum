import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sirf_hum/security/messaging/text_payload.dart';
import 'package:sirf_hum/security/moments/moment_payload.dart';
import 'package:sirf_hum_crypto/sirf_hum_crypto.dart';

Matcher fails(MomentPayloadFailure f) => throwsA(
  isA<MomentPayloadException>().having((e) => e.failure, 'failure', f),
);

String id(int n) => n.toRadixString(16).padLeft(32, '0');

void main() {
  final photos = [id(1), id(2)];

  MomentPayload payload({
    List<String>? ids,
    String? caption = 'Our first trip',
    MomentDate? date,
  }) => MomentPayload(
    photoMessageIds: ids ?? photos,
    clientTimeMs: 1760000000000,
    caption: caption,
    memoryDate: date,
  );

  group('format v1', () {
    test('golden vector: layout is fixed (D-114)', () {
      final bytes = MomentPayload(
        photoMessageIds: [id(0xab)],
        clientTimeMs: 0x0102030405060708,
        caption: 'hi',
        memoryDate: MomentDate(2026, 2, 14),
      ).encode();
      expect(bytes, [
        1, 3, // version, kind
        1, 2, 3, 4, 5, 6, 7, 8, // client time
        0, 1, // schema
        0x07, 0xea, 2, 14, // 2026-02-14
        1, // one photo
        ...List.filled(15, 0), 0xab, // photo message id
        0, 2, 0x68, 0x69, // caption "hi"
      ]);
    });

    test('round trip with caption, date and the maximum photos', () {
      final ids = [for (var i = 1; i <= MomentPayload.maxPhotos; i++) id(i)];
      final p = payload(ids: ids, date: MomentDate(2024, 2, 29));
      final back = MomentPayload.decode(p.encode());
      expect(back.photoMessageIds, ids);
      expect(back.caption, 'Our first trip');
      expect(back.memoryDate, MomentDate(2024, 2, 29));
      expect(back.clientTimeMs, 1760000000000);
    });

    test('caption and date are optional; blank captions are none', () {
      for (final caption in [null, '', '   \n ']) {
        final back = MomentPayload.decode(payload(caption: caption).encode());
        expect(back.caption, isNull);
        expect(back.memoryDate, isNull);
      }
      expect(payload(caption: '  hello  ').caption, 'hello');
    });

    test('unicode captions round-trip; the limit is in UTF-8 bytes', () {
      const hindi = 'हमारी पहली यात्रा 🌊';
      expect(
        MomentPayload.decode(payload(caption: hindi).encode()).caption,
        hindi,
      );
      final atLimit = 'a' * MomentPayload.maxCaptionBytes;
      expect(payload(caption: atLimit).caption, atLimit);
      expect(
        () => payload(caption: '${'a' * MomentPayload.maxCaptionBytes}b'),
        fails(MomentPayloadFailure.captionTooLong),
      );
      // 4-byte characters: 501 of them are over 2,000 bytes.
      expect(
        () => payload(caption: '🌊' * 501),
        fails(MomentPayloadFailure.captionTooLong),
      );
    });

    test('photos: 1..8, distinct, message IDs only', () {
      expect(() => payload(ids: []), fails(MomentPayloadFailure.noPhotos));
      expect(
        () => payload(ids: [for (var i = 0; i < 9; i++) id(i)]),
        fails(MomentPayloadFailure.tooManyPhotos),
      );
      expect(
        () => payload(ids: [id(1), id(1)]),
        fails(MomentPayloadFailure.duplicatePhoto),
      );
      for (final bad in ['xyz', id(0xab).toUpperCase(), '${id(1)}0', '']) {
        expect(
          () => payload(ids: [bad]),
          fails(MomentPayloadFailure.malformed),
        );
      }
    });

    test('it carries no key, hash, size, file name or location', () {
      final bytes = payload(caption: null).encode();
      // Header + two 16-byte message IDs + an empty caption length.
      expect(bytes.length, 17 + 32 + 2);
    });
  });

  group('strict decode fails closed', () {
    late Uint8List good;
    setUp(() => good = payload().encode());

    Uint8List edit(void Function(Uint8List b) change) {
      final b = Uint8List.fromList(good);
      change(b);
      return b;
    }

    test('unknown version, kind or schema is unsupported', () {
      expect(
        () => MomentPayload.decode(edit((b) => b[0] = 2)),
        fails(MomentPayloadFailure.unsupported),
      );
      expect(
        () => MomentPayload.decode(edit((b) => b[1] = 1)),
        fails(MomentPayloadFailure.unsupported),
      );
      expect(
        () => MomentPayload.decode(edit((b) => b[11] = 2)),
        fails(MomentPayloadFailure.unsupported),
      );
    });

    test('truncated, extended or miscounted input is malformed', () {
      expect(
        () => MomentPayload.decode(good.sublist(0, good.length - 1)),
        fails(MomentPayloadFailure.malformed),
      );
      expect(
        () => MomentPayload.decode(Uint8List.fromList([...good, 0])),
        fails(MomentPayloadFailure.malformed),
      );
      expect(
        () => MomentPayload.decode(good.sublist(0, 10)),
        fails(MomentPayloadFailure.malformed),
      );
      for (final count in [0, 3, 9, 255]) {
        expect(
          () => MomentPayload.decode(edit((b) => b[16] = count)),
          fails(MomentPayloadFailure.malformed),
          reason: 'count $count',
        );
      }
    });

    test('a duplicated photo reference is refused', () {
      final b = edit((b) => b.setRange(33, 49, b.sublist(17, 33)));
      expect(
        () => MomentPayload.decode(b),
        fails(MomentPayloadFailure.duplicatePhoto),
      );
    });

    test('impossible or partial dates are refused', () {
      for (final (y, m, d) in [
        (2026, 2, 30),
        (2026, 13, 1),
        (2026, 0, 1),
        (1899, 1, 1),
        (0, 1, 0),
      ]) {
        final b = edit((b) {
          ByteData.sublistView(b).setUint16(12, y, Endian.big);
          b[14] = m;
          b[15] = d;
        });
        expect(
          () => MomentPayload.decode(b),
          fails(MomentPayloadFailure.invalidDate),
          reason: '$y-$m-$d',
        );
      }
    });

    test('invalid UTF-8 and unnormalized captions are malformed', () {
      final p = payload(caption: 'ab').encode();
      final invalid = Uint8List.fromList(p)..[p.length - 1] = 0xff;
      expect(
        () => MomentPayload.decode(invalid),
        fails(MomentPayloadFailure.malformed),
      );
      final spaced = Uint8List.fromList(p)..[p.length - 2] = 0x20;
      expect(
        () => MomentPayload.decode(spaced),
        fails(MomentPayloadFailure.malformed),
      );
    });

    test('over-long captions are refused before decoding them', () {
      final head = payload(caption: null).encode();
      final text = utf8.encode('a' * (MomentPayload.maxCaptionBytes + 1));
      final b = Uint8List.fromList([
        ...head.sublist(0, head.length - 2),
        (text.length >> 8) & 0xff,
        text.length & 0xff,
        ...text,
      ]);
      expect(
        () => MomentPayload.decode(b),
        fails(MomentPayloadFailure.malformed),
      );
    });
  });

  test('payload kinds never collide', () {
    final moment = payload().encode();
    final text = TextPayload(text: 'hi', clientTimeMs: 1).encode();
    expect(MomentPayload.isMoment(moment), isTrue);
    expect(MomentPayload.isMoment(text), isFalse);
    expect(MediaRefView.isMedia(moment), isFalse);
    expect(
      () => TextPayload.decode(moment),
      throwsA(
        isA<TextPayloadException>().having(
          (e) => e.failure,
          'failure',
          TextPayloadFailure.unsupported,
        ),
      ),
    );
  });

  test('nothing private in toString', () {
    final p = payload(caption: 'secret caption', date: MomentDate(2020, 1, 2));
    for (final s in ['$p', '${p.memoryDate}']) {
      expect(s, isNot(contains('secret')));
      expect(s, isNot(contains('2020')));
      expect(s, isNot(contains(id(1))));
    }
  });

  group('MomentDate', () {
    test('real calendar days only, 1900–2199', () {
      expect(MomentDate(2024, 2, 29).toLocal(), DateTime(2024, 2, 29));
      for (final (y, m, d) in [
        (2023, 2, 29),
        (2026, 4, 31),
        (1899, 12, 31),
        (2200, 1, 1),
        (2026, 1, 0),
      ]) {
        expect(
          () => MomentDate(y, m, d),
          fails(MomentPayloadFailure.invalidDate),
        );
      }
    });

    test('orders by day', () {
      expect(
        MomentDate(2026, 1, 2).compareTo(MomentDate(2025, 12, 31)),
        isPositive,
      );
      expect(
        MomentDate.of(DateTime(2026, 5, 6, 23, 59)),
        MomentDate(2026, 5, 6),
      );
    });
  });
}
