import 'dart:async';

import 'package:sirf_hum/core/logging/app_logger.dart';
import 'package:sirf_hum/core/logging/log_value.dart';
import 'package:sirf_hum/security/device/device_registration.dart';
import 'package:sirf_hum/security/media/media_storage.dart';
import 'package:sirf_hum/security/messaging/conversation_transport.dart';
import 'package:sirf_hum/security/messaging/messaging_service.dart';
import 'package:sirf_hum/security/moments/moment_payload.dart';
import 'package:sirf_hum/security/notebook/notebook.dart';
import 'package:sirf_hum/security/notebook/notebook_payload.dart';
import 'package:sirf_hum_crypto/sirf_hum_crypto.dart';

/// Why a notebook operation stopped. Categories only: never text, dates or
/// identifiers.
enum NotebookFailure {
  /// No private content here (web, D-046) or no backend wired.
  unsupported,
  missingTitle,
  titleTooLong,
  noteTooLong,
  detailTooLong,

  /// Control characters in a one-line field.
  invalidText,
  invalidCategory,

  /// Not a real day, or (for your story and "together since") a day that
  /// has not happened yet.
  invalidDate,

  /// This part of the notebook is full (D-120).
  limitReached,

  /// The record is not in the notebook on this phone (removed meanwhile).
  notFound,

  /// This phone is not an active, trusted device (revoked, pending, …) or
  /// was removed from the couple's conversation.
  deviceNotTrusted,

  /// This account is not (any more) in the couple's conversation.
  notPaired,

  /// The phones are not connected yet. Retry later.
  notReady,
  outboxFull,

  /// The server refused (not as a stale epoch).
  rejected,

  /// Offline or interrupted.
  unavailable,
}

class NotebookException implements Exception {
  const NotebookException(this.failure);

  final NotebookFailure failure;

  @override
  String toString() => 'NotebookException(${failure.name})';
}

enum NotebookSaveOutcome {
  /// The change is on the server.
  saved,

  /// Sealed on this phone; it finishes uploading by itself.
  savedOnPhone,
}

/// What Future and Us need (D-121). Like `MomentsBackend` it takes no
/// account, couple, conversation or device identifier: an implementation is
/// built for one account's couple conversation, which comes from the
/// server. Handles are issued by the implementation and only refer back to
/// it. Failures are [NotebookException]s.
abstract interface class NotebookBackend {
  /// The notebook from this phone. No network.
  NotebookSnapshot notebook();

  Future<void> refresh();

  Future<void> retryPending();

  Future<NotebookSaveOutcome> create(NotebookFields fields);

  /// Replaces every field of [handle]'s record. The section cannot change.
  Future<NotebookSaveOutcome> update(
    NotebookHandle handle,
    NotebookFields fields,
  );

  /// Removes [handle]'s record for both of you. This is a change in the
  /// shared notebook, not erasure (D-119).
  Future<NotebookSaveOutcome> remove(NotebookHandle handle);
}

/// The couple's notebook — Future's plans and Us's story, little things,
/// rituals and "together since" — for one couple on one device (Prompt 16,
/// D-118–D-121). Each change is one kind-4 MLS application message in the
/// couple's existing conversation (D-104), exactly as a moment's manifest
/// is (D-113).
///
/// It adds no server state, rules or cryptography: authorization, device
/// trust and confidentiality are the messaging service's (D-085, D-089,
/// D-095). In particular:
/// - the conversation (and so the couple) comes from the server's pairing
///   answer, never from the client, and every step checks membership;
/// - every write requires this device to be active, and a refresh first
///   re-checks trust;
/// - plaintext exists only in the caller's fields and in [notebook]'s
///   entries — never on disk outside the sealed core, never in logs.
///
/// State-changing operations share the conversation's lock with every other
/// feature on it ([MessagingService.exclusive]).
class NotebookService implements NotebookBackend {
  NotebookService({required this.messaging, DateTime Function()? now})
    : _now = now ?? DateTime.now;

  final MessagingService messaging;
  final DateTime Function() _now;

  /// Live records per section (D-120): a notebook, not a database.
  static const Map<NotebookSection, int> limits = {
    NotebookSection.future: 200,
    NotebookSection.story: 12,
    NotebookSection.littleThing: 30,
    NotebookSection.ritual: 12,
    NotebookSection.togetherSince: 1,
  };

