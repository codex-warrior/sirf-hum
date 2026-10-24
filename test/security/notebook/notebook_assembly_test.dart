// Notebook assembly (D-119): how creates, updates and removes combine,
// which operations fail closed, and that both phones converge. Pure: runs
// without the native core.
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sirf_hum/security/messaging/text_payload.dart';
import 'package:sirf_hum/security/moments/moment_payload.dart';
import 'package:sirf_hum/security/notebook/notebook.dart';
import 'package:sirf_hum/security/notebook/notebook_payload.dart';
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

/// [viewer] is the phone assembling: its own messages are outgoing.
LocalMessage _msg(
  int n,
  Uint8List payload, {
  DeviceId? sender,
  DeviceId? viewer,
  MessageState? state,
  int? time,
}) {
  final from = sender ?? _own;
  final outgoing = from == (viewer ?? _own);
  final s = state ?? (outgoing ? MessageState.sent : MessageState.received);
  final t = time ?? 1000 + n;
  return LocalMessage(
    messageId: _mid(n),
    senderDeviceId: from,
    direction: outgoing ? MessageDirection.outgoing : MessageDirection.incoming,
    state: s,
    epoch: 1,
    createdAtMs: t,
    serverTimeMs: s == MessageState.queued ? 0 : t,
    payload: payload,
    ciphertext: s == MessageState.queued ? Uint8List(1) : null,
  );
}

NotebookFields _plan(
  String title, {
  FutureStatus status = FutureStatus.planned,
  FutureCategory category = FutureCategory.plan,
}) => NotebookFields(
  section: NotebookSection.future,
  category: category.wireValue,
  status: status.wireValue,
  title: title,
);

Uint8List _create(NotebookFields f) =>
    NotebookPayload.create(fields: f, clientTimeMs: 1).encode();

Uint8List _update(int target, NotebookFields f) => NotebookPayload.update(
  target: _id(target),
  fields: f,
  clientTimeMs: 1,
).encode();

Uint8List _remove(int target, [NotebookSection s = NotebookSection.future]) =>
    NotebookPayload.remove(
      target: _id(target),
      section: s,
      clientTimeMs: 1,
    ).encode();

NotebookSnapshot _assemble(List<LocalMessage> history) =>
    assembleNotebook(history, isOwnAccount: (d) => d == _own || d == _ownOther);

