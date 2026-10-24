import 'dart:convert';
import 'dart:typed_data';

import 'package:sirf_hum/security/moments/moment_payload.dart';

/// Why a notebook payload cannot be built or read. Categories only; never
/// the text.
enum NotebookPayloadFailure {
  malformed,
  unsupported,
  missingTitle,
  titleTooLong,
  noteTooLong,
  detailTooLong,
  invalidText,
  invalidCategory,
  invalidStatus,
  invalidDate,
  invalidProgress,
}

class NotebookPayloadException implements Exception {
  const NotebookPayloadException(this.failure);

  final NotebookPayloadFailure failure;

  @override
  String toString() => 'NotebookPayloadException(${failure.name})';
}

/// Which part of the couple's notebook a record belongs to (D-119). A
/// small, closed set: Future's plans and Us's story, little things, rituals
/// and "together since".
enum NotebookSection {
  /// Future: something the two of you want to do (D-120).
  future(1),

  /// Us: one part of your story ("How we started").
  story(2),

  /// Us: one of your little things ("Our song").
  littleThing(3),

  /// Us: something you do together, regularly or not.
  ritual(4),

  /// Us: the day you got together. At most one is shown.
  togetherSince(5);

  const NotebookSection(this.wireValue);

  final int wireValue;

  static NotebookSection? fromWire(int value) {
    for (final s in values) {
      if (s.wireValue == value) return s;
    }
    return null;
  }
}

/// Future's kinds of plan (D-120), and dreams: a long-term goal with a
/// progress the two of you set (D-157).
enum FutureCategory {
  plan(1),
  place(2),
  tryThing(3),
  importantDate(4),
  dream(5);

  const FutureCategory(this.wireValue);

  final int wireValue;

  static FutureCategory? fromWire(int value) {
    for (final c in values) {
      if (c.wireValue == value) return c;
    }
    return null;
  }
}

enum FutureStatus {
  planned(1),
  done(2);

  const FutureStatus(this.wireValue);

  final int wireValue;

  static FutureStatus? fromWire(int value) {
    for (final s in values) {
      if (s.wireValue == value) return s;
    }
    return null;
  }
}

/// The kinds of little thing (D-120). "Other" keeps the set small without
/// leaving anything out.
enum LittleThingKind {
  favouriteFood(1),
  comfortFood(2),
  favouriteMovie(3),
  ourSong(4),
  favouritePlace(5),
  insideJoke(6),
  alwaysDo(7),
  other(8);

  const LittleThingKind(this.wireValue);

  final int wireValue;

  static LittleThingKind? fromWire(int value) {
    for (final k in values) {
      if (k.wireValue == value) return k;
    }
    return null;
  }
}

enum NotebookOp {
  /// A new record; its ID is this message's ID.
  create(1),

  /// Replaces every field of the target record.
  update(2),

  /// Removes the target record for both phones. Terminal.
  remove(3);

  const NotebookOp(this.wireValue);

  final int wireValue;

  static NotebookOp? fromWire(int value) {
    for (final o in values) {
      if (o.wireValue == value) return o;
    }
    return null;
  }
}

/// The fields of one notebook record, validated for its section. [title],
/// [note], [detail] and [date] are private content: never log them.
class NotebookFields {
  NotebookFields({
    required this.section,
    this.category = 0,
    this.status = 0,
    this.date,
    this.progress,
    String? title,
    String? note,
    String? detail,
  }) : title = _normalized(title),
       note = _normalized(note),
       detail = _normalized(detail) {
    _validate();
  }

  /// Wire limits (D-119). The screens ask for less; these bound what any
  /// client may send, well under the core's 16 KiB payload limit.
  static const int maxTitleBytes = 400;
  static const int maxNoteBytes = 4000;
  static const int maxDetailBytes = 160;

  final NotebookSection section;

  /// A [FutureCategory] or [LittleThingKind] wire value; 0 elsewhere.
  final int category;

