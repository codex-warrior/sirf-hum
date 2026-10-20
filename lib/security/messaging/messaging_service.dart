import 'dart:typed_data';

import 'package:sirf_hum/core/logging/app_logger.dart';
import 'package:sirf_hum/core/logging/log_value.dart';
import 'package:sirf_hum/security/device/device_registration.dart';
import 'package:sirf_hum/security/device/device_status.dart';
import 'package:sirf_hum/security/media/media_storage.dart';
import 'package:sirf_hum/security/messaging/conversation_transport.dart';
import 'package:sirf_hum/security/messaging/message_envelope.dart';
import 'package:sirf_hum/security/messaging/text_payload.dart';
import 'package:sirf_hum_crypto/sirf_hum_crypto.dart';

/// Why a messaging operation stopped. Categories only.
enum MessagingFailure {
  /// This device is not `active` on the server (revoked, pending, …).
  deviceNotTrusted,

  /// The account is not a member, or the conversation is closed.
  notMember,

  /// No MLS group on this device yet (waiting for a Welcome).
  notJoined,

  /// This device was removed from the conversation's MLS group.
  removed,

  /// Too many messages waiting to upload.
  outboxFull,

  /// The server refused a write for a reason other than a stale epoch.
  rejected,

  /// Local MLS state cannot follow the server's accepted commits. Never
  /// reset silently: the device needs to be re-added (deferred).
  stateDiverged,

  /// A staged commit must be resolved first ([MessagingService.sync]).
  commitPending,

  /// The roster holds a device this device no longer trusts:
  /// [MessagingService.reconcileMembership] removes it first.
  untrustedMember,
}

class MessagingException implements Exception {
  const MessagingException(this.failure);

  final MessagingFailure failure;

  @override
  String toString() => 'MessagingException(${failure.name})';
}

enum SendOutcome {
  /// Accepted by the server.
  sent,

  /// Encrypted and sealed locally; uploads on [MessagingService.flushOutbox].
  queued,
}

/// One message as the (future) UI sees it. [text] is private content.
class ChatMessage {
  const ChatMessage({
    required this.messageIdHex,
    required this.outgoing,
    required this.senderDeviceIdHex,
    required this.state,
    required this.sortTimeMs,
    required this.text,
    this.media,
  });

  final String messageIdHex;
  final bool outgoing;
  final String senderDeviceIdHex;
  final MessageState state;

  /// Server time when known, else this device's time (D-091).
  final int sortTimeMs;

  /// Null when the payload is a kind or version this build cannot show
  /// ("Update Sirf Hum to see this"), or for media. Never invented text.
  final String? text;

  /// For a media message: its key-free reference (D-094). Open it with
  /// [MessagingService.openMedia].
  final MediaRefView? media;

  @override
  String toString() => 'ChatMessage(${state.name}, <redacted>)';
}

/// What one [MessagingService.sync] did. Counts and categories only.
class SyncReport {
  SyncReport._();

  bool joined = false;
  bool removed = false;
  int epoch = 0;
  int received = 0;
  int duplicates = 0;

  /// Messages that could not be opened, by category (e.g. `stale_epoch`,
  /// `envelope_mismatch`, `unauthorized_device`, `malformed`). Shown as
  /// "a message couldn't be opened", never as content.
  final Map<String, int> failures = {};

  void _fail(String category) =>
      failures.update(category, (n) => n + 1, ifAbsent: () => 1);

  @override
  String toString() =>
      'SyncReport(epoch: $epoch, received: $received, failures: $failures)';
}

/// Text messaging for one conversation on one device (Prompt 10,
/// docs/security/E2EE-MESSAGING-DESIGN.md). No UI: a future chat screen and
/// the test harness call this.
///
/// - **Trust:** device trust comes from verified lineage
///   ([refreshTrust], D-085), never from the server's word.
/// - **Order:** per epoch, every message of epoch L before commit L
///   ([sync], D-091).
/// - **Commits:** staged, submitted, then confirmed or discarded by what the
///   server accepted (first commit wins, D-087, D-088).
/// - **Offline:** messages are encrypted at once and sealed in the core's
///   history; [flushOutbox] uploads them, re-encrypting the same message ID
///   after a stale-epoch refusal.
///
/// Plaintext exists in Dart only in [sendText]'s argument, in [messages]'
/// results and in [openMedia]'s result (D-090, D-096: never written by
/// Dart, never logged). Media plaintext never touches disk: [sendMedia]
/// reads the caller's file inside the core, and the cache holds ciphertext.
class MessagingService {
  MessagingService({
    required this.core,
    required this.account,
    required this.conversation,
    required ConversationTransport transport,
    required DeviceRegistry registry,
    MediaSupport? media,
    int Function()? clock,
  }) : _transport = transport,
       _registry = registry,
       _media = media,
       _clock = clock ?? (() => DateTime.now().millisecondsSinceEpoch);