void main() {
  test('create → entry with its own message ID as handle', () {
    final snap = _assemble([_msg(1, _create(_plan('Go to Udaipur')))]);
    final e = snap.entries.single;
    expect(e.handle, NotebookHandle(_id(1)));
    expect(e.title, 'Go to Udaipur');
    expect(e.futureCategory, FutureCategory.plan);
    expect(e.done, isFalse);
    expect(e.addedByYou, isTrue);
    expect(e.saving, isFalse);
    expect(snap.unreadable, 0);
  });

  test('update replaces every field; the last change wins by server time, '
      'whatever order the history lists them in', () {
    final history = [
      _msg(3, _update(1, _plan('Udaipur, finally')), time: 3000),
      _msg(1, _create(_plan('Go to Udaipur')), time: 1000),
      _msg(
        2,
        _update(1, _plan('Udaipur', status: FutureStatus.done)),
        sender: _partner,
        time: 2000,
      ),
    ];
    final e = _assemble(history).entries.single;
    expect(e.title, 'Udaipur, finally');
    expect(e.done, isFalse);
    expect(e.changedByYou, isTrue);
    expect(e.changedAt, DateTime.fromMillisecondsSinceEpoch(3000));
    expect(e.addedAt, DateTime.fromMillisecondsSinceEpoch(1000));
  });

  test('a tie in server time is broken by message ID, the same on both '
      'phones', () {
    List<LocalMessage> on(DeviceId viewer) => [
      _msg(1, _create(_plan('a')), viewer: viewer, time: 1000),
      _msg(5, _update(1, _plan('from A')), viewer: viewer, time: 2000),
      _msg(
        4,
        _update(1, _plan('from B')),
        sender: _partner,
        viewer: viewer,
        time: 2000,
      ),
    ];
    final mine = _assemble(on(_own)).entries.single;
    final theirs = assembleNotebook(
      on(_partner),
      isOwnAccount: (d) => d == _partner,
    ).entries.single;
    expect(mine.title, 'from A');
    expect(theirs.title, 'from A');
  });

  test('either partner may complete, edit or remove: the notebook is '
      'shared', () {
    final snap = _assemble([
      _msg(1, _create(_plan('Goa'))),
      _msg(2, _create(_plan('Manali'))),
      _msg(
        3,
        _update(1, _plan('Goa', status: FutureStatus.done)),
        sender: _partner,
      ),
      _msg(4, _remove(2), sender: _partner),
    ]);
    expect(snap.entries.single.title, 'Goa');
    expect(snap.entries.single.done, isTrue);
    expect(snap.entries.single.changedByYou, isFalse);
  });

  test('remove is final: later changes do nothing, a second remove is '
      'harmless', () {
    final snap = _assemble([
      _msg(1, _create(_plan('Goa'))),
      _msg(2, _remove(1)),
      _msg(3, _update(1, _plan('Goa again')), sender: _partner),
      _msg(4, _remove(1), sender: _partner),
    ]);
    expect(snap.entries, isEmpty);
    expect(snap.unreadable, 0);
  });

  test('a change to a record that is not here does nothing', () {
    final snap = _assemble([
      _msg(2, _update(99, _plan('ghost')), sender: _partner),
      _msg(3, _remove(98), sender: _partner),
    ]);
    expect(snap.entries, isEmpty);
    expect(snap.unreadable, 0);
  });

  test('a change that names the wrong section fails closed', () {
    final story = NotebookFields(
      section: NotebookSection.story,
      title: 'Hijacked',
    );
    final snap = _assemble([
      _msg(1, _create(_plan('Goa'))),
      _msg(2, _update(1, story), sender: _partner),
      _msg(3, _remove(1, NotebookSection.ritual), sender: _partner),
    ]);
    expect(snap.entries.single.title, 'Goa');
    expect(snap.entries.single.section, NotebookSection.future);
    expect(snap.unreadable, 2);
  });

  test('malformed or newer payloads are counted, never shown', () {
    final newer = _create(_plan('x'))..[11] = 2; // schema 2
    final truncated = _create(_plan('x')).sublist(0, 30);
    final snap = _assemble([
      _msg(1, newer, sender: _partner),
      _msg(2, truncated, sender: _partner),
      _msg(3, _create(_plan('real'))),
    ]);
    expect(snap.entries.single.title, 'real');
    expect(snap.unreadable, 2);
  });

  test('texts, moments and media are not notebook records', () {
    final snap = _assemble([
      _msg(1, TextPayload(text: 'hello', clientTimeMs: 1).encode()),
      _msg(
        2,
        MomentPayload(photoMessageIds: [_id(1)], clientTimeMs: 1).encode(),
      ),
    ]);
    expect(snap.entries, isEmpty);
    expect(snap.unreadable, 0);
  });

  test('a change still in the outbox shows at once, marked saving', () {
    final snap = _assemble([
      _msg(1, _create(_plan('Goa'))),
      _msg(2, _update(1, _plan('Goa in March')), state: MessageState.queued),
      _msg(3, _create(_plan('Manali')), state: MessageState.queued),
      _msg(4, _create(_plan('Pondicherry')), state: MessageState.queued),
      _msg(5, _remove(4), state: MessageState.queued),
    ]);
    expect(snap.entries.map((e) => e.title), ['Goa in March', 'Manali']);
    expect(snap.entries.every((e) => e.saving), isTrue);
  });

  test('another phone of this account counts as you; the partner does '
      'not', () {
    final snap = _assemble([
      _msg(1, _create(_plan('mine')), sender: _ownOther),
      _msg(2, _create(_plan('theirs')), sender: _partner),
    ]);
    expect(snap.entries.map((e) => e.addedByYou), [true, false]);
  });

  test('entries keep the order they were added; sections filter', () {
    final snap = _assemble([
      _msg(2, _create(_plan('second')), time: 2000),
      _msg(
        1,
        _create(
          NotebookFields(
            section: NotebookSection.ritual,
            title: 'Sunday call',
            detail: 'Sundays',
          ),
        ),
        time: 1000,
      ),
      _msg(3, _create(_plan('third')), time: 3000),
    ]);
    expect(snap.entries.map((e) => e.title), [
      'Sunday call',
      'second',
      'third',
    ]);
    expect(snap.section(NotebookSection.future), hasLength(2));
    expect(snap.section(NotebookSection.ritual).single.detail, 'Sundays');
  });

  test('protocol IDs cover every kind-4 message, readable or not', () {
    final bad = _create(_plan('x'))..[12] = 9;
    final history = [
      _msg(1, _create(_plan('a'))),
      _msg(2, bad),
      _msg(3, TextPayload(text: 'chat', clientTimeMs: 1).encode()),
    ];
    expect(notebookProtocolMessageIds(history), {_id(1), _id(2)});
  });

  test('entries and snapshots never print content', () {
    final snap = _assemble([_msg(1, _create(_plan('SECRET-PLAN')))]);
    expect('$snap', isNot(contains('SECRET')));
    expect('${snap.entries.single}', isNot(contains('SECRET')));
    expect('${snap.entries.single.handle}', isNot(contains(_id(1))));
  });

  test('a dream keeps the progress of its latest version, from either '
      'phone (D-157)', () {
    NotebookFields dream(int progress) => NotebookFields(
      section: NotebookSection.future,
      category: FutureCategory.dream.wireValue,
      status: FutureStatus.planned.wireValue,
      title: 'A home together',
      progress: progress,
    );
    final snap = _assemble([
      _msg(1, _create(dream(10))),
      _msg(2, _update(1, dream(42)), sender: _partner),
      _msg(3, _create(_plan('Goa'))),
    ]);
    final entries = snap.section(NotebookSection.future).toList();
    final home = entries.singleWhere((e) => e.title == 'A home together');
    expect(home.progress, 42);
    expect(home.futureCategory, FutureCategory.dream);
    expect(home.fields.progress, 42, reason: 'an edit starts from it');
    expect(entries.singleWhere((e) => e.title == 'Goa').progress, isNull);
  });
}