  /// A [FutureStatus] wire value for Future; 0 elsewhere.
  final int status;
  final MomentDate? date;
  final String title;
  final String note;
  final String detail;

  /// How far a dream has come, 0–100, set by either of you. Present exactly
  /// for [FutureCategory.dream] (D-157).
  final int? progress;

  static const int maxProgress = 100;

  bool get isDream =>
      section == NotebookSection.future &&
      category == FutureCategory.dream.wireValue;

  void _validate() {
    void fail(NotebookPayloadFailure f) => throw NotebookPayloadException(f);
    final titled = section != NotebookSection.togetherSince;
    if (titled && title.isEmpty) fail(NotebookPayloadFailure.missingTitle);
    if (!titled && title.isNotEmpty) fail(NotebookPayloadFailure.malformed);
    if (utf8.encode(title).length > maxTitleBytes) {
      fail(NotebookPayloadFailure.titleTooLong);
    }
    if (utf8.encode(note).length > maxNoteBytes) {
      fail(NotebookPayloadFailure.noteTooLong);
    }
    if (utf8.encode(detail).length > maxDetailBytes) {
      fail(NotebookPayloadFailure.detailTooLong);
    }
    // Titles and details are one line; notes may have line breaks.
    if (_control.hasMatch(title) || _control.hasMatch(detail)) {
      fail(NotebookPayloadFailure.invalidText);
    }
    if (_controlExceptNewline.hasMatch(note)) {
      fail(NotebookPayloadFailure.invalidText);
    }
    final categoryOk = switch (section) {
      NotebookSection.future => FutureCategory.fromWire(category) != null,
      NotebookSection.littleThing => LittleThingKind.fromWire(category) != null,
      _ => category == 0,
    };
    if (!categoryOk) fail(NotebookPayloadFailure.invalidCategory);
    final statusOk = section == NotebookSection.future
        ? FutureStatus.fromWire(status) != null
        : status == 0;
    if (!statusOk) fail(NotebookPayloadFailure.invalidStatus);
    final dateOk = switch (section) {
      NotebookSection.future || NotebookSection.story => true,
      NotebookSection.togetherSince => date != null,
      NotebookSection.littleThing || NotebookSection.ritual => date == null,
    };
    if (!dateOk) fail(NotebookPayloadFailure.invalidDate);
    final noteOk = switch (section) {
      NotebookSection.togetherSince => note.isEmpty,
      _ => true,
    };
    if (!noteOk) fail(NotebookPayloadFailure.malformed);
    if (section != NotebookSection.ritual && detail.isNotEmpty) {
      fail(NotebookPayloadFailure.malformed);
    }
    final progress = this.progress;
    final progressOk = isDream
        ? progress != null && progress >= 0 && progress <= maxProgress
        : progress == null;
    if (!progressOk) fail(NotebookPayloadFailure.invalidProgress);
  }

  static final RegExp _control = RegExp(r'[\u0000-\u001F\u007F-\u009F]');
  static final RegExp _controlExceptNewline = RegExp(
    r'[\u0000-\u0009\u000B-\u001F\u007F-\u009F]',
  );

  static String _normalized(String? text) => text?.trim() ?? '';

  @override
  String toString() => 'NotebookFields(${section.name}, <redacted>)';
}

/// The encrypted application payload of one notebook operation (kind 4,
/// D-119). Like a moment's manifest (D-114) it exists only inside MLS
/// ciphertext and the sealed local history:
///
/// ```text
/// version u8 = 1 | kind u8 = 4 | client time ms u64 BE | notebook schema u16 BE = 1
/// | op u8 (1 create, 2 update, 3 remove) | target record id [16] (zero for create)
/// | section u8 | category u8 | status u8
/// | date: year u16 BE | month u8 | day u8            (all zero: no date)
/// | title len u16 BE | title UTF-8 | note len u16 BE | note UTF-8
/// | detail len u8 | detail UTF-8
/// | progress u8                                       (schema 2 only)
/// ```
///
/// Schema 2 (D-157) exists only for dreams: it appends their progress.
/// Every other record is still written as schema 1, byte for byte, so
/// nothing that already exists changes; both schemas are read.
///
/// A record's ID is the message ID of its `create`, chosen by the core. No
/// couple, account or device field exists: the couple is the conversation
/// (MLS AAD), the author is the MLS-authenticated sender. Unknown versions,
/// kinds, schemas, ops, sections or values fail closed.
class NotebookPayload {
  NotebookPayload._({
    required this.op,
    required this.clientTimeMs,
    required this.section,
    this.target,
    this.fields,
  });