  /// Outgoing messages allowed to wait for upload.
  static const int maxOutbox = 100;

  /// Upload attempts for one message across stale-epoch refusals.
  static const int maxUploadAttempts = 3;

  /// Epochs processed by one [sync] (a bound, not a protocol limit).
  static const int maxEpochsPerSync = 1000;

  final CryptoCore core;
  final AccountId account;
  final ConversationId conversation;
  final ConversationTransport _transport;
  final DeviceRegistry _registry;
  final MediaSupport? _media;
  final int Function() _clock;

  Future<void> _exclusiveTail = Future.value();

  GroupId get _group => GroupId(conversation.bytes);

  DeviceId get _ownId => core.publicIdentity().deviceId;

  /// Runs [action] after every earlier exclusive action on this service has
  /// finished. Features that share the conversation (Moments, the couple's
  /// notebook, D-118) run their state-changing operations — trust refresh,
  /// sync, sealing, flushing — through here, so two features never
  /// interleave a sync with a seal or with another sync. Not re-entrant:
  /// [action] must not call [exclusive] again.
  Future<T> exclusive<T>(Future<T> Function() action) {
    final result = _exclusiveTail.then((_) => action());
    _exclusiveTail = result.then<void>((_) {}, onError: (Object _) {});
    return result;
  }

  String get _ownHex => EncryptedMessageEnvelope.hexOf(_ownId.bytes);

  // ------------------------------------------------------------------ trust

  /// Confirms this device is active and applies every member account's
  /// verified lineage to the core's trust (D-085). Each account's root
  /// person key must already be anchored (`trustVerifiedPersonKey`, after
  /// out-of-band verification); an account whose lineage cannot be applied
  /// keeps its previous trust and is reported, never trusted more.
  Future<List<String>> refreshTrust() async {
    core.checkAccount(account);
    final conv = await _conversation();
    await _requireActive();
    final failed = <String>[];
    for (final member in conv.members) {
      final memberAccount = AccountId(member);
      final lineage = await _registry.lineage(memberAccount);
      if (lineage == null) continue;
      final state = await _registry.trustState(memberAccount);
      try {
        if (member == account.value) core.observeTrustEpoch(state.trustEpoch);
        core.trustLineage(lineage, state.trustEpoch);
      } on CryptoException catch (e) {
        if (_isLocalStateFailure(e)) rethrow;
        failed.add(e.code.name);
      }
    }
    _log('messaging_trust_refreshed', failed.isEmpty ? 'ok' : 'partial');
    return failed;
  }

  /// Publishes a fresh KeyPackage so a member device can add this one.
  Future<void> publishKeyPackage() async {
    await _conversation();
    await _requireActive();
    await _transport.publishKeyPackage(
      conversation,
      PublishedKeyPackage(
        accountId: account.value,
        deviceIdHex: _ownHex,
        keyPackage: core.keyPackage(),
      ),
    );
    _log('messaging_key_package_published', 'ok');
  }

  // ------------------------------------------------------------------- sync

  /// Joins or creates the group if needed, then processes epochs in order.
  Future<SyncReport> sync() async {
    final report = SyncReport._();
    var conv = await _conversation();
    if (!_hasGroup) await _joinOrCreate(conv, report);
    if (_hasGroup) await _catchUp(report);
    if (!_hasGroup && !report.removed) {
      // Lost the race to create the group: join the winner's.
      conv = await _conversation();
      await _joinOrCreate(conv, report, create: false);
      if (_hasGroup) await _catchUp(report);
    }
    report.epoch = _hasGroup ? core.epoch(_group) : 0;
    _log(
      'messaging_synced',
      report.removed
          ? 'removed'
          : _hasGroup
          ? 'joined'
          : 'waiting',
      {'received': report.received, 'failed': report.failures.length},
    );
    return report;
  }

