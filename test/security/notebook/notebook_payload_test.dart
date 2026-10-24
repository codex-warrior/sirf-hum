// The kind-4 notebook payload (D-119): exact bytes, strict decode, and the
// per-section field rules. Pure: runs without the native core.
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sirf_hum/security/messaging/text_payload.dart';
import 'package:sirf_hum/security/moments/moment_payload.dart';
import 'package:sirf_hum/security/notebook/notebook_payload.dart';

Matcher fails(NotebookPayloadFailure f) => throwsA(
  isA<NotebookPayloadException>().having((e) => e.failure, 'failure', f),
);

const _target = '00112233445566778899aabbccddeeff';

NotebookFields _future({
  FutureCategory category = FutureCategory.plan,
  FutureStatus status = FutureStatus.planned,
  String title = 'Go to Udaipur',
  String? note,
  MomentDate? date,
}) => NotebookFields(
  section: NotebookSection.future,
  category: category.wireValue,
  status: status.wireValue,
  title: title,
  note: note,
  date: date,
);

void main() {
  group('golden vector', () {
    test('a Future create encodes to exactly these bytes', () {
      final bytes = NotebookPayload.create(
        fields: _future(note: 'Lake', date: MomentDate(2026, 10, 28)),
        clientTimeMs: 0x0102030405060708,
      ).encode();
      final expected = <int>[
        1, 4, // version, kind
        1, 2, 3, 4, 5, 6, 7, 8, // client time
        0, 1, // schema
        1, // op create
        ...List.filled(16, 0), // no target
        1, 1, 1, // section future, category plan, status planned
        0x07, 0xea, 10, 28, // 2026-10-28
        0, 13, ...utf8.encode('Go to Udaipur'),
        0, 4, ...utf8.encode('Lake'),
        0, // no detail
      ];
      expect(bytes, expected);
      final back = NotebookPayload.decode(bytes);
      expect(back.op, NotebookOp.create);
      expect(back.target, isNull);
      expect(back.fields!.title, 'Go to Udaipur');
      expect(back.fields!.note, 'Lake');
      expect(back.fields!.date, MomentDate(2026, 10, 28));
      expect(back.clientTimeMs, 0x0102030405060708);
    });

    test('update and remove carry their target; remove carries nothing '
        'else', () {
      final update = NotebookPayload.decode(
        NotebookPayload.update(
          target: _target,
          fields: _future(status: FutureStatus.done),
          clientTimeMs: 5,
        ).encode(),
      );
      expect(update.op, NotebookOp.update);
      expect(update.target, _target);
      expect(update.fields!.status, FutureStatus.done.wireValue);

      final removeBytes = NotebookPayload.remove(
        target: _target,
        section: NotebookSection.ritual,
        clientTimeMs: 5,
      ).encode();
      expect(removeBytes, hasLength(36 + 5));
      final remove = NotebookPayload.decode(removeBytes);
      expect(remove.op, NotebookOp.remove);
      expect(remove.section, NotebookSection.ritual);
      expect(remove.fields, isNull);
    });

    test('every section round-trips', () {
      final all = [
        _future(category: FutureCategory.importantDate),
        NotebookFields(
          section: NotebookSection.story,
          title: 'How we started',
          note: 'A rainy Tuesday.\nThen chai.',
          date: MomentDate(2021, 3, 12),
        ),
        NotebookFields(
          section: NotebookSection.littleThing,
          category: LittleThingKind.ourSong.wireValue,
          title: 'Tum Hi Ho',
        ),
        NotebookFields(
          section: NotebookSection.ritual,
          title: 'Friday movie',
          note: 'Popcorn, no phones',
          detail: 'Every Friday',
        ),
        NotebookFields(
          section: NotebookSection.togetherSince,
          date: MomentDate(2021, 3, 12),
        ),
      ];
      for (final f in all) {
        final back = NotebookPayload.decode(
          NotebookPayload.create(fields: f, clientTimeMs: 1).encode(),
        ).fields!;
        expect(back.section, f.section);
        expect(back.category, f.category);
        expect(back.status, f.status);
        expect(back.title, f.title);
        expect(back.note, f.note);
        expect(back.detail, f.detail);
        expect(back.date, f.date);
      }
    });

    test('isNotebook tells kind 4 from texts and moments', () {
      expect(
        NotebookPayload.isNotebook(
          NotebookPayload.create(fields: _future(), clientTimeMs: 1).encode(),
        ),
        isTrue,
      );
      expect(
        NotebookPayload.isNotebook(
          TextPayload(text: 'hi', clientTimeMs: 1).encode(),
        ),
        isFalse,
      );
      expect(
        NotebookPayload.isNotebook(
          MomentPayload(photoMessageIds: [_target], clientTimeMs: 1).encode(),
        ),
        isFalse,
      );
    });
  });

  group('field rules', () {
    test('titles are required, trimmed, one line and bounded', () {
      expect(
        () => _future(title: '   '),
        fails(NotebookPayloadFailure.missingTitle),
      );
      expect(_future(title: '  Goa  ').title, 'Goa');
      expect(
        () => _future(title: 'Goa\nManali'),
        fails(NotebookPayloadFailure.invalidText),
      );
      expect(
        () => _future(title: 'x' * (NotebookFields.maxTitleBytes + 1)),
        fails(NotebookPayloadFailure.titleTooLong),
      );
      // Bytes, not characters: 101 four-byte emoji are over 400 bytes.
      expect(
        () => _future(title: '😀' * 101),
        fails(NotebookPayloadFailure.titleTooLong),
      );
      expect(
        () => _future(note: 'x' * (NotebookFields.maxNoteBytes + 1)),
        fails(NotebookPayloadFailure.noteTooLong),
      );
      expect(
        () => _future(note: 'a\u0000b'),
        fails(NotebookPayloadFailure.invalidText),
      );
      expect(_future(note: 'line one\nline two').note, contains('\n'));
    });

    test('categories and statuses belong to their section', () {
      expect(
        () => NotebookFields(
          section: NotebookSection.future,
          category: 9,
          status: 1,
          title: 'x',
        ),
        fails(NotebookPayloadFailure.invalidCategory),
      );
      expect(
        () => NotebookFields(
          section: NotebookSection.future,
          category: 1,
          title: 'x',
        ),
        fails(NotebookPayloadFailure.invalidStatus),
      );
      expect(
        () => NotebookFields(
          section: NotebookSection.story,
          category: 1,
          title: 'x',
        ),
        fails(NotebookPayloadFailure.invalidCategory),
      );
      expect(
        () => NotebookFields(
          section: NotebookSection.ritual,
          status: 1,
          title: 'x',
        ),
        fails(NotebookPayloadFailure.invalidStatus),
      );
      expect(
        () => NotebookFields(section: NotebookSection.littleThing, title: 'x'),
        fails(NotebookPayloadFailure.invalidCategory),
      );
    });

    test('dates only where they mean something', () {
      expect(
        () => NotebookFields(section: NotebookSection.togetherSince),
        fails(NotebookPayloadFailure.invalidDate),
      );
      expect(
        () => NotebookFields(
          section: NotebookSection.ritual,
          title: 'x',
          date: MomentDate(2026, 1, 1),
        ),
        fails(NotebookPayloadFailure.invalidDate),
      );
      expect(
        () => NotebookFields(
          section: NotebookSection.togetherSince,
          title: 'x',
          date: MomentDate(2026, 1, 1),
        ),
        fails(NotebookPayloadFailure.malformed),
      );
      expect(
        () => NotebookFields(
          section: NotebookSection.story,
          title: 'x',
          detail: 'weekly',
        ),
        fails(NotebookPayloadFailure.malformed),
      );
    });
  });

  group('strict decode', () {
    Uint8List valid() => NotebookPayload.create(
      fields: _future(note: 'n', date: MomentDate(2026, 10, 28)),
      clientTimeMs: 1,
    ).encode();

    test('any length change is malformed', () {
      final b = valid();
      expect(
        () => NotebookPayload.decode(Uint8List.fromList([...b, 0])),
        fails(NotebookPayloadFailure.malformed),
      );
      expect(
        () => NotebookPayload.decode(b.sublist(0, b.length - 1)),
        fails(NotebookPayloadFailure.malformed),
      );
      expect(
        () => NotebookPayload.decode(Uint8List(10)),
        fails(NotebookPayloadFailure.malformed),
      );
    });

    test('unknown version, kind, schema, op or section is unsupported', () {
      for (final (at, value) in [(0, 2), (1, 3), (11, 3), (12, 9), (29, 9)]) {
        final b = valid()..[at] = value;
        expect(
          () => NotebookPayload.decode(b),
          fails(NotebookPayloadFailure.unsupported),
          reason: 'byte $at',
        );
      }
    });

    test('a create with a target, or an update without one, is malformed', () {
      final withTarget = valid()..[13] = 1;
      expect(
        () => NotebookPayload.decode(withTarget),
        fails(NotebookPayloadFailure.malformed),
      );
      final update = NotebookPayload.update(
        target: _target,
        fields: _future(),
        clientTimeMs: 1,
      ).encode()..fillRange(13, 29, 0);
      expect(
        () => NotebookPayload.decode(update),
        fails(NotebookPayloadFailure.malformed),
      );
    });

    test('impossible dates, bad UTF-8 and untrimmed text fail closed', () {
      final feb30 = valid()
        ..[34] = 2
        ..[35] = 30;
      expect(
        () => NotebookPayload.decode(feb30),
        fails(NotebookPayloadFailure.invalidDate),
      );
      final badUtf8 = valid()..[38] = 0xff;
      expect(
        () => NotebookPayload.decode(badUtf8),
        fails(NotebookPayloadFailure.malformed),
      );
      final spaced = valid()..[38] = 0x20; // leading space in the title
      expect(
        () => NotebookPayload.decode(spaced),
        fails(NotebookPayloadFailure.malformed),
      );
    });

    test('a remove that carries content is malformed', () {
      final remove = NotebookPayload.remove(
        target: _target,
        section: NotebookSection.future,
        clientTimeMs: 1,
      ).encode()..[30] = 1;
      expect(
        () => NotebookPayload.decode(remove),
        fails(NotebookPayloadFailure.malformed),
      );
    });

    test('targets must be real IDs', () {
      for (final bad in ['', 'XYZ', '0' * 32, _target.toUpperCase()]) {
        expect(
          () => NotebookPayload.update(
            target: bad,
            fields: _future(),
            clientTimeMs: 1,
          ),
          fails(NotebookPayloadFailure.malformed),
          reason: bad,
        );
      }
    });

    test('toString never shows content', () {
      final f = _future(title: 'SECRET-TITLE', note: 'SECRET-NOTE');
      expect('$f', isNot(contains('SECRET')));
      expect(
        '${NotebookPayload.create(fields: f, clientTimeMs: 1)}',
        isNot(contains('SECRET')),
      );
    });
  });

  group('dreams (D-157)', () {
    NotebookFields dream({int? progress = 42, bool done = false}) =>
        NotebookFields(
          section: NotebookSection.future,
          category: FutureCategory.dream.wireValue,
          status: (done ? FutureStatus.done : FutureStatus.planned).wireValue,
          title: 'A home together',
          progress: progress,
        );

    test('a dream is schema 2 with one trailing progress byte, and '
        'round-trips', () {
      final bytes = NotebookPayload.create(
        fields: dream(),
        clientTimeMs: 1,
      ).encode();
      expect(ByteData.sublistView(bytes).getUint16(10), 2);
      expect(bytes.last, 42);
      final back = NotebookPayload.decode(bytes).fields!;
      expect(back.progress, 42);
      expect(back.isDream, isTrue);
      expect(back.title, 'A home together');
    });

    test('everything else is still schema 1, byte for byte', () {
      final bytes = NotebookPayload.create(
        fields: _future(),
        clientTimeMs: 1,
      ).encode();
      expect(ByteData.sublistView(bytes).getUint16(10), 1);
      expect(NotebookPayload.decode(bytes).fields!.progress, isNull);
    });

    test('progress belongs to dreams only, from 0 to 100', () {
      for (final p in [0, 100]) {
        expect(dream(progress: p).progress, p);
      }
      for (final p in [null, -1, 101]) {
        expect(
          () => dream(progress: p),
          fails(NotebookPayloadFailure.invalidProgress),
          reason: '$p',
        );
      }
      expect(
        () => NotebookFields(
          section: NotebookSection.future,
          category: FutureCategory.plan.wireValue,
          status: FutureStatus.planned.wireValue,
          title: 'Udaipur',
          progress: 10,
        ),
        fails(NotebookPayloadFailure.invalidProgress),
      );
    });

    test('a progress byte on a plan, a missing one on a dream, or one out '
        'of range fails closed', () {
      final plan = NotebookPayload.create(
        fields: _future(),
        clientTimeMs: 1,
      ).encode();
      final planWithProgress = Uint8List.fromList([...plan, 10]);
      ByteData.sublistView(planWithProgress).setUint16(10, 2);
      expect(
        () => NotebookPayload.decode(planWithProgress),
        fails(NotebookPayloadFailure.invalidProgress),
      );

      final d = NotebookPayload.create(
        fields: dream(),
        clientTimeMs: 1,
      ).encode();
      final noByte = Uint8List.fromList(d.sublist(0, d.length - 1));
      ByteData.sublistView(noByte).setUint16(10, 1);
      expect(
        () => NotebookPayload.decode(noByte),
        fails(NotebookPayloadFailure.invalidProgress),
      );

      final tooMuch = Uint8List.fromList(d)..[d.length - 1] = 101;
      expect(
        () => NotebookPayload.decode(tooMuch),
        fails(NotebookPayloadFailure.invalidProgress),
      );
    });

    test('a remove is never schema 2', () {
      final remove = NotebookPayload.remove(
        target: _target,
        section: NotebookSection.future,
        clientTimeMs: 1,
      ).encode();
      final withByte = Uint8List.fromList([...remove, 0]);
      ByteData.sublistView(withByte).setUint16(10, 2);
      expect(
        () => NotebookPayload.decode(withByte),
        fails(NotebookPayloadFailure.malformed),
      );
    });
  });
}
