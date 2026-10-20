import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:sirf_hum/infrastructure/firebase/firestore_device_registry.dart';
import 'package:sirf_hum/security/messaging/conversation_transport.dart';
import 'package:sirf_hum/security/messaging/message_envelope.dart';
import 'package:sirf_hum_crypto/sirf_hum_crypto.dart';

/// Firestore implementation of [ConversationTransport] (Prompt 10,
/// docs/security/E2EE-MESSAGING-DESIGN.md §5–§6; rules in
/// firebase/firestore.rules).
///
/// Messages are written in **transactions**, never plain writes: a
/// transaction either reaches the server or fails, whereas the SDK's
/// offline queue could land a write after the caller already treated it as
/// refused. Commits, their Welcomes and the epoch move go through the
/// `requestCommitChallenge` / `submitMlsCommit` callables with this
/// device's signed authorization (Prompt 17B, D-127): the rules refuse
/// those writes from clients. Only ciphertext, MLS handshake bytes and
/// public metadata cross this boundary.
class FirestoreConversationTransport implements ConversationTransport {
  FirestoreConversationTransport({
    FirebaseFirestore? firestore,
    FirebaseFunctions? functions,
  }) : _db = firestore ?? FirebaseFirestore.instance,
       _functions =
           functions ??
           FirebaseFunctions.instanceFor(
             region: FirestoreDeviceRegistry.functionsRegion,
           );

  final FirebaseFirestore _db;
  final FirebaseFunctions _functions;

  static String _hex(ConversationId id) =>
      EncryptedMessageEnvelope.hexOf(id.bytes);

  DocumentReference<Map<String, dynamic>> _conv(ConversationId id) =>
      _db.doc('conversations/${_hex(id)}');

  CollectionReference<Map<String, dynamic>> _sub(
    ConversationId id,
    String name,
  ) => _conv(id).collection(name);

  /// The `submitMlsCommit` request (D-127): exactly these fields; the
  /// server derives the sender account from the session and the sender
  /// device from the verified proof's certificate.
  static Map<String, Object> commitRequest(
    ConversationId id,
    CommitRecord c,
    List<WelcomeRecord> welcomes,
    CommitAuthorization a,
  ) => {
    'deviceId': c.senderDeviceIdHex,
    'conversationId': _hex(id),
    'fromEpoch': c.epoch,
    'challengeId': a.challengeId,
    'proof': base64.encode(a.proof),
    'commit': base64.encode(c.commit),
    'welcomes': [
      for (final w in welcomes)
        {
          'targetDeviceId': w.targetDeviceIdHex,
          'welcome': base64.encode(w.welcome),
        },
    ],
  };

  static Map<String, Object> messageFields(EncryptedMessageEnvelope e) => {
    ...e.toFields(),
    'ciphertext': Blob(e.ciphertext),
    'serverTime': FieldValue.serverTimestamp(),
  };

  @override
  Future<ConversationRecord> conversation(ConversationId id) =>
      _guard(() async {
        final snap = await _conv(id).get();
        final data = snap.data();
        if (data == null) {
          throw const TransportException(TransportFailure.denied);
        }
        final members = data['members'];
        final epoch = data['epoch'];
        if (members is! List || epoch is! int) {
          throw const TransportException(TransportFailure.malformed);
        }
        return ConversationRecord(
          members: [for (final m in members) '$m'],
          epoch: epoch,
          active: data['state'] == 'active',
        );
      });

  @override
  Future<void> publishKeyPackage(ConversationId id, PublishedKeyPackage kp) =>
      _guard(
        () => _sub(id, 'keyPackages').doc(kp.deviceIdHex).set({
          'schemaVersion': 1,
          'accountId': kp.accountId,
          'deviceId': kp.deviceIdHex,
          'keyPackage': Blob(kp.keyPackage),
          'updatedAt': FieldValue.serverTimestamp(),
        }),
      );

  @override
  Future<List<PublishedKeyPackage>> keyPackages(ConversationId id) => _guard(
    () async {
      final snap = await _sub(id, 'keyPackages').get();
      return [
        for (final d in snap.docs)
          if (d.data()['keyPackage'] is Blob && d.data()['accountId'] is String)
            PublishedKeyPackage(
              accountId: d.data()['accountId'] as String,
              deviceIdHex: d.id,
              keyPackage: (d.data()['keyPackage'] as Blob).bytes,
            ),
      ];
    },
  );

  @override
  Future<CommitChallenge> requestCommitChallenge(
    ConversationId id, {
    required String deviceIdHex,
    required int fromEpoch,
  }) async {
    try {
      final result = await _functions
          .httpsCallable('requestCommitChallenge')
          .call<Map<String, dynamic>>({
            'deviceId': deviceIdHex,
            'conversationId': _hex(id),
            'fromEpoch': fromEpoch,
          });
      final challengeId = result.data['challengeId'];
      final nonce = result.data['challenge'];
      if (challengeId is! String || nonce is! String) {
        throw const TransportException(TransportFailure.malformed);
      }
      return CommitChallenge(
        challengeId: challengeId,
        nonce: base64.decode(nonce),
      );
    } on FirebaseFunctionsException catch (e) {
      throw TransportException(
        _unreachable(e.code)
            ? TransportFailure.unavailable
            : TransportFailure.denied,
      );
    } on FormatException {
      throw const TransportException(TransportFailure.malformed);
    }
  }