  Future<void> _joinOrCreate(
    ConversationRecord conv,
    SyncReport report, {
    bool create = true,
  }) async {
    final welcomes = await _transport.welcomesFor(conversation, _ownHex)
      ..sort((a, b) => b.epoch.compareTo(a.epoch));
    for (final w in welcomes) {
      try {
        core.joinConversation(conversation, w.welcome);
        report.joined = true;
        return;
      } on CryptoException catch (e) {
        if (_isLocalStateFailure(e)) rethrow;
        report._fail('welcome_${e.code.name}');
      }
    }
    if (create && conv.epoch == 0) await _createGroup(conv);
  }

  /// First device to win `commits/0` creates the group (D-086, D-088).
  Future<void> _createGroup(ConversationRecord conv) async {
    final candidates = await _trustedKeyPackages(conv, inRoster: const {});
    final partner = candidates.any((k) => k.accountId != account.value);
    if (!partner) return; // the partner has no trusted device yet
    final staged = core.createConversationGroup(conversation, [
      for (final k in candidates) k.keyPackage,
    ]);
    await _submit(staged, [for (final k in candidates) k.deviceIdHex]);
  }

  Future<void> _catchUp(SyncReport report) async {
    for (var i = 0; i < maxEpochsPerSync && _hasGroup; i++) {
      final epoch = core.epoch(_group);
      final staged = core.stagedCommitEpoch(conversation);
      // Read the commit FIRST: if it exists, every epoch-L message already
      // exists too (rules accept messages only at the current epoch).
      final commit = await _transport.commit(conversation, epoch);
      if (epoch > 0) await _receiveEpoch(epoch, report);
      if (commit == null) {
        // Ours was never accepted (commits are written in transactions,
        // which never land later): drop it.
        if (staged == epoch) core.discardCommit(conversation, epoch);
        return;
      }
      final ours = commit.senderDeviceIdHex == _ownHex;
      if (staged == epoch && ours) {
        core.confirmCommit(conversation, epoch);
        continue;
      }
      if (staged == epoch) core.discardCommit(conversation, epoch);
      if (!_hasGroup) return; // our unconfirmed new group lost the race
      if (ours) {
        // Accepted from this device but no longer staged here (e.g. state
        // restored from an older copy): this device cannot follow.
        throw const MessagingException(MessagingFailure.stateDiverged);
      }
      final IncomingResult result;
      try {
        result = core.processCommit(
          conversation,
          epoch: epoch,
          sender: DeviceId(
            EncryptedMessageEnvelope.bytesOfHex(commit.senderDeviceIdHex),
          ),
          commit: commit.commit,
        );
      } on CryptoException catch (e) {
        if (_isLocalStateFailure(e)) rethrow;
        // A winning commit this device cannot validate: fail closed.
        _log('messaging_commit_rejected', e.code.name);
        throw const MessagingException(MessagingFailure.stateDiverged);
      }
      if (result is IncomingRemoved) {
        report.removed = true;
        return;
      }
    }
  }

  Future<void> _receiveEpoch(int epoch, SyncReport report) async {
    final batch = await _transport.messagesAtEpoch(conversation, epoch);
    for (var i = 0; i < batch.malformedCount; i++) {
      report._fail('malformed');
    }
    for (final env in batch.messages) {
      if (env.senderDeviceIdHex == _ownHex) {
        _confirmOwn(env);
        continue;
      }
      // The envelope's account must be the one the verified lineage
      // assigned to the sending device (D-089): the server cannot relabel.
      if (core.deviceAccount(env.senderDeviceId) != env.senderAccountId) {
        report._fail('unauthorized_device');
        continue;
      }
      try {
        final r = core.receiveMessage(
          conversation,
          messageId: env.messageId,
          sender: env.senderDeviceId,
          epoch: env.epoch,
          schemaVersion: env.schemaVersion,
          protocolVersion: env.protocolVersion,
          ciphertext: env.ciphertext,
          serverTimeMs: env.serverTimeMs ?? 0,
        );
        wipeBytes(r.payload);
        r.duplicate ? report.duplicates++ : report.received++;
      } on CryptoException catch (e) {
        if (_isLocalStateFailure(e)) rethrow;
        report._fail(e.code.name);
      }
    }
  }