  factory NotebookPayload.create({
    required NotebookFields fields,
    required int clientTimeMs,
  }) => NotebookPayload._(
    op: NotebookOp.create,
    clientTimeMs: clientTimeMs,
    section: fields.section,
    fields: fields,
  );

  factory NotebookPayload.update({
    required String target,
    required NotebookFields fields,
    required int clientTimeMs,
  }) => NotebookPayload._(
    op: NotebookOp.update,
    clientTimeMs: clientTimeMs,
    section: fields.section,
    target: _checkedTarget(target),
    fields: fields,
  );

  factory NotebookPayload.remove({
    required String target,
    required NotebookSection section,
    required int clientTimeMs,
  }) => NotebookPayload._(
    op: NotebookOp.remove,
    clientTimeMs: clientTimeMs,
    section: section,
    target: _checkedTarget(target),
  );

  static const int version = 1;
  static const int kindNotebook = 4;
  static const int schema = 1;

  /// Schema 1 plus a trailing progress byte (dreams, D-157).
  static const int schemaWithProgress = 2;

  static const int _headerBytes = 36;
  static final RegExp _hexId = RegExp(r'^[0-9a-f]{32}$');
  static const String _zeroId = '00000000000000000000000000000000';

  final NotebookOp op;
  final NotebookSection section;

  /// The record an update or remove applies to (lowercase hex message ID).
  final String? target;

  /// Null for [NotebookOp.remove].
  final NotebookFields? fields;

  /// The sender's clock, display only (ordering uses server time, D-091).
  final int clientTimeMs;

  /// True when [bytes] claims to be a notebook record (version 1, kind 4).
  static bool isNotebook(Uint8List bytes) =>
      bytes.length >= 2 && bytes[0] == version && bytes[1] == kindNotebook;

  Uint8List encode() {
    final f = fields;
    final title = utf8.encode(f?.title ?? '');
    final note = utf8.encode(f?.note ?? '');
    final detail = utf8.encode(f?.detail ?? '');
    final progress = f?.progress;
    final length =
        _headerBytes +
        2 +
        title.length +
        2 +
        note.length +
        1 +
        detail.length +
        (progress == null ? 0 : 1);
    final out = ByteData(length)
      ..setUint8(0, version)
      ..setUint8(1, kindNotebook)
      ..setUint64(2, clientTimeMs, Endian.big)
      ..setUint16(
        10,
        progress == null ? schema : schemaWithProgress,
        Endian.big,
      )
      ..setUint8(12, op.wireValue)
      ..setUint8(29, section.wireValue)
      ..setUint8(30, f?.category ?? 0)
      ..setUint8(31, f?.status ?? 0)
      ..setUint16(32, f?.date?.year ?? 0, Endian.big)
      ..setUint8(34, f?.date?.month ?? 0)
      ..setUint8(35, f?.date?.day ?? 0);
    final bytes = out.buffer.asUint8List();
    final id = target ?? _zeroId;
    for (var i = 0; i < 16; i++) {
      bytes[13 + i] = int.parse(id.substring(2 * i, 2 * i + 2), radix: 16);
    }
    var at = _headerBytes;
    out.setUint16(at, title.length, Endian.big);
    bytes.setRange(at + 2, at + 2 + title.length, title);
    at += 2 + title.length;
    out.setUint16(at, note.length, Endian.big);
    bytes.setRange(at + 2, at + 2 + note.length, note);
    at += 2 + note.length;
    out.setUint8(at, detail.length);
    bytes.setRange(at + 1, at + 1 + detail.length, detail);
    at += 1 + detail.length;
    if (progress != null) out.setUint8(at, progress);
    return bytes;
  }