  @override
  Future<WriteResult> submitCommit(
    ConversationId id,
    CommitRecord commit,
    List<WelcomeRecord> welcomes,
    CommitAuthorization authorization,
  ) async {
    try {
      await _functions
          .httpsCallable('submitMlsCommit')
          .call<Map<String, dynamic>>(
            commitRequest(id, commit, welcomes, authorization),
          );
      return const WriteResult(WriteOutcome.accepted);
    } on FirebaseFunctionsException catch (e) {
      // Refused (conflict, unauthorized, expired) or unreachable: either
      // way the caller re-reads commits/{epoch} to learn what happened.
      return WriteResult(
        _unreachable(e.code) ? WriteOutcome.unavailable : WriteOutcome.refused,
      );
    }
  }

  static bool _unreachable(String code) =>
      code == 'unavailable' || code == 'internal' || code == 'unknown';

  @override
  Future<CommitRecord?> commit(ConversationId id, int epoch) =>
      _guard(() async {
        final data = (await _sub(id, 'commits').doc('$epoch').get()).data();
        if (data == null) return null;
        final sender = data['senderDeviceId'];
        final account = data['senderAccountId'];
        final bytes = data['commit'];
        if (sender is! String || account is! String || bytes is! Blob) {
          throw const TransportException(TransportFailure.malformed);
        }
        return CommitRecord(
          epoch: epoch,
          senderAccountId: account,
          senderDeviceIdHex: sender,
          commit: bytes.bytes,
        );
      });

  @override
  Future<List<WelcomeRecord>> welcomesFor(
    ConversationId id,
    String deviceHex,
  ) => _guard(() async {
    final snap = await _sub(
      id,
      'welcomes',
    ).where('targetDeviceId', isEqualTo: deviceHex).get();
    return [
      for (final d in snap.docs)
        if (d.data()['welcome'] is Blob && d.data()['epoch'] is int)
          WelcomeRecord(
            epoch: d.data()['epoch'] as int,
            targetDeviceIdHex: deviceHex,
            welcome: (d.data()['welcome'] as Blob).bytes,
          ),
    ];
  });

  @override
  Future<WriteResult> submitMessage(
    ConversationId id,
    EncryptedMessageEnvelope envelope,
  ) => _write(() async {
    final ref = _sub(id, 'messages').doc(envelope.messageIdHex);
    final written = await _db.runTransaction((tx) async {
      if ((await tx.get(ref)).exists) return false;
      tx.set(ref, messageFields(envelope));
      return true;
    });
    if (!written) return const WriteResult(WriteOutcome.refused);
    final stored = await message(id, envelope.messageIdHex);
    return WriteResult(
      WriteOutcome.accepted,
      serverTimeMs: stored?.serverTimeMs,
    );
  });

  @override
  Future<EncryptedMessageEnvelope?> message(ConversationId id, String hexId) =>
      _guard(() async {
        final data = (await _sub(id, 'messages').doc(hexId).get()).data();
        if (data == null) return null;
        return _parse(hexId, data);
      });

  @override
  Future<({List<EncryptedMessageEnvelope> messages, int malformedCount})>
  messagesAtEpoch(ConversationId id, int epoch) => _guard(() async {
    final snap = await _sub(
      id,
      'messages',
    ).where('epoch', isEqualTo: epoch).get();
    final messages = <EncryptedMessageEnvelope>[];
    var malformed = 0;
    for (final d in snap.docs) {
      try {
        messages.add(_parse(d.id, d.data()));
      } on EnvelopeFormatException {
        malformed++;
      }
    }
    // Server time, then ID: deterministic; MLS tolerates reordering anyway.
    messages.sort((a, b) {
      final t = (a.serverTimeMs ?? 0).compareTo(b.serverTimeMs ?? 0);
      return t != 0 ? t : a.messageIdHex.compareTo(b.messageIdHex);
    });
    return (messages: messages, malformedCount: malformed);
  });

  static EncryptedMessageEnvelope _parse(
    String id,
    Map<String, Object?> data,
  ) => EncryptedMessageEnvelope.fromFields(
    id,
    data,
    bytesOf: (v) =>
        v is Blob ? v.bytes : (throw const EnvelopeFormatException()),
    timeOf: (v) => v is Timestamp ? v.millisecondsSinceEpoch : null,
  );

  /// A refusal by the rules is an answer (`refused`); no connection is
  /// `unavailable`. SDK messages never propagate.
  static Future<WriteResult> _write(Future<WriteResult> Function() run) async {
    try {
      return await run();
    } on FirebaseException catch (e) {
      return switch (e.code) {
        'permission-denied' ||
        'already-exists' ||
        'failed-precondition' ||
        'aborted' => const WriteResult(WriteOutcome.refused),
        _ => const WriteResult(WriteOutcome.unavailable),
      };
    }
  }

  static Future<T> _guard<T>(Future<T> Function() run) async {
    try {
      return await run();
    } on TransportException {
      rethrow;
    } on FirebaseException catch (e) {
      throw TransportException(
        e.code == 'permission-denied'
            ? TransportFailure.denied
            : TransportFailure.unavailable,
      );
    }
  }
}