  /// Our own message is on the server: mark it sent if still queued (the
  /// acknowledgement may have been lost).
  void _confirmOwn(EncryptedMessageEnvelope env) {
    try {
      core.markMessageSent(
        conversation,
        env.messageId,
        serverTimeMs: env.serverTimeMs ?? _clock(),
      );
    } on CryptoException catch (e) {
      if (_isLocalStateFailure(e)) rethrow;
      // Not in local history (e.g. deleted for me): nothing to do.
    }
  }

  // -------------------------------------------------------------- sending

  /// Encrypts [text] now (also offline) and uploads it. A refusal at a stale
  /// epoch syncs and re-encrypts the same message ID (D-091).
  Future<SendOutcome> sendText(String text) async {
    final payload = TextPayload(text: text, clientTimeMs: _clock()).encode();
    try {
      await _requireActive();
      _requireRoomToSend();
      final SentMessage sent;
      try {
        sent = core.sendMessage(conversation, payload);
      } on CryptoException catch (e) {
        throw _sendFailure(e);
      }
      final outcome = await _upload(sent);
      _log('message_sent', outcome.name);
      return outcome;
    } finally {
      wipeBytes(payload);
    }
  }

  /// Uploads queued messages in creation order; stops at the first one that
  /// cannot reach the server. Returns how many were sent.
  Future<int> flushOutbox() async {
    await _requireActive();
    if (!_hasGroup) return 0;
    final queued =
        core
            .history(conversation)
            .where((m) => m.state == MessageState.queued)
            .toList()
          ..sort(_outboxOrder);
    var sent = 0;
    for (final m in queued) {
      if (MediaRefView.isMedia(m.payload)) {
        // The object goes first: a reference must never reach the
        // recipients before its object (D-095).
        final view = MediaRefView.decode(m.payload);
        try {
          if (!await _ensureObjectUploaded(view)) break;
        } on MediaException catch (e) {
          if (e.failure != MediaFailure.objectLost) rethrow;
          // Undeliverable: drop it from the outbox ("couldn't be sent").
          core.deleteLocalMessage(conversation, m.messageId);
          _log('media_send_abandoned', 'object_lost');
          continue;
        }
      }
      final SentMessage current;
      try {
        current = m.epoch == core.epoch(_group)
            ? SentMessage(
                messageId: m.messageId,
                epoch: m.epoch,
                ciphertext: m.ciphertext!,
              )
            : core.reencryptMessage(conversation, m.messageId);
      } on CryptoException catch (e) {
        throw _sendFailure(e);
      }
      if (await _upload(current) == SendOutcome.queued) break;
      sent++;
    }
    _log('messaging_outbox_flushed', sent > 0 ? 'sent' : 'idle');
    return sent;
  }

  /// Creation order. Within one millisecond media goes first: a message
  /// that references media (a moment, D-113) is always created after it,
  /// and must never reach the server before it. Then by ID, so the order is
  /// total.
  static int _outboxOrder(LocalMessage a, LocalMessage b) {
    final t = a.createdAtMs.compareTo(b.createdAtMs);
    if (t != 0) return t;
    final media = (MediaRefView.isMedia(a.payload) ? 0 : 1).compareTo(
      MediaRefView.isMedia(b.payload) ? 0 : 1,
    );
    if (media != 0) return media;
    return EncryptedMessageEnvelope.hexOf(
      a.messageId.bytes,
    ).compareTo(EncryptedMessageEnvelope.hexOf(b.messageId.bytes));
  }

  /// Encrypts an application [payload] built by a feature (e.g. a moment,
  /// kind 3, D-114) and seals it in the outbox **without uploading it**:
  /// [flushOutbox] sends it after everything queued before it. The core
  /// refuses media references (kind 2), which only it builds (D-094).
  /// Returns the message ID. The caller wipes [payload].
  Future<String> queuePayload(Uint8List payload) async {
    await _requireActive();
    _requireRoomToSend();
    try {
      final sent = core.sendMessage(conversation, payload);
      return EncryptedMessageEnvelope.hexOf(sent.messageId.bytes);
    } on CryptoException catch (e) {
      throw _sendFailure(e);
    }
  }

