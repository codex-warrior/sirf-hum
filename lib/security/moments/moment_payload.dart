import 'dart:convert';
import 'dart:typed_data';

/// Why a moment payload cannot be built or read. Categories only; never the
/// caption.
enum MomentPayloadFailure {
  malformed,
  unsupported,
  noPhotos,
  tooManyPhotos,
  duplicatePhoto,
  captionTooLong,
  invalidDate,
}

class MomentPayloadException implements Exception {
  const MomentPayloadException(this.failure);

  final MomentPayloadFailure failure;

  @override
  String toString() => 'MomentPayloadException(${failure.name})';
}

/// A calendar day ("when it happened"), with no time and no time zone: the
/// least a memory date needs to say. Years 1900–2199.
class MomentDate implements Comparable<MomentDate> {
  MomentDate(this.year, this.month, this.day) {
    if (year < minYear || year > maxYear || month < 1 || month > 12) {
      throw const MomentPayloadException(MomentPayloadFailure.invalidDate);
    }
    final probe = DateTime.utc(year, month, day);
    if (day < 1 || probe.month != month || probe.day != day) {
      throw const MomentPayloadException(MomentPayloadFailure.invalidDate);
    }
  }

  factory MomentDate.of(DateTime time) =>
      MomentDate(time.year, time.month, time.day);

  static const int minYear = 1900;
  static const int maxYear = 2199;

  final int year;
  final int month;
  final int day;

  /// Midnight of this day in local time, for display and ordering.
  DateTime toLocal() => DateTime(year, month, day);

  @override
  int compareTo(MomentDate other) =>
      (year * 10000 + month * 100 + day) -
      (other.year * 10000 + other.month * 100 + other.day);

  @override
  bool operator ==(Object other) =>
      other is MomentDate &&
      other.year == year &&
      other.month == month &&
      other.day == day;

  @override
  int get hashCode => Object.hash(year, month, day);

  @override
  String toString() => 'MomentDate(<redacted>)';
}

/// The encrypted application payload of a moment's manifest (kind 3,
/// D-114). It exists only inside MLS ciphertext and the sealed local
/// history, like a text (D-089, D-090):
///
/// ```text
/// version u8 = 1 | kind u8 = 3 | client time ms u64 BE | moment schema u16 BE = 1
/// | memory date: year u16 BE | month u8 | day u8        (all zero: no date)
/// | photo count u8 (1..8) | count × photo message id [16]
/// | caption length u16 BE | caption UTF-8 (0..2,000 bytes)
/// ```
///
/// The photos are the moment's own media messages (kind 2, built only by the
/// core, D-094), referenced by message ID. No key, hash, file name, class,
/// size, location or device detail is here: the caption and the date are the
/// only content, and both are private. Unknown versions, kinds or schemas
/// fail closed.
class MomentPayload {
  MomentPayload({
    required List<String> photoMessageIds,
    required this.clientTimeMs,
    String? caption,
    this.memoryDate,
  }) : photoMessageIds = List.unmodifiable(photoMessageIds),
       caption = _normalized(caption) {
    if (photoMessageIds.isEmpty) {
      throw const MomentPayloadException(MomentPayloadFailure.noPhotos);
    }
    if (photoMessageIds.length > maxPhotos) {
      throw const MomentPayloadException(MomentPayloadFailure.tooManyPhotos);
    }
    if (photoMessageIds.any((id) => !_hexId.hasMatch(id))) {
      throw const MomentPayloadException(MomentPayloadFailure.malformed);
    }
    if (photoMessageIds.toSet().length != photoMessageIds.length) {
      throw const MomentPayloadException(MomentPayloadFailure.duplicatePhoto);
    }
    final text = this.caption;
    if (text != null && utf8.encode(text).length > maxCaptionBytes) {
      throw const MomentPayloadException(MomentPayloadFailure.captionTooLong);
    }
  }

  static const int version = 1;
  static const int kindMoment = 3;
  static const int schema = 1;

  /// A conservative V1 bound (D-114): a moment is a few photos, not an
  /// album. With the manifest that is at most 9 outbox slots of 100.
  static const int maxPhotos = 8;

  /// Fits easily under the core's 16 KiB payload limit.
  static const int maxCaptionBytes = 2000;

