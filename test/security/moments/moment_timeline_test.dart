// Timeline assembly (D-114): which manifests become moments, which fail
// closed, and in what order. Pure: runs without the native core.
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sirf_hum/security/messaging/text_payload.dart';
import 'package:sirf_hum/security/moments/moment.dart';
import 'package:sirf_hum/security/moments/moment_payload.dart';
import 'package:sirf_hum_crypto/sirf_hum_crypto.dart';

final _own = DeviceId(Uint8List.fromList(List.filled(16, 0xa1)));
final _partner = DeviceId(Uint8List.fromList(List.filled(16, 0xb1)));
final _ownOther = DeviceId(Uint8List.fromList(List.filled(16, 0xa2)));

String _id(int n) => n.toRadixString(16).padLeft(32, '0');

MessageId _mid(int n) => MessageId(
  Uint8List.fromList([
    for (var i = 0; i < 32; i += 2)
      int.parse(_id(n).substring(i, i + 2), radix: 16),
  ]),
);

/// The 43-byte key-free view the core returns for a media message.
Uint8List _mediaView({
  MediaClass mediaClass = MediaClass.image,
  int len = 1000,
}) {
  final b = ByteData(MediaRefView.length)
    ..setUint8(0, 1)
    ..setUint8(1, 2)
    ..setUint64(2, 1, Endian.big)
    ..setUint8(26, mediaClass.wireValue)
    ..setUint64(27, len, Endian.big)
    ..setUint64(35, MediaLimits.objectLength(len), Endian.big);
  return b.buffer.asUint8List();
}

LocalMessage _msg(
  int n,
  Uint8List payload, {
  DeviceId? sender,
  MessageState? state,
  int time = 1000,
}) {
  final from = sender ?? _own;
  final outgoing = from == _own;
  final s = state ?? (outgoing ? MessageState.sent : MessageState.received);
  return LocalMessage(
    messageId: _mid(n),
    senderDeviceId: from,
    direction: outgoing ? MessageDirection.outgoing : MessageDirection.incoming,
    state: s,
    epoch: 1,
    createdAtMs: time,
    serverTimeMs: s == MessageState.queued ? 0 : time,
    payload: payload,
    ciphertext: s == MessageState.queued ? Uint8List(1) : null,
  );
}

LocalMessage _photo(
  int n, {
  DeviceId? sender,
  MessageState? state,
  MediaClass mediaClass = MediaClass.image,
}) => _msg(
  n,
  _mediaView(mediaClass: mediaClass),
  sender: sender,
  state: state,
);

LocalMessage _manifest(
  int n,
  List<int> photos, {
  DeviceId? sender,
  MessageState? state,
  String? caption,
  MomentDate? date,
  int time = 1000,
}) => _msg(
  n,
  MomentPayload(
    photoMessageIds: [for (final p in photos) _id(p)],
    clientTimeMs: time,
    caption: caption,
    memoryDate: date,
  ).encode(),
  sender: sender,
  state: state,
  time: time,
);

List<MomentEntry> _assemble(List<LocalMessage> history) =>
    assembleMoments(history, isOwnAccount: (d) => d == _own || d == _ownOther);

