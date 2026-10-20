import 'dart:async';
import 'dart:typed_data';

import 'package:sirf_hum/core/logging/app_logger.dart';
import 'package:sirf_hum/core/logging/log_value.dart';
import 'package:sirf_hum/security/device/device_registration.dart';
import 'package:sirf_hum/security/media/media_storage.dart';
import 'package:sirf_hum/security/messaging/conversation_transport.dart';
import 'package:sirf_hum/security/messaging/messaging_service.dart';
import 'package:sirf_hum/security/moments/moment.dart';
import 'package:sirf_hum/security/moments/moment_payload.dart';
import 'package:sirf_hum_crypto/sirf_hum_crypto.dart';

/// Why a moments operation stopped. Categories only: never captions, paths
/// or identifiers.
enum MomentFailure {
  /// No private media here (web, D-046) or no media support wired.
  unsupported,
  noPhotos,
  tooManyPhotos,

  /// Over the 64 MiB media limit (D-093).
  photoTooLarge,

  /// Missing, empty, or changed while it was being encrypted.
  photoUnreadable,
  captionTooLong,

  /// Not a real day, or a day that has not happened yet.
  invalidDate,

  /// This phone is not an active, trusted device (revoked, pending, …) or
  /// was removed from the couple's conversation.
  deviceNotTrusted,

  /// This account is not (any more) in the couple's conversation.
  notPaired,

  /// The phones are not connected yet (no shared group, a commit to
  /// resolve, or a device to remove first). Retry later.
  notReady,
  outboxFull,

  /// The server refused (not as a stale epoch).
  rejected,

  /// Offline or interrupted, or a photo that is not on this phone yet.
  unavailable,

  /// A photo failed its integrity check even after a fresh download.
  corrupted,

  /// Not a photo of a moment on this phone.
  notFound,
}

class MomentException implements Exception {
  const MomentException(this.failure);

  final MomentFailure failure;

  @override
  String toString() => 'MomentException(${failure.name})';
}

/// One chosen photo: a file the picker owns, read only inside the core.
class MomentInput {
  const MomentInput({required this.path, required this.sizeBytes});

  final String path;
  final int sizeBytes;

  @override
  String toString() => 'MomentInput(<redacted>)';
}

/// What the person chose to keep. [caption] and [memoryDate] are private.
class MomentDraft {
  const MomentDraft({required this.photos, this.caption, this.memoryDate});

  final List<MomentInput> photos;
  final String? caption;
  final MomentDate? memoryDate;

  @override
  String toString() => 'MomentDraft(${photos.length} photos, <redacted>)';
}

enum MomentSaveOutcome {
  /// Everything is on the server.
  saved,

  /// Sealed on this phone; it finishes uploading by itself (offline,
  /// interrupted, or the server could not take it right now).
  savedOnPhone,
}

/// What the Moments area needs (D-115). It takes no account, couple,
/// conversation or device identifier: an implementation is built for one
/// account's couple conversation, which comes from the server. Handles are
/// issued by the implementation and only refer back to it. Failures are
/// [MomentException]s.
abstract interface class MomentsBackend {
  int get maxPhotos;

  /// The timeline from this phone, newest first. No network.
  List<MomentEntry> moments();

  Future<void> refresh();

  Future<void> retryPending();

  Future<MomentSaveOutcome> create(MomentDraft draft);

  /// Private plaintext for display only.
  Future<Uint8List> openPhoto(MomentPhoto photo);
}

/// Moments for one couple on one device (Prompt 15, D-113–D-116): the
/// couple's existing MLS conversation (D-104) carries each moment as its
/// photos (kind-2 media references, keys only in the core, D-094) followed
/// by a kind-3 manifest with the caption and date (D-114).
///
/// It adds no server state, no rules and no cryptography: authorization,
/// device trust and confidentiality are the messaging service's (D-085,
/// D-089, D-095, D-096). In particular:
/// - the conversation (and so the couple) comes from the server's pairing
///   answer, never from the client, and every step checks membership;
/// - every write and every download requires this device to be active;
/// - nothing leaves the device until the whole moment is sealed;
/// - plaintext exists only in the caller's files (read inside the core),
///   in [moments]' captions and in [openPhoto]'s result — never on disk,
///   never in logs.
///
/// Operations that change local state run one at a time.
class MomentsService implements MomentsBackend {
  MomentsService({required this.messaging, DateTime Function()? now})
    : _now = now ?? DateTime.now;

  final MessagingService messaging;
  final DateTime Function() _now;

  Future<void> _openTail = Future.value();

  @override
  int get maxPhotos => MomentPayload.maxPhotos;

  /// The timeline from local history, newest first. No network.
  @override
  List<MomentEntry> moments() => assembleMoments(
    messaging.core.history(messaging.conversation),
    isOwnAccount: _isOwnAccount,
  );