  /// Strict decode: exact length, known version, kind, schema, op and
  /// section, values valid for the section, a real date or none, valid
  /// normalized UTF-8. A remove carries no content at all.
  static NotebookPayload decode(Uint8List bytes) {
    const malformed = NotebookPayloadException(
      NotebookPayloadFailure.malformed,
    );
    if (bytes.length < _headerBytes + 5) throw malformed;
    final view = ByteData.sublistView(bytes);
    final wireSchema = view.getUint16(10, Endian.big);
    if (!isNotebook(bytes) ||
        (wireSchema != schema && wireSchema != schemaWithProgress)) {
      throw const NotebookPayloadException(NotebookPayloadFailure.unsupported);
    }
    final op = NotebookOp.fromWire(view.getUint8(12));
    final section = NotebookSection.fromWire(view.getUint8(29));
    if (op == null || section == null) {
      throw const NotebookPayloadException(NotebookPayloadFailure.unsupported);
    }
    final target = _hex(bytes.sublist(13, 29));
    if ((op == NotebookOp.create) != (target == _zeroId)) throw malformed;

    var at = _headerBytes;
    int length(int width) {
      if (bytes.length < at + width) throw malformed;
      final value = width == 2
          ? view.getUint16(at, Endian.big)
          : view.getUint8(at);
      at += width;
      return value;
    }

    String text(int n) {
      if (bytes.length < at + n) throw malformed;
      final String value;
      try {
        value = utf8.decode(bytes.sublist(at, at + n), allowMalformed: false);
      } on FormatException {
        throw malformed;
      }
      at += n;
      // Text that changes under normalization was not written by us.
      if (value.trim() != value) throw malformed;
      return value;
    }

    final title = text(length(2));
    final note = text(length(2));
    final detail = text(length(1));
    final progress = wireSchema == schemaWithProgress ? length(1) : null;
    if (at != bytes.length) throw malformed;

    final category = view.getUint8(30);
    final status = view.getUint8(31);
    final year = view.getUint16(32, Endian.big);
    final month = view.getUint8(34);
    final day = view.getUint8(35);
    final clientTimeMs = view.getUint64(2, Endian.big);

    if (op == NotebookOp.remove) {
      // A remove carries nothing, so it is only ever schema 1.
      if (progress != null) throw malformed;
      final empty =
          category == 0 &&
          status == 0 &&
          year == 0 &&
          month == 0 &&
          day == 0 &&
          title.isEmpty &&
          note.isEmpty &&
          detail.isEmpty;
      if (!empty) throw malformed;
      return NotebookPayload._(
        op: op,
        clientTimeMs: clientTimeMs,
        section: section,
        target: target,
      );
    }

    final MomentDate? date;
    if (year == 0 && month == 0 && day == 0) {
      date = null;
    } else {
      try {
        date = MomentDate(year, month, day);
      } on MomentPayloadException {
        throw const NotebookPayloadException(
          NotebookPayloadFailure.invalidDate,
        );
      }
    }
    final fields = NotebookFields(
      section: section,
      category: category,
      status: status,
      date: date,
      progress: progress,
      title: title,
      note: note,
      detail: detail,
    );
    return NotebookPayload._(
      op: op,
      clientTimeMs: clientTimeMs,
      section: section,
      target: op == NotebookOp.create ? null : target,
      fields: fields,
    );
  }

  static String _checkedTarget(String target) {
    if (!_hexId.hasMatch(target) || target == _zeroId) {
      throw const NotebookPayloadException(NotebookPayloadFailure.malformed);
    }
    return target;
  }

  static String _hex(List<int> bytes) =>
      [for (final b in bytes) b.toRadixString(16).padLeft(2, '0')].join();

  @override
  String toString() =>
      'NotebookPayload(${op.name}, ${section.name}, <redacted>)';
}