  Future<SendOutcome> _upload(SentMessage first) async {
    var sent = first;
    for (var attempt = 0; attempt < maxUploadAttempts; attempt++) {
      final envelope = EncryptedMessageEnvelope(
        messageId: sent.messageId,
        schemaVersion: MessageVersions.schema,
        protocolVersion: MessageVersions.protocol,
        senderAccountId: account.value,
        senderDeviceId: _ownId,
        epoch: sent.epoch,
        ciphertext: sent.ciphertext,
      );
      final WriteResult result;
      try {
        result = await _transport.submitMessage(conversation, envelope);
      } on TransportException {
        return SendOutcome.queued;
      }
      switch (result.outcome) {
        case WriteOutcome.accepted:
          core.markMessageSent(
            conversation,
            sent.messageId,
            serverTimeMs: result.serverTimeMs ?? _clock(),
          );
          return SendOutcome.sent;
        case WriteOutcome.unavailable:
          return SendOutcome.queued;
        case WriteOutcome.refused:
          final existing = await _transport.message(
            conversation,
            envelope.messageIdHex,
          );
          if (existing != null) {
            if (existing.senderDeviceIdHex == _ownHex &&
                _sameBytes(existing.ciphertext, sent.ciphertext)) {
              // An earlier attempt landed; its acknowledgement was lost.
              core.markMessageSent(
                conversation,
                sent.messageId,
                serverTimeMs: existing.serverTimeMs ?? _clock(),
              );
              return SendOutcome.sent;
            }
            throw const MessagingException(MessagingFailure.rejected);
          }
          final conv = await _conversation();
          if (conv.epoch == sent.epoch) {
            // Not stale: refused for another reason (e.g. revoked device).
            throw const MessagingException(MessagingFailure.rejected);
          }
          await sync();
          try {
            sent = core.reencryptMessage(conversation, sent.messageId);
          } on CryptoException catch (e) {
            throw _sendFailure(e);
          }
      }
    }
    return SendOutcome.queued;
  }

  // ------------------------------------------------------------ membership

  /// Removes roster devices this device no longer trusts (revoked or no
  /// longer proven by lineage), then adds trusted devices of the members
  /// that published a KeyPackage. Each change is staged, submitted and
  /// resolved by [sync] (first commit wins).
  Future<void> reconcileMembership() async {
    await _requireActive();
    if (!_hasGroup) throw const MessagingException(MessagingFailure.notJoined);
    final conv = await _conversation();
    final roster = core.roster(_group);
    final own = _ownId;
    final untrusted = [
      for (final m in roster)
        if (m.deviceId != own &&
            !conv.members.contains(core.deviceAccount(m.deviceId)))
          m.deviceId,
    ];
    if (untrusted.isNotEmpty) {
      await _submit(core.stageRemoveMembers(conversation, untrusted), const []);
      _log('messaging_members_removed', 'staged');
    }
    if (!_hasGroup) return;
    final inRoster = {
      for (final m in core.roster(_group))
        EncryptedMessageEnvelope.hexOf(m.deviceId.bytes),
    };
    final adds = await _trustedKeyPackages(conv, inRoster: inRoster);
    if (adds.isNotEmpty) {
      await _submit(
        core.stageAddMembers(conversation, [
          for (final k in adds) k.keyPackage,
        ]),
        [for (final k in adds) k.deviceIdHex],
      );
      _log('messaging_members_added', 'staged');
    }
  }

  Future<void> _submit(StagedCommit staged, List<String> welcomeTargets) async {
    final welcome = staged.welcome;
    try {
      await _transport.submitCommit(
        conversation,
        CommitRecord(
          epoch: staged.fromEpoch,
          senderAccountId: account.value,
          senderDeviceIdHex: _ownHex,
          commit: staged.commit,
        ),
        [
          if (welcome != null)
            for (final t in welcomeTargets)
              WelcomeRecord(
                epoch: staged.fromEpoch,
                targetDeviceIdHex: t,
                welcome: welcome,
              ),
        ],
      );
    } on TransportException {
      // Resolved by the sync below: a commit that never landed is dropped.
    }
    // Whatever the outcome, the server's commits/{epoch} decides: confirm
    // ours after flushing the epoch's messages, or discard and follow.
    await sync();
  }

