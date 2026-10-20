import 'package:sirf_hum/security/messaging/message_envelope.dart';
import 'package:sirf_hum/security/moments/moment_payload.dart';
import 'package:sirf_hum_crypto/sirf_hum_crypto.dart';

/// Opaque reference to one moment (its manifest message). Issued only by
/// the moments service; never rendered, logged or put in a URL.
final class MomentHandle {
  const MomentHandle(this.value);

  final String value;

  @override
  bool operator ==(Object other) =>
      other is MomentHandle && other.value == value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => 'MomentHandle(<redacted>)';
}

/// Opaque reference to one photo of a moment (its media message).
final class MomentPhoto {
  const MomentPhoto(this.value);

  final String value;

  @override
  bool operator ==(Object other) =>
      other is MomentPhoto && other.value == value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => 'MomentPhoto(<redacted>)';
}

enum MomentStatus {
  /// Added on this phone; some part has not reached the server yet. It is
  /// sealed in the outbox and finishes on its own (offline, interrupted).
  saving,

  /// Added on this phone and on the server.
  saved,

  /// Arrived from the partner (or from another of this account's phones).
  received,
}

enum MomentProblem {
  none,

  /// Some photos of a moment from elsewhere are not on this phone yet.
  photosArriving,

  /// Some photos of a moment from this phone were lost before they could be
  /// sent (their encrypted file vanished, D-096 `object_lost`).
  photosMissing,
}

/// One entry of the timeline.
sealed class MomentEntry {
  const MomentEntry({required this.handle, required this.addedAt});

  final MomentHandle handle;

  /// Server time when known, else this phone's (D-091).
  final DateTime addedAt;

  /// The day the timeline files it under: its memory date, else the day it
  /// was added (local time).
  DateTime get day;
}

/// A moment this phone can show. [caption] and [memoryDate] are private
/// content: display only, never log or persist elsewhere.
final class Moment extends MomentEntry {
  const Moment({
    required super.handle,
    required super.addedAt,
    required this.addedByYou,
    required this.status,
    required this.photos,
    required this.photoCount,
    required this.problem,
    this.caption,
    this.memoryDate,
  });

  final bool addedByYou;
  final MomentStatus status;

  /// The photos that are on this phone, in order.
  final List<MomentPhoto> photos;

  /// How many photos the moment has (including any not here yet).
  final int photoCount;
  final MomentProblem problem;
  final String? caption;
  final MomentDate? memoryDate;

  @override
  DateTime get day => memoryDate?.toLocal() ?? _dayOf(addedAt);

  @override
  String toString() => 'Moment(${status.name}, $photoCount photos, <redacted>)';
}

/// A moment that arrived but cannot be shown: malformed, from a newer
/// version, or referencing photos it may not (D-114). Shown as "This memory
/// couldn't be opened", never guessed at.
final class UnreadableMoment extends MomentEntry {
  const UnreadableMoment({required super.handle, required super.addedAt});

  @override
  DateTime get day => _dayOf(addedAt);

  @override
  String toString() => 'UnreadableMoment()';
}

DateTime _dayOf(DateTime time) {
  final local = time.toLocal();
  return DateTime(local.year, local.month, local.day);
}