  @override
  NotebookSnapshot notebook() => assembleNotebook(
    messaging.core.history(messaging.conversation),
    isOwnAccount: _isOwnAccount,
  );

  /// Confirms this device is still trusted (lineage, D-085), fetches what
  /// arrived and finishes queued changes. A device that is no longer active
  /// stops here and fetches nothing new.
  @override
  Future<void> refresh() => messaging.exclusive(() async {
    try {
      await messaging.refreshTrust();
      final report = await messaging.sync();
      if (report.removed) {
        throw const NotebookException(NotebookFailure.deviceNotTrusted);
      }
      await messaging.flushOutbox();
      _log('notebook_refreshed', 'ok', {'received': report.received});
    } on Exception catch (e) {
      final failure = _failureOf(e);
      _log('notebook_refreshed', failure.name);
      throw NotebookException(failure);
    }
  });

  @override
  Future<void> retryPending() => messaging.exclusive(() async {
    try {
      await messaging.flushOutbox();
    } on Exception catch (e) {
      throw NotebookException(_failureOf(e));
    }
  });

  @override
  Future<NotebookSaveOutcome> create(NotebookFields fields) =>
      _write(NotebookOp.create, fields.section, () {
        _validateDate(fields);
        final live = notebook().section(fields.section).length;
        if (live >= limits[fields.section]!) {
          throw const NotebookException(NotebookFailure.limitReached);
        }
        return NotebookPayload.create(
          fields: fields,
          clientTimeMs: _now().millisecondsSinceEpoch,
        );
      });

  @override
  Future<NotebookSaveOutcome> update(
    NotebookHandle handle,
    NotebookFields fields,
  ) => _write(NotebookOp.update, fields.section, () {
    _validateDate(fields);
    _requireLive(handle, fields.section);
    return NotebookPayload.update(
      target: handle.value,
      fields: fields,
      clientTimeMs: _now().millisecondsSinceEpoch,
    );
  });

  @override
  Future<NotebookSaveOutcome> remove(NotebookHandle handle) {
    final section = _sectionOf(handle);
    if (section == null) {
      return Future.error(const NotebookException(NotebookFailure.notFound));
    }
    return _write(NotebookOp.remove, section, () {
      _requireLive(handle, section);
      return NotebookPayload.remove(
        target: handle.value,
        section: section,
        clientTimeMs: _now().millisecondsSinceEpoch,
      );
    });
  }

  /// Seals one change in the outbox, then uploads it. Validation (and the
  /// record and limit checks, which read the notebook) happen under the
  /// lock, so two writes never decide on the same stale notebook. Once
  /// sealed the change exists: a later transient failure only delays it
  /// ([NotebookSaveOutcome.savedOnPhone]) and retrying never sends it twice.
  /// A permanent refusal (this account left the couple, this device lost
  /// trust) discards it if the server has not taken it, and is reported.
  Future<NotebookSaveOutcome> _write(
    NotebookOp op,
    NotebookSection section,
    NotebookPayload Function() build,
  ) => messaging.exclusive(() async {
    final kind = {
      'op': SafeLogString(op.name),
      'section': SafeLogString(section.name),
    };
    _log('notebook_write_started', 'ok', kind);
    final String id;
    try {
      final payload = build().encode();
      _requireRoom();
      try {
        id = await messaging.queuePayload(payload);
      } finally {
        wipeBytes(payload);
      }
    } on Exception catch (e) {
      final failure = _failureOf(e);
      _log('notebook_write_failed', failure.name, kind);
      throw NotebookException(failure);
    }

    var outcome = NotebookSaveOutcome.savedOnPhone;
    try {
      await messaging.flushOutbox();
      final sent = messaging.core
          .history(messaging.conversation)
          .any((m) => _hex(m.messageId) == id && m.state == MessageState.sent);
      if (sent) outcome = NotebookSaveOutcome.saved;
    } on MessagingException catch (e) {
      final permanent = switch (e.failure) {
        MessagingFailure.notMember ||
        MessagingFailure.deviceNotTrusted ||
        MessagingFailure.removed => true,
        _ => false,
      };
      if (permanent) {
        // It could never be delivered: "saved on this phone" would be
        // untrue. Drop it if the server has not taken it, and say so.
        _discard(id);
        final failure = _failureOf(e);
        _log('notebook_write_failed', failure.name, kind);
        throw NotebookException(failure);
      }
      _log('notebook_write_deferred', e.failure.name, kind);
    } on MediaException catch (e) {
      // A moment's photo queued before this change could not upload yet
      // (the outbox keeps creation order): this change waits behind it.
      _log('notebook_write_deferred', e.failure.name, kind);
    } on DeviceRegistryException catch (e) {
      // Device status could not be confirmed (offline) after sealing: it
      // finishes on the next refresh. A failure here would invite a
      // duplicate.
      _log('notebook_write_deferred', e.failure.name, kind);
    } on TransportException catch (e) {
      _log('notebook_write_deferred', e.failure.name, kind);
    }
    _log('notebook_write_completed', outcome.name, kind);
    return outcome;
  });