  /// Published KeyPackages of devices that are not in [inRoster], belong
  /// to a member account, and that this device's verified lineage assigns
  /// to exactly that account.
  Future<List<PublishedKeyPackage>> _trustedKeyPackages(
    ConversationRecord conv, {
    required Set<String> inRoster,
  }) async {
    final all = await _transport.keyPackages(conversation);
    return [
      for (final k in all)
        if (k.deviceIdHex != _ownHex &&
            !inRoster.contains(k.deviceIdHex) &&
            conv.members.contains(k.accountId) &&
            RegExp(r'^[0-9a-f]{32}$').hasMatch(k.deviceIdHex) &&
            core.deviceAccount(
                  DeviceId(EncryptedMessageEnvelope.bytesOfHex(k.deviceIdHex)),
                ) ==
                k.accountId)
          k,
    ];
  }

  // --------------------------------------------------------------- history

  /// Local history in display order (server time, then local time, then ID).
  List<ChatMessage> messages() {
    final own = _ownId;
    final list = [
      for (final m in core.history(conversation))
        ChatMessage(
          messageIdHex: EncryptedMessageEnvelope.hexOf(m.messageId.bytes),
          outgoing: m.direction == MessageDirection.outgoing,
          senderDeviceIdHex: m.senderDeviceId == own
              ? _ownHex
              : EncryptedMessageEnvelope.hexOf(m.senderDeviceId.bytes),
          state: m.state,
          sortTimeMs: m.serverTimeMs != 0 ? m.serverTimeMs : m.createdAtMs,
          text: _textOf(m.payload),
          media: _mediaOf(m.payload),
        ),
    ];
    list.sort((a, b) {
      final t = a.sortTimeMs.compareTo(b.sortTimeMs);
      return t != 0 ? t : a.messageIdHex.compareTo(b.messageIdHex);
    });
    return list;
  }

  /// "Delete for me": removes it from this device only (never from the
  /// server or from any other device). A media message's cached ciphertext
  /// object goes with it.
  void deleteForMe(String messageIdHex) {
    final id = MessageId(EncryptedMessageEnvelope.bytesOfHex(messageIdHex));
    final view = _mediaOf(_record(id)?.payload);
    core.deleteLocalMessage(conversation, id);
    final media = _media;
    if (view != null && media != null) {
      media.files.delete(_objectPath(media, view.mediaId));
    }
  }

  static MediaRefView? _mediaOf(Uint8List? payload) {
    if (payload == null || !MediaRefView.isMedia(payload)) return null;
    try {
      return MediaRefView.decode(payload);
    } on CryptoException {
      return null;
    }
  }

  static String? _textOf(Uint8List payload) {
    try {
      return TextPayload.decode(payload).text;
    } on TextPayloadException {
      return null;
    }
  }

  // ---------------------------------------------------------------- media

  /// Encrypts the file at [inputPath] inside the core (D-093, D-094): a new
  /// ciphertext object in the account's media directory plus the queued
  /// message carrying its key. Uploads the object, then the message.
  /// Offline or interrupted: [SendOutcome.queued]; [flushOutbox] finishes.
  /// The caller's file is only read; the app never copies plaintext.
  Future<SendOutcome> sendMedia({
    required String inputPath,
    required MediaClass mediaClass,
  }) async {
    final sent = await _encryptMedia(inputPath, mediaClass);
    final view = _ownView(sent.message.messageId);
    final SendOutcome outcome = await _ensureObjectUploaded(view)
        ? await _upload(sent.message)
        : SendOutcome.queued;
    _log('media_sent', outcome.name);
    return outcome;
  }

  /// Like [sendMedia], but only encrypts and seals: the object and its
  /// message stay in the outbox until [flushOutbox]. Lets a feature seal
  /// several media and the message that references them before anything
  /// leaves the device (a moment, D-113). Returns the message ID.
  Future<String> queueMedia({
    required String inputPath,
    required MediaClass mediaClass,
  }) async {
    final sent = await _encryptMedia(inputPath, mediaClass);
    return EncryptedMessageEnvelope.hexOf(sent.message.messageId.bytes);
  }

  Future<SentMedia> _encryptMedia(
    String inputPath,
    MediaClass mediaClass,
  ) async {
    final media = _requireMedia();
    await _requireActive();
    _requireRoomToSend();
    try {
      return core.sendMedia(
        conversation,
        inputPath: inputPath,
        mediaDirectory: media.directory,
        mediaClass: mediaClass,
      );
    } on CryptoException catch (e) {
      throw switch (e.code) {
        CryptoErrorCode.invalidInput => const MediaException(
          MediaFailure.invalidInput,
        ),
        CryptoErrorCode.inputTooLarge => const MediaException(
          MediaFailure.tooLarge,
        ),
        _ => _sendFailure(e),
      };
    }
  }