  /// Confirms this device is still trusted (lineage, D-085), fetches what
  /// arrived and finishes queued saves. A device that is no longer active
  /// stops here: it fetches nothing new (D-096).
  @override
  Future<void> refresh() => _serial(() async {
    try {
      await messaging.refreshTrust();
      final report = await messaging.sync();
      if (report.removed) {
        throw const MomentException(MomentFailure.deviceNotTrusted);
      }
      await messaging.flushOutbox();
      _log('moments_refreshed', 'ok', {'received': report.received});
    } on Exception catch (e) {
      final failure = _failureOf(e);
      _log('moments_refreshed', failure.name);
      throw MomentException(failure);
    }
  });

  /// Finishes queued saves without fetching anything.
  @override
  Future<void> retryPending() => _serial(() async {
    try {
      await messaging.flushOutbox();
    } on Exception catch (e) {
      throw MomentException(_failureOf(e));
    }
  });

  /// Seals the photos and then the manifest in the outbox, then uploads
  /// them in that order (objects before references, D-095). If any step
  /// before the manifest is sealed fails, everything already sealed is
  /// discarded, so a failed save leaves nothing behind and nothing was
  /// sent. Once sealed, the moment exists: a later upload failure only
  /// delays it ([MomentSaveOutcome.savedOnPhone]), and retrying never
  /// creates it twice — unless the server refuses it for good (this account
  /// left the couple, this device lost trust): then whatever it has not
  /// taken is discarded and the failure is reported, never "saved".
  @override
  Future<MomentSaveOutcome> create(MomentDraft draft) => _serial(() async {
    final count = draft.photos.length;
    _log('moment_upload_started', 'ok', {'photos': count});
    final ids = <String>[];
    try {
      _validate(draft);
      _requireRoom(count + 1);
      for (final photo in draft.photos) {
        ids.add(
          await messaging.queueMedia(
            inputPath: photo.path,
            mediaClass: MediaClass.image,
          ),
        );
      }
      final payload = MomentPayload(
        photoMessageIds: ids,
        clientTimeMs: _now().millisecondsSinceEpoch,
        caption: draft.caption,
        memoryDate: draft.memoryDate,
      ).encode();
      try {
        ids.add(await messaging.queuePayload(payload));
      } finally {
        wipeBytes(payload);
      }
    } on Exception catch (e) {
      for (final id in ids) {
        _discard(id);
      }
      final failure = _failureOf(e);
      _log('moment_upload_failed', failure.name);
      throw MomentException(failure);
    }

    var outcome = MomentSaveOutcome.savedOnPhone;
    try {
      await messaging.flushOutbox();
      final manifest = ids.last;
      final sent = messaging.core
          .history(messaging.conversation)
          .any((m) => _hex(m.messageId) == manifest && m.state.isSent);
      if (sent) outcome = MomentSaveOutcome.saved;
    } on MessagingException catch (e) {
      final permanent = switch (e.failure) {
        MessagingFailure.notMember ||
        MessagingFailure.deviceNotTrusted ||
        MessagingFailure.removed => true,
        _ => false,
      };
      if (permanent) {
        // It could never be delivered: "saved on this phone" would be
        // untrue. Drop what the server has not taken and say so.
        for (final id in ids) {
          _discard(id);
        }
        final failure = _failureOf(e);
        _log('moment_upload_failed', failure.name);
        throw MomentException(failure);
      }
      _log('moment_upload_deferred', e.failure.name);
    } on MediaException catch (e) {
      _log('moment_upload_deferred', e.failure.name);
    } on DeviceRegistryException catch (e) {
      // Device status could not be confirmed (offline): the moment is
      // sealed and finishes on the next refresh. Reporting a failure here
      // would invite a second, duplicate moment.
      _log('moment_upload_deferred', e.failure.name);
    } on TransportException catch (e) {
      _log('moment_upload_deferred', e.failure.name);
    }
    _log('moment_upload_completed', outcome.name, {'photos': count});
    return outcome;
  });

  /// Decrypts one photo for display (from the ciphertext cache, or after a
  /// size-checked download that requires an active device, D-096). Only
  /// photos of a moment this phone can show open here. The result is
  /// private: render it, never store it; wipe it when done. One at a time,
  /// which also bounds plaintext in memory.
  @override
  Future<Uint8List> openPhoto(MomentPhoto photo) {
    final result = _openTail.then((_) async {
      final known = moments().whereType<Moment>().any(
        (m) => m.photos.contains(photo),
      );
      if (!known) throw const MomentException(MomentFailure.notFound);
      try {
        return await messaging.openMedia(photo.value);
      } on Exception catch (e) {
        final failure = _failureOf(e);
        _log('moment_photo_opened', failure.name);
        throw MomentException(failure);
      }
    });
    _openTail = result.then<void>((_) {}, onError: (Object _) {});
    return result;
  }