void main() {
  test('a saved moment: its photos in order, caption and date', () {
    final entries = _assemble([
      _photo(2),
      _photo(1),
      _manifest(9, [1, 2], caption: 'Goa', date: MomentDate(2025, 12, 31)),
    ]);
    final m = entries.single as Moment;
    expect(m.photos, [MomentPhoto(_id(1)), MomentPhoto(_id(2))]);
    expect(m.photoCount, 2);
    expect(m.caption, 'Goa');
    expect(m.memoryDate, MomentDate(2025, 12, 31));
    expect(m.day, DateTime(2025, 12, 31));
    expect(m.status, MomentStatus.saved);
    expect(m.addedByYou, isTrue);
    expect(m.problem, MomentProblem.none);
    expect(m.handle, MomentHandle(_id(9)));
  });

  test('saving while any part is still queued', () {
    const q = MessageState.queued;
    expect(
      (_assemble([
                _photo(1, state: q),
                _manifest(9, [1], state: q),
              ]).single
              as Moment)
          .status,
      MomentStatus.saving,
    );
    expect(
      (_assemble([
                _photo(1, state: q),
                _manifest(9, [1]),
              ]).single
              as Moment)
          .status,
      MomentStatus.saving,
    );
  });

  test("the partner's moment is received; another own phone's is yours", () {
    final partner =
        _assemble([
              _photo(1, sender: _partner),
              _manifest(9, [1], sender: _partner),
            ]).single
            as Moment;
    expect(partner.status, MomentStatus.received);
    expect(partner.addedByYou, isFalse);

    final ownOther =
        _assemble([
              _photo(1, sender: _ownOther),
              _manifest(9, [1], sender: _ownOther),
            ]).single
            as Moment;
    expect(ownOther.status, MomentStatus.received);
    expect(ownOther.addedByYou, isTrue);
  });

  test('photos not here yet are counted, never invented', () {
    final arriving =
        _assemble([
              _photo(1, sender: _partner),
              _manifest(9, [1, 2, 3], sender: _partner),
            ]).single
            as Moment;
    expect(arriving.photos, hasLength(1));
    expect(arriving.photoCount, 3);
    expect(arriving.problem, MomentProblem.photosArriving);

    final lost =
        _assemble([
              _manifest(9, [1]),
            ]).single
            as Moment;
    expect(lost.photos, isEmpty);
    expect(lost.problem, MomentProblem.photosMissing);
  });

  group('fails closed', () {
    test("a moment cannot claim the partner's photos (re-attribution)", () {
      final entries = _assemble([
        _photo(1, sender: _partner),
        _manifest(9, [1]),
      ]);
      expect(entries.single, isA<UnreadableMoment>());
    });

    test('references to texts, videos or other moments are refused', () {
      final text = TextPayload(text: 'hi', clientTimeMs: 1).encode();
      expect(
        _assemble([
          _msg(1, text),
          _manifest(9, [1]),
        ]).single,
        isA<UnreadableMoment>(),
      );
      expect(
        _assemble([
          _photo(1, mediaClass: MediaClass.video),
          _manifest(9, [1]),
        ]).single,
        isA<UnreadableMoment>(),
      );
      expect(
        _assemble([
          _photo(1),
          _manifest(8, [1], time: 1),
          _manifest(9, [8], time: 2),
        ]).whereType<UnreadableMoment>(),
        hasLength(1),
      );
    });

    test('a photo belongs to one moment: the earliest claim wins', () {
      final entries = _assemble([
        _photo(1),
        _manifest(9, [1], time: 2000, caption: 'later'),
        _manifest(8, [1], time: 1000, caption: 'first'),
      ]);
      final good = entries.whereType<Moment>().single;
      expect(good.caption, 'first');
      expect(entries.whereType<UnreadableMoment>().single.handle.value, _id(9));
    });

    test('malformed or newer manifests are unreadable, with their time', () {
      final bad = _manifest(9, [1]).payload..[11] = 9; // unknown schema
      final entries = _assemble([
        _photo(1),
        _msg(9, bad, time: 5000),
        _msg(7, Uint8List.fromList([1, 3, 0]), time: 6000),
      ]);
      expect(entries, everyElement(isA<UnreadableMoment>()));
      expect(entries, hasLength(2));
      expect(entries.first.addedAt, DateTime.fromMillisecondsSinceEpoch(6000));
    });
  });

  test('texts and photos outside a moment are not moments', () {
    final text = TextPayload(text: 'hi', clientTimeMs: 1).encode();
    expect(_assemble([_msg(1, text), _photo(2)]), isEmpty);
  });

  test('newest day first; a memory date files it under that day', () {
    final day = DateTime(2026, 10, 20, 12).millisecondsSinceEpoch;
    final entries = _assemble([
      _photo(1),
      _photo(2),
      _photo(3),
      _manifest(7, [1], time: day, caption: 'today'),
      _manifest(
        8,
        [2],
        time: day + 1,
        caption: 'old',
        date: MomentDate(2019, 3, 4),
      ),
      _manifest(9, [3], time: day + 2, caption: 'today later'),
    ]);
    expect(
      [for (final e in entries) (e as Moment).caption],
      ['today later', 'today', 'old'],
    );
  });

  test('handles and entries never print identifiers', () {
    final entries = _assemble([
      _photo(1),
      _manifest(9, [1], caption: 'x'),
    ]);
    final m = entries.single as Moment;
    for (final s in ['$m', '${m.handle}', '${m.photos.single}']) {
      expect(s, isNot(contains(_id(9))));
      expect(s, isNot(contains(_id(1))));
    }
  });
}