  /// Drops an outgoing message that is still queued — and, for media, its
  /// local ciphertext object — so it is never sent. Only for messages no
  /// attempt has uploaded yet (the caller sealed them and has not flushed):
  /// a message the server may already hold is never "un-sent" here.
  /// Returns false when [messageIdHex] is not a queued outgoing message.
  bool discardQueued(String messageIdHex) {
    final id = MessageId(EncryptedMessageEnvelope.bytesOfHex(messageIdHex));
    final record = _record(id);
    if (record == null ||
        record.direction != MessageDirection.outgoing ||
        record.state != MessageState.queued) {
      return false;
    }
    deleteForMe(messageIdHex);
    return true;
  }

  /// Decrypts a media message's object for display: from the local
  /// ciphertext cache, or downloaded (and size-checked) first. A cached
  /// object that fails verification is deleted and downloaded once more;
  /// a second failure is [MediaFailure.corrupted]. The result is private
  /// content: render it, then wipe it ([wipeBytes]); never store it.
  Future<Uint8List> openMedia(String messageIdHex) async {
    final media = _requireMedia();
    final id = MessageId(EncryptedMessageEnvelope.bytesOfHex(messageIdHex));
    final view = _mediaOf(_record(id)?.payload);
    if (view == null) throw const MediaException(MediaFailure.notMedia);
    final path = _objectPath(media, view.mediaId);
    var fresh = false;
    if (!media.files.exists(path)) {
      await _download(media, view, path);
      fresh = true;
    }
    while (true) {
      try {
        final plaintext = core.openMedia(conversation, id, path);
        _log('media_opened', fresh ? 'downloaded' : 'cached');
        return plaintext;
      } on CryptoException catch (e) {
        if (e.code == CryptoErrorCode.invalidInput) {
          // The cached file vanished underneath us.
          throw const MediaException(MediaFailure.unavailable);
        }
        if (e.code != CryptoErrorCode.authenticationFailure) rethrow;
        // Never keep an object that failed verification.
        media.files.delete(path);
        if (fresh) {
          _log('media_opened', 'corrupted');
          throw const MediaException(MediaFailure.corrupted);
        }
        await _download(media, view, path);
        fresh = true;
      }
    }
  }

  /// Downloads the object to a temporary name and moves it into the cache
  /// only when complete and exactly the authenticated size. Storage rules
  /// cannot tell devices apart on reads, so this device refuses downloads
  /// itself once it is no longer active (D-096).
  Future<void> _download(
    MediaSupport media,
    MediaRefView view,
    String path,
  ) async {
    await _requireActive();
    final partial = '$path.part';
    media.files.delete(partial);
    MediaDownloadOutcome outcome;
    try {
      outcome = await media.storage.download(
        conversationIdHex: _conversationHex,
        mediaIdHex: EncryptedMessageEnvelope.hexOf(view.mediaId.bytes),
        expectedSize: view.objectLength,
        destinationPath: partial,
      );
    } on TransportException {
      outcome = MediaDownloadOutcome.unavailable;
    }
    if (outcome == MediaDownloadOutcome.downloaded) {
      media.files.rename(partial, path);
      return;
    }
    media.files.delete(partial);
    _log('media_download', outcome.name);
    throw MediaException(
      outcome == MediaDownloadOutcome.wrongSize
          ? MediaFailure.corrupted
          : MediaFailure.unavailable,
    );
  }