  void _validate(MomentDraft draft) {
    final photos = draft.photos;
    if (photos.isEmpty) throw const MomentException(MomentFailure.noPhotos);
    if (photos.length > MomentPayload.maxPhotos) {
      throw const MomentException(MomentFailure.tooManyPhotos);
    }
    for (final p in photos) {
      if (p.sizeBytes <= 0) {
        throw const MomentException(MomentFailure.photoUnreadable);
      }
      if (p.sizeBytes > MediaLimits.maxPlaintextBytes) {
        throw const MomentException(MomentFailure.photoTooLarge);
      }
    }
    final date = draft.memoryDate;
    if (date != null && date.compareTo(MomentDate.of(_now())) > 0) {
      throw const MomentException(MomentFailure.invalidDate);
    }
    // The caption limit is checked by building a throwaway payload.
    MomentPayload(
      photoMessageIds: [for (var i = 0; i < photos.length; i++) _probeId(i)],
      clientTimeMs: 0,
      caption: draft.caption,
    );
  }

  /// Room for the whole moment, so it is never sealed half-way because the
  /// outbox filled up.
  void _requireRoom(int needed) {
    final queued = messaging.core
        .history(messaging.conversation)
        .where((m) => m.state == MessageState.queued)
        .length;
    if (queued + needed > MessagingService.maxOutbox) {
      throw const MomentException(MomentFailure.outboxFull);
    }
  }

  void _discard(String id) {
    try {
      messaging.discardQueued(id);
    } on Object {
      // Best effort; a queued photo without its manifest is never shown
      // as a moment (D-114) and is reported by the failure already thrown.
    }
  }

  bool _isOwnAccount(DeviceId device) {
    try {
      return messaging.core.deviceAccount(device) == messaging.account.value;
    } on CryptoException {
      return false;
    }
  }

  // Shared with every feature on this conversation (D-118), not per
  // service: the notebook must not sync while a moment is being sealed.
  Future<T> _serial<T>(Future<T> Function() action) =>
      messaging.exclusive(action);

  static String _probeId(int i) => i.toRadixString(16).padLeft(32, '0');

  static String _hex(MessageId id) =>
      [for (final b in id.bytes) b.toRadixString(16).padLeft(2, '0')].join();

  static MomentFailure _failureOf(Exception e) => switch (e) {
    MomentException(:final failure) => failure,
    MomentPayloadException(:final failure) => switch (failure) {
      MomentPayloadFailure.noPhotos => MomentFailure.noPhotos,
      MomentPayloadFailure.tooManyPhotos => MomentFailure.tooManyPhotos,
      MomentPayloadFailure.captionTooLong => MomentFailure.captionTooLong,
      MomentPayloadFailure.invalidDate => MomentFailure.invalidDate,
      _ => MomentFailure.rejected,
    },
    MediaException(:final failure) => switch (failure) {
      MediaFailure.unsupported => MomentFailure.unsupported,
      MediaFailure.invalidInput => MomentFailure.photoUnreadable,
      MediaFailure.tooLarge => MomentFailure.photoTooLarge,
      MediaFailure.notMedia => MomentFailure.notFound,
      MediaFailure.unavailable => MomentFailure.unavailable,
      MediaFailure.corrupted => MomentFailure.corrupted,
      MediaFailure.objectLost => MomentFailure.rejected,
    },
    MessagingException(:final failure) => switch (failure) {
      MessagingFailure.deviceNotTrusted ||
      MessagingFailure.removed => MomentFailure.deviceNotTrusted,
      MessagingFailure.notMember => MomentFailure.notPaired,
      MessagingFailure.notJoined ||
      MessagingFailure.commitPending ||
      MessagingFailure.untrustedMember ||
      MessagingFailure.stateDiverged => MomentFailure.notReady,
      MessagingFailure.outboxFull => MomentFailure.outboxFull,
      MessagingFailure.rejected => MomentFailure.rejected,
    },
    TransportException() => MomentFailure.unavailable,
    // The device registry could not answer (offline) or refused. Never
    // treated as trusted; only categorized.
    DeviceRegistryException(:final failure) =>
      failure == DeviceRegistryFailure.unavailable
          ? MomentFailure.unavailable
          : MomentFailure.rejected,
    // Local state failures (corruption, persistence) must surface as
    // themselves: they are never a "bad moment".
    _ => throw e,
  };

  static void _log(
    String event,
    String outcome, [
    Map<String, Object?> extra = const {},
  ]) => AppLogger.info(
    event,
    fields: {'outcome': SafeLogString(outcome), ...extra},
  );
}

extension on MessageState {
  bool get isSent => this == MessageState.sent;
}