  static const int _headerBytes = 17;
  static final RegExp _hexId = RegExp(r'^[0-9a-f]{32}$');

  /// Media message IDs (lowercase hex), in display order.
  final List<String> photoMessageIds;

  /// Private content: never log it. Null when there is none.
  final String? caption;

  /// Private content.
  final MomentDate? memoryDate;

  /// The sender's clock, display only (ordering uses server time, D-091).
  final int clientTimeMs;

  /// True when [bytes] claims to be a moment (version 1, kind 3).
  static bool isMoment(Uint8List bytes) =>
      bytes.length >= 2 && bytes[0] == version && bytes[1] == kindMoment;

  Uint8List encode() {
    final text = caption == null ? Uint8List(0) : utf8.encode(caption!);
    final count = photoMessageIds.length;
    final out = ByteData(_headerBytes + 16 * count + 2 + text.length)
      ..setUint8(0, version)
      ..setUint8(1, kindMoment)
      ..setUint64(2, clientTimeMs, Endian.big)
      ..setUint16(10, schema, Endian.big)
      ..setUint16(12, memoryDate?.year ?? 0, Endian.big)
      ..setUint8(14, memoryDate?.month ?? 0)
      ..setUint8(15, memoryDate?.day ?? 0)
      ..setUint8(16, count);
    final bytes = out.buffer.asUint8List();
    var at = _headerBytes;
    for (final id in photoMessageIds) {
      for (var i = 0; i < 32; i += 2) {
        bytes[at++] = int.parse(id.substring(i, i + 2), radix: 16);
      }
    }
    out.setUint16(at, text.length, Endian.big);
    bytes.setRange(at + 2, at + 2 + text.length, text);
    return bytes;
  }

  /// Strict decode: exact length, known version, kind and schema, a real
  /// date or none, 1..8 distinct photos, valid UTF-8.
  static MomentPayload decode(Uint8List bytes) {
    if (bytes.length < _headerBytes + 16 + 2) {
      throw const MomentPayloadException(MomentPayloadFailure.malformed);
    }
    final view = ByteData.sublistView(bytes);
    if (!isMoment(bytes) || view.getUint16(10, Endian.big) != schema) {
      throw const MomentPayloadException(MomentPayloadFailure.unsupported);
    }
    final year = view.getUint16(12, Endian.big);
    final month = view.getUint8(14);
    final day = view.getUint8(15);
    final count = view.getUint8(16);
    if (count < 1 || count > maxPhotos) {
      throw const MomentPayloadException(MomentPayloadFailure.malformed);
    }
    final textAt = _headerBytes + 16 * count;
    if (bytes.length < textAt + 2) {
      throw const MomentPayloadException(MomentPayloadFailure.malformed);
    }
    final textLength = view.getUint16(textAt, Endian.big);
    if (bytes.length != textAt + 2 + textLength ||
        textLength > maxCaptionBytes) {
      throw const MomentPayloadException(MomentPayloadFailure.malformed);
    }
    final MomentDate? date;
    if (year == 0 && month == 0 && day == 0) {
      date = null;
    } else {
      date = MomentDate(year, month, day);
    }
    final ids = [
      for (var i = 0; i < count; i++)
        _hex(bytes.sublist(_headerBytes + 16 * i, _headerBytes + 16 * i + 16)),
    ];
    final String text;
    try {
      text = utf8.decode(bytes.sublist(textAt + 2), allowMalformed: false);
    } on FormatException {
      throw const MomentPayloadException(MomentPayloadFailure.malformed);
    }
    // A caption that changes under normalization was not written by us.
    if (textLength > 0 && _normalized(text) != text) {
      throw const MomentPayloadException(MomentPayloadFailure.malformed);
    }
    return MomentPayload(
      photoMessageIds: ids,
      clientTimeMs: view.getUint64(2, Endian.big),
      caption: textLength == 0 ? null : text,
      memoryDate: date,
    );
  }

  static String? _normalized(String? caption) {
    final text = caption?.trim();
    return text == null || text.isEmpty ? null : text;
  }

  static String _hex(List<int> bytes) =>
      [for (final b in bytes) b.toRadixString(16).padLeft(2, '0')].join();

  @override
  String toString() =>
      'MomentPayload(${photoMessageIds.length} photos, <redacted>)';
}