  /// True once the object is on the server, uploaded now or by an earlier
  /// attempt whose acknowledgement was lost (create-only: the retry is
  /// refused, and the stored object is ours when its uploader and size
  /// match). False: not reachable now. A refused upload that is not ours
  /// is [MessagingFailure.rejected].
  Future<bool> _ensureObjectUploaded(MediaRefView view) async {
    final media = _requireMedia();
    final mediaHex = EncryptedMessageEnvelope.hexOf(view.mediaId.bytes);
    final path = _objectPath(media, view.mediaId);
    if (!media.files.exists(path)) {
      if (await _isOurObject(media, mediaHex, view.objectLength)) return true;
      throw const MediaException(MediaFailure.objectLost);
    }
    final MediaUploadOutcome outcome;
    try {
      outcome = await media.storage.upload(
        conversationIdHex: _conversationHex,
        mediaIdHex: mediaHex,
        senderDeviceIdHex: _ownHex,
        filePath: path,
      );
    } on TransportException {
      return false;
    }
    switch (outcome) {
      case MediaUploadOutcome.uploaded:
        return true;
      case MediaUploadOutcome.unavailable:
        return false;
      case MediaUploadOutcome.refused:
        if (await _isOurObject(media, mediaHex, view.objectLength)) {
          return true;
        }
        throw const MessagingException(MessagingFailure.rejected);
    }
  }

  Future<bool> _isOurObject(
    MediaSupport media,
    String mediaHex,
    int objectLength,
  ) async {
    final StoredMediaObject? stored;
    try {
      stored = await media.storage.stat(
        conversationIdHex: _conversationHex,
        mediaIdHex: mediaHex,
      );
    } on TransportException {
      return false;
    }
    return stored != null &&
        stored.size == objectLength &&
        stored.senderDeviceIdHex == _ownHex;
  }

  MediaRefView _ownView(MessageId id) {
    final view = _mediaOf(_record(id)?.payload);
    if (view == null) throw const MessagingException(MessagingFailure.rejected);
    return view;
  }

  LocalMessage? _record(MessageId id) {
    for (final m in core.history(conversation)) {
      if (m.messageId == id) return m;
    }
    return null;
  }

  String _objectPath(MediaSupport media, MediaId id) =>
      '${media.directory}/${mediaObjectFileName(conversation, id)}';

  String get _conversationHex =>
      EncryptedMessageEnvelope.hexOf(conversation.bytes);

  MediaSupport _requireMedia() =>
      _media ?? (throw const MediaException(MediaFailure.unsupported));

  // ----------------------------------------------------------------- shared

  void _requireRoomToSend() {
    if (!_hasGroup) {
      throw const MessagingException(MessagingFailure.notJoined);
    }
    final queued = core
        .history(conversation)
        .where((m) => m.state == MessageState.queued)
        .length;
    if (queued >= maxOutbox) {
      throw const MessagingException(MessagingFailure.outboxFull);
    }
  }

  bool get _hasGroup {
    try {
      core.epoch(_group);
      return true;
    } on CryptoException catch (e) {
      if (e.code == CryptoErrorCode.unknownGroup) return false;
      rethrow;
    }
  }

  Future<ConversationRecord> _conversation() async {
    final conv = await _transport.conversation(conversation);
    if (!conv.active || !conv.members.contains(account.value)) {
      throw const MessagingException(MessagingFailure.notMember);
    }
    return conv;
  }

  /// Firebase status gates sending (rules refuse non-active devices
  /// anyway); MLS membership is handled by [reconcileMembership].
  Future<void> _requireActive() async {
    core.checkAccount(account);
    if (await _registry.status(account, _ownHex) != DeviceStatus.active) {
      throw const MessagingException(MessagingFailure.deviceNotTrusted);
    }
  }

  static MessagingException _sendFailure(CryptoException e) => switch (e.code) {
    CryptoErrorCode.commitPending => const MessagingException(
      MessagingFailure.commitPending,
    ),
    CryptoErrorCode.unauthorizedDevice => const MessagingException(
      MessagingFailure.untrustedMember,
    ),
    CryptoErrorCode.unknownGroup => const MessagingException(
      MessagingFailure.notJoined,
    ),
    _ => throw e,
  };

  /// Local failures that must surface, never be counted as a bad message.
  static bool _isLocalStateFailure(CryptoException e) => switch (e.code) {
    CryptoErrorCode.stateCorruption ||
    CryptoErrorCode.persistenceFailure ||
    CryptoErrorCode.rollbackFailure ||
    CryptoErrorCode.accountMismatch ||
    CryptoErrorCode.internal => true,
    _ => false,
  };

  static bool _sameBytes(Uint8List a, Uint8List b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a[i] ^ b[i];
    }
    return diff == 0;
  }

  static void _log(
    String event,
    String outcome, [
    Map<String, Object?> extra = const {},
  ]) => AppLogger.info(
    event,
    fields: {'outcome': SafeLogString(outcome), ...extra},
  );
}