/// Builds the timeline from the conversation's local history (D-114),
/// newest day first. Pure: every rule here is testable without the core.
///
/// A manifest is shown only if each photo it lists is, on this phone,
/// - a media message (kind 2) of class image,
/// - sent by the **same device** as the manifest (both MLS-authenticated,
///   D-089), so nobody can put the partner's photos into their own moment,
/// - and not already claimed by an earlier moment.
///
/// Anything else makes the whole moment [UnreadableMoment]: it fails
/// closed. A listed photo that is simply not here yet (eventual delivery)
/// is counted as missing, never invented.
List<MomentEntry> assembleMoments(
  List<LocalMessage> history, {
  required bool Function(DeviceId device) isOwnAccount,
}) {
  final byId = <String, LocalMessage>{
    for (final m in history) _hex(m.messageId): m,
  };
  final manifests = [
    for (final m in history)
      if (MomentPayload.isMoment(m.payload)) m,
  ]..sort(_compareTime);

  final claimed = <String>{};
  final entries = <MomentEntry>[];
  for (final m in manifests) {
    final handle = MomentHandle(_hex(m.messageId));
    final addedAt = DateTime.fromMillisecondsSinceEpoch(_timeOf(m));
    final MomentPayload payload;
    try {
      payload = MomentPayload.decode(m.payload);
    } on MomentPayloadException {
      entries.add(UnreadableMoment(handle: handle, addedAt: addedAt));
      continue;
    }
    final photos = <MomentPhoto>[];
    var missing = 0;
    var valid = true;
    var queued = m.state == MessageState.queued;
    for (final id in payload.photoMessageIds) {
      final photo = byId[id];
      if (photo == null) {
        missing++;
        continue;
      }
      final view = _mediaOf(photo);
      if (view == null ||
          view.mediaClass != MediaClass.image ||
          photo.senderDeviceId != m.senderDeviceId ||
          photo.direction != m.direction ||
          claimed.contains(id)) {
        valid = false;
        break;
      }
      photos.add(MomentPhoto(id));
      if (photo.state == MessageState.queued) queued = true;
    }
    if (!valid) {
      entries.add(UnreadableMoment(handle: handle, addedAt: addedAt));
      continue;
    }
    claimed.addAll(photos.map((p) => p.value));
    final outgoing = m.direction == MessageDirection.outgoing;
    entries.add(
      Moment(
        handle: handle,
        addedAt: addedAt,
        addedByYou: outgoing || isOwnAccount(m.senderDeviceId),
        status: !outgoing
            ? MomentStatus.received
            : queued
            ? MomentStatus.saving
            : MomentStatus.saved,
        photos: List.unmodifiable(photos),
        photoCount: payload.photoMessageIds.length,
        problem: missing == 0
            ? MomentProblem.none
            : outgoing
            ? MomentProblem.photosMissing
            : MomentProblem.photosArriving,
        caption: payload.caption,
        memoryDate: payload.memoryDate,
      ),
    );
  }
  entries.sort((a, b) {
    final d = b.day.compareTo(a.day);
    if (d != 0) return d;
    final t = b.addedAt.compareTo(a.addedAt);
    return t != 0 ? t : b.handle.value.compareTo(a.handle.value);
  });
  return entries;
}

/// The message IDs that belong to the moments protocol (D-114): every
/// kind-3 manifest — readable or not — and every photo a shown moment
/// claims. A chat view of the same conversation MUST leave these out, so
/// memories never appear as stray chat photos or "unsupported message"
/// rows. Photos no moment claims (e.g. orphans, E66) are not included.
Set<String> momentProtocolMessageIds(
  List<LocalMessage> history, {
  required bool Function(DeviceId device) isOwnAccount,
}) => {
  for (final m in history)
    if (MomentPayload.isMoment(m.payload)) _hex(m.messageId),
  for (final e in assembleMoments(history, isOwnAccount: isOwnAccount))
    if (e is Moment) ...e.photos.map((p) => p.value),
};

MediaRefView? _mediaOf(LocalMessage m) {
  if (!MediaRefView.isMedia(m.payload)) return null;
  try {
    return MediaRefView.decode(m.payload);
  } on CryptoException {
    return null;
  }
}

int _timeOf(LocalMessage m) =>
    m.serverTimeMs != 0 ? m.serverTimeMs : m.createdAtMs;

int _compareTime(LocalMessage a, LocalMessage b) {
  final t = _timeOf(a).compareTo(_timeOf(b));
  return t != 0 ? t : _hex(a.messageId).compareTo(_hex(b.messageId));
}

String _hex(MessageId id) => EncryptedMessageEnvelope.hexOf(id.bytes);
