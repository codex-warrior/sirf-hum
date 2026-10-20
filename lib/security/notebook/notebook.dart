import 'package:sirf_hum/security/messaging/message_envelope.dart';
import 'package:sirf_hum/security/moments/moment_payload.dart';
import 'package:sirf_hum/security/notebook/notebook_payload.dart';
import 'package:sirf_hum_crypto/sirf_hum_crypto.dart';

/// Opaque reference to one notebook record (the message ID of its create).
/// Issued only by the notebook service; never rendered, logged or put in a
/// URL.
final class NotebookHandle {
  const NotebookHandle(this.value);

  final String value;

  @override
  bool operator ==(Object other) =>
      other is NotebookHandle && other.value == value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => 'NotebookHandle(<redacted>)';
}

/// One live record of the couple's notebook, as this phone sees it now.
/// [title], [note], [detail] and [date] are private content: display only,
/// never log or persist elsewhere.
final class NotebookEntry {
  const NotebookEntry({
    required this.handle,
    required this.section,
    required this.category,
    required this.status,
    required this.title,
    required this.note,
    required this.detail,
    required this.addedByYou,
    required this.changedByYou,
    required this.addedAt,
    required this.changedAt,
    required this.saving,
    this.date,
  });

  final NotebookHandle handle;
  final NotebookSection section;
  final int category;
  final int status;
  final String title;
  final String note;
  final String detail;
  final MomentDate? date;

  /// Who wrote the create, and who wrote the version shown (both
  /// MLS-authenticated sender devices of this account or the partner's).
  final bool addedByYou;
  final bool changedByYou;

  /// Server time when known, else this phone's (D-091).
  final DateTime addedAt;
  final DateTime changedAt;

  /// A change from this phone has not reached the server yet. It is sealed
  /// in the outbox and finishes on its own.
  final bool saving;

  FutureCategory? get futureCategory => section == NotebookSection.future
      ? FutureCategory.fromWire(category)
      : null;

  LittleThingKind? get littleThingKind => section == NotebookSection.littleThing
      ? LittleThingKind.fromWire(category)
      : null;

  bool get done =>
      section == NotebookSection.future &&
      status == FutureStatus.done.wireValue;

  /// The fields as they are, to start an edit from.
  NotebookFields get fields => NotebookFields(
    section: section,
    category: category,
    status: status,
    date: date,
    title: title,
    note: note,
    detail: detail,
  );

  @override
  String toString() =>
      'NotebookEntry(${section.name}${saving ? ', saving' : ''}, <redacted>)';
}

/// The notebook on this phone: live records in the order they were added,
/// and how many operations could not be read.
final class NotebookSnapshot {
  const NotebookSnapshot({required this.entries, required this.unreadable});

  static const empty = NotebookSnapshot(entries: [], unreadable: 0);

  final List<NotebookEntry> entries;

  /// Operations that arrived but cannot be applied: malformed, from a newer
  /// version, or contradicting their record (D-119). Shown as a quiet
  /// "something couldn't be opened", never guessed at.
  final int unreadable;

  Iterable<NotebookEntry> section(NotebookSection section) =>
      entries.where((e) => e.section == section);

  @override
  String toString() =>
      'NotebookSnapshot(${entries.length} entries, $unreadable unreadable)';
}

/// Builds the notebook from the conversation's local history (D-119).
/// Pure: every rule here is testable without the core.
///
/// Operations apply in server order (server time, else this phone's time
/// for a change still in the outbox; then message ID), so both phones reach
/// the same notebook once they hold the same messages:
/// - **create** starts a record whose handle is its own message ID;
/// - **update** replaces every field of a live record of the **same
///   section** (the last change wins);
/// - **remove** ends a record for good; later changes to it do nothing.
///
/// Either partner may change or remove any record: the notebook is shared.
/// A change whose record is not here (removed, or never received) does
/// nothing. A payload that cannot be decoded, or that names its record's
/// section wrongly, is counted as unreadable and changes nothing: it fails
/// closed.
NotebookSnapshot assembleNotebook(
  List<LocalMessage> history, {
  required bool Function(DeviceId device) isOwnAccount,
}) {
  final ops = [
    for (final m in history)
      if (NotebookPayload.isNotebook(m.payload)) m,
  ]..sort(_compareTime);

  final records = <String, _Record>{};
  var unreadable = 0;
  for (final m in ops) {
    final NotebookPayload p;
    try {
      p = NotebookPayload.decode(m.payload);
    } on NotebookPayloadException {
      unreadable++;
      continue;
    }
    final at = DateTime.fromMillisecondsSinceEpoch(_timeOf(m));
    final byYou =
        m.direction == MessageDirection.outgoing ||
        isOwnAccount(m.senderDeviceId);
    final queued = m.state == MessageState.queued;
    switch (p.op) {
      case NotebookOp.create:
        final id = _hex(m.messageId);
        records[id] = _Record(fields: p.fields!, addedByYou: byYou, addedAt: at)
          ..changed(p.fields!, at, byYou, queued);
      case NotebookOp.update:
      case NotebookOp.remove:
        final record = records[p.target];
        if (record == null || record.removed) continue;
        if (record.fields.section != p.section) {
          unreadable++;
          continue;
        }
        if (p.op == NotebookOp.remove) {
          record.removed = true;
        } else {
          record.changed(p.fields!, at, byYou, queued);
        }
    }
  }

  return NotebookSnapshot(
    entries: List.unmodifiable([
      for (final MapEntry(key: id, value: r) in records.entries)
        if (!r.removed)
          NotebookEntry(
            handle: NotebookHandle(id),
            section: r.fields.section,
            category: r.fields.category,
            status: r.fields.status,
            title: r.fields.title,
            note: r.fields.note,
            detail: r.fields.detail,
            date: r.fields.date,
            addedByYou: r.addedByYou,
            changedByYou: r.changedByYou,
            addedAt: r.addedAt,
            changedAt: r.changedAt,
            saving: r.saving,
          ),
    ]),
    unreadable: unreadable,
  );
}

/// The message IDs of the notebook protocol (every kind-4 message, readable
/// or not). A chat view of the same conversation MUST leave these out, as
/// it leaves out `momentProtocolMessageIds` (D-119).
Set<String> notebookProtocolMessageIds(List<LocalMessage> history) => {
  for (final m in history)
    if (NotebookPayload.isNotebook(m.payload)) _hex(m.messageId),
};

class _Record {
  _Record({
    required this.fields,
    required this.addedByYou,
    required this.addedAt,
  }) : changedAt = addedAt;

  NotebookFields fields;
  final bool addedByYou;
  final DateTime addedAt;
  bool changedByYou = false;
  DateTime changedAt;
  bool saving = false;
  bool removed = false;

  void changed(NotebookFields next, DateTime at, bool byYou, bool queued) {
    fields = next;
    changedAt = at;
    changedByYou = byYou;
    saving = saving || queued;
  }
}

int _timeOf(LocalMessage m) =>
    m.serverTimeMs != 0 ? m.serverTimeMs : m.createdAtMs;

int _compareTime(LocalMessage a, LocalMessage b) {
  final t = _timeOf(a).compareTo(_timeOf(b));
  return t != 0 ? t : _hex(a.messageId).compareTo(_hex(b.messageId));
}

String _hex(MessageId id) => EncryptedMessageEnvelope.hexOf(id.bytes);