  /// Your story and "together since" happened already; a plan's date may be
  /// any real day (a past one is never "missed", D-120).
  void _validateDate(NotebookFields fields) {
    final date = fields.date;
    if (date == null) return;
    final past = switch (fields.section) {
      NotebookSection.story || NotebookSection.togetherSince => true,
      _ => false,
    };
    if (past && date.compareTo(MomentDate.of(_now())) > 0) {
      throw const NotebookException(NotebookFailure.invalidDate);
    }
  }

  void _requireLive(NotebookHandle handle, NotebookSection section) {
    final live = notebook().entries.any(
      (e) => e.handle == handle && e.section == section,
    );
    if (!live) throw const NotebookException(NotebookFailure.notFound);
  }

  NotebookSection? _sectionOf(NotebookHandle handle) {
    for (final e in notebook().entries) {
      if (e.handle == handle) return e.section;
    }
    return null;
  }

  void _requireRoom() {
    final queued = messaging.core
        .history(messaging.conversation)
        .where((m) => m.state == MessageState.queued)
        .length;
    if (queued + 1 > MessagingService.maxOutbox) {
      throw const NotebookException(NotebookFailure.outboxFull);
    }
  }

  void _discard(String id) {
    try {
      messaging.discardQueued(id);
    } on Object {
      // Best effort; the failure is reported already.
    }
  }

  bool _isOwnAccount(DeviceId device) {
    try {
      return messaging.core.deviceAccount(device) == messaging.account.value;
    } on CryptoException {
      return false;
    }
  }

  static String _hex(MessageId id) =>
      [for (final b in id.bytes) b.toRadixString(16).padLeft(2, '0')].join();

  static NotebookFailure _failureOf(Exception e) => switch (e) {
    NotebookException(:final failure) => failure,
    NotebookPayloadException(:final failure) => switch (failure) {
      NotebookPayloadFailure.missingTitle => NotebookFailure.missingTitle,
      NotebookPayloadFailure.titleTooLong => NotebookFailure.titleTooLong,
      NotebookPayloadFailure.noteTooLong => NotebookFailure.noteTooLong,
      NotebookPayloadFailure.detailTooLong => NotebookFailure.detailTooLong,
      NotebookPayloadFailure.invalidText => NotebookFailure.invalidText,
      NotebookPayloadFailure.invalidCategory ||
      NotebookPayloadFailure.invalidStatus => NotebookFailure.invalidCategory,
      NotebookPayloadFailure.invalidDate => NotebookFailure.invalidDate,
      _ => NotebookFailure.rejected,
    },
    MessagingException(:final failure) => switch (failure) {
      MessagingFailure.deviceNotTrusted ||
      MessagingFailure.removed => NotebookFailure.deviceNotTrusted,
      MessagingFailure.notMember => NotebookFailure.notPaired,
      MessagingFailure.notJoined ||
      MessagingFailure.commitPending ||
      MessagingFailure.untrustedMember ||
      MessagingFailure.stateDiverged => NotebookFailure.notReady,
      MessagingFailure.outboxFull => NotebookFailure.outboxFull,
      MessagingFailure.rejected => NotebookFailure.rejected,
    },
    TransportException() => NotebookFailure.unavailable,
    // A moment's photo ahead in the shared outbox could not upload yet.
    MediaException() => NotebookFailure.unavailable,
    // Never treated as trusted; only categorized.
    DeviceRegistryException(:final failure) =>
      failure == DeviceRegistryFailure.unavailable
          ? NotebookFailure.unavailable
          : NotebookFailure.rejected,
    // Local state failures (corruption, persistence) surface as themselves.
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
