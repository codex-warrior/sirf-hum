// Messaging service (Prompt 10): real native cores, real enrollment and
// approval flows (so lineage carries real signatures), one FakeRegistry per
// account and an in-memory server enforcing the Firestore rules' semantics.
// Persons A (A1 root, A2) and B (B1 root, B2).
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sirf_hum/core/logging/app_logger.dart';
import 'package:sirf_hum/security/device/device_registration.dart';
import 'package:sirf_hum/security/device/device_status.dart';
import 'package:sirf_hum/security/device/device_trust_service.dart';
import 'package:sirf_hum/security/messaging/commit_authorization.dart';
import 'package:sirf_hum/security/messaging/conversation_transport.dart';
import 'package:sirf_hum/security/messaging/lifecycle_authorization.dart';
import 'package:sirf_hum/security/messaging/message_envelope.dart';
import 'package:sirf_hum/security/messaging/messaging_service.dart';
import 'package:sirf_hum_crypto/sirf_hum_crypto.dart';

import '../device/device_test_support.dart';
import '../device/fake_registry.dart';
import 'fake_transport.dart';

/// Routes each account to its own fake registry (the real Firestore
/// registry serves every account; rules decide who may read what).
class _Registries implements DeviceRegistry {
  _Registries(this.byAccount);

  final Map<String, FakeRegistry> byAccount;

  FakeRegistry _r(AccountId a) => byAccount[a.value]!;

  @override
  Future<DeviceStatus> status(AccountId a, String d) => _r(a).status(a, d);

  @override
  Future<AccountTrustState> trustState(AccountId a) => _r(a).trustState(a);

  @override
  Future<LineageRequest?> lineage(AccountId a) => _r(a).lineage(a);

  @override
  Future<List<DeviceRecord>> listDevices(AccountId a) => _r(a).listDevices(a);

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('not used by messaging');
}

class _Sink implements LogSink {
  final lines = <String>[];

  @override
  void write(LogRecord record) => lines.add(record.message);
}

Matcher matcher(MessagingFailure f) =>
    throwsA(isA<MessagingException>().having((e) => e.failure, 'failure', f));

void main() {
  final accountA = AccountId('accountA');
  final accountB = AccountId('accountB');
  final cid = ConversationId(Uint8List.fromList(List.filled(16, 0x5a)));

  group('native', () {
    late Directory root;
    late Map<String, FakeRegistry> registries;
    late FakeTransport server;
    late _Registries registry;
    final cores = <String, CryptoCore>{};
    final services = <String, MessagingService>{};
    var clock = 1000;

    String hex(String name) =>
        PendingDeviceRegistration.hexOf(cores[name]!.publicIdentity().deviceId);

    CryptoCore open(String name) => CryptoCore.initializeWithPlatformKey(
      directory: (Directory(
        '${root.path}/$name',
      )..createSync(recursive: true)).path,
      storeKey: Uint8List.fromList(List.filled(32, name.codeUnits.first)),
    );

    MessagingService serviceFor(String name, AccountId account) =>
        services[name] = MessagingService(
          core: cores[name]!,
          account: account,
          conversation: cid,
          transport: server,
          registry: registry,
          clock: () => ++clock,
        );

    /// Enrolls a device: first device of its account, or approved by
    /// [approver] (D-075), through the real flows.
    Future<void> enroll(
      String name,
      AccountId account, {
      String? approver,
    }) async {
      final core = cores[name] = open(name)..createIdentity(account);
      final reg = registries[account.value]!;
      final state = await DeviceRegistrationFlow(
        reg,
      ).enroll(core: core, account: account, platform: DevicePlatform.android);
      if (approver != null) {
        expect(state, isA<EnrollmentAwaitingApproval>());
        final trust = DeviceTrustService(reg);
        final candidate = (await trust.pendingApprovals(
          core: cores[approver]!,
          account: account,
        )).single;
        await trust.approve(
          core: cores[approver]!,
          account: account,
          candidate: candidate,
        );
      } else {
        expect(state, isA<EnrollmentActive>());
      }
    }

    /// Out-of-band verification of both persons' root keys (D-064, D-085).
    void anchorRoots(String name) {
      for (final rootName in ['a1', 'b1']) {
        cores[name]!.trustVerifiedPersonKey(
          cores[rootName]!.publicIdentity().personKey,
        );
      }
    }

    Future<void> online(String name, AccountId account) async {
      anchorRoots(name);
      final s = serviceFor(name, account);
      await s.refreshTrust();
      await s.publishKeyPackage();
    }

    List<String?> texts(String name) => [
      for (final m in services[name]!.messages()) m.text,
    ];

    /// While true the server refuses every commit authorization (models a
    /// device revoked between staging and submission, or a forged proof).
    var denyCommits = false;

    /// The server-side proof check (D-127): Ed25519 is deterministic, so the
    /// claimed device's own core recomputes the expected proof.
    bool verifyCommitProof(
      String deviceHex,
      Uint8List signed,
      Uint8List proof,
    ) {
      if (denyCommits) return false;
      for (final e in cores.entries) {
        if (hex(e.key) != deviceHex) continue;
        final expected = e.value.deviceProof(DeviceProofPurpose.commit, signed);
        return expected.length == proof.length &&
            Iterable<int>.generate(
              proof.length,
            ).every((i) => expected[i] == proof[i]);
      }
      return false;
    }

    /// What a device does to submit a staged commit (D-127): challenge,
    /// binding, signature by ITS core. [signer] lets a test sign with
    /// another core (a forged authorization).
    Future<WriteResult> submitAs(
      String name,
      AccountId account,
      StagedCommit staged, {
      String? signer,
    }) async {
      final c = await server.requestCommitChallenge(
        cid,
        deviceIdHex: hex(name),
        fromEpoch: staged.fromEpoch,
      );
      final signed = commitAuthorizationChallenge(
        nonce: c.nonce,
        accountId: account.value,
        deviceId: cores[name]!.publicIdentity().deviceId.bytes,
        conversationId: cid.bytes,
        fromEpoch: staged.fromEpoch,
        protocolVersion: MessageVersions.protocol,
        commit: staged.commit,
        welcomes: const [],
      );
      return server.submitCommit(
        cid,
        _commit(staged, account.value, hex(name)),
        const [],
        CommitAuthorization(
          challengeId: c.challengeId,
          proof: cores[signer ?? name]!.deviceProof(
            DeviceProofPurpose.commit,
            signed,
          ),
        ),
      );
    }

    /// The server-side recovery proof check (D-135), as for commits.
    bool verifyRecoveryProof(
      String deviceHex,
      Uint8List signed,
      Uint8List proof,
    ) {
      for (final e in cores.entries) {
        if (hex(e.key) != deviceHex) continue;
        final expected = e.value.deviceProof(
          DeviceProofPurpose.conversationRecovery,
          signed,
        );
        return expected.length == proof.length &&
            Iterable<int>.generate(
              proof.length,
            ).every((i) => expected[i] == proof[i]);
      }
      return false;
    }

    setUp(() async {
      root = Directory.systemTemp.createTempSync('sh_messaging_');
      registries = {
        accountA.value: FakeRegistry(),
        accountB.value: FakeRegistry(),
      };
      registry = _Registries(registries);
      denyCommits = false;
      server =
          FakeTransport(
              members: [accountA.value, accountB.value],
              statusOf: (account, device) =>
                  registries[account]?.statuses[device] ?? DeviceStatus.unknown,
              verifyCommitProof: verifyCommitProof,
            )
            ..verifyRecoveryProof = verifyRecoveryProof
            ..trustEpochOf = ((a) => registries[a]!.trustEpoch);
      cores.clear();
      services.clear();
      await enroll('a1', accountA);
      await enroll('b1', accountB);
      await enroll('a2', accountA, approver: 'a1');
      await enroll('b2', accountB, approver: 'b1');
      for (final (n, a) in [
        ('a1', accountA),
        ('a2', accountA),
        ('b1', accountB),
        ('b2', accountB),
      ]) {
        await online(n, a);
      }
      // A1 creates the group (wins commits/0); everyone else joins.
      final created = await services['a1']!.sync();
      expect(created.epoch, 1);
      for (final n in ['a2', 'b1', 'b2']) {
        final r = await services[n]!.sync();
        expect(r.joined, isTrue, reason: n);
        expect(r.epoch, 1);
      }
    });

    tearDown(() {
      for (final c in cores.values) {
        c.close();
      }
      root.deleteSync(recursive: true);
    });

    test('connect publishes a KeyPackage only while outside the group, and '
        'is safe to repeat', () async {
      final a1Package = server.keyPackageDocs[hex('a1')];
      expect((await services['a1']!.connect()).epoch, 1);
      expect(identical(server.keyPackageDocs[hex('a1')], a1Package), isTrue);

      await enroll('a3', accountA, approver: 'a1');
      anchorRoots('a3');
      final a3 = serviceFor('a3', accountA);
      final first = await a3.connect();
      expect(first.joined, isFalse);
      final a3Package = server.keyPackageDocs[hex('a3')];
      expect(a3Package, isNotNull);
      await a3.connect();
      expect(identical(server.keyPackageDocs[hex('a3')], a3Package), isTrue);
    });

    test('A1, A2, B1, B2: every device reaches every other device', () async {
      for (final sender in ['a1', 'a2', 'b1', 'b2']) {
        expect(
          await services[sender]!.sendText('from $sender'),
          SendOutcome.sent,
        );
        for (final receiver in ['a1', 'a2', 'b1', 'b2']) {
          if (receiver == sender) continue;
          final r = await services[receiver]!.sync();
          expect(r.failures, isEmpty, reason: '$sender → $receiver');
        }
      }
      for (final n in ['a1', 'a2', 'b1', 'b2']) {
        expect(texts(n), ['from a1', 'from a2', 'from b1', 'from b2']);
      }
      // The server only ever held ciphertext.
      for (final doc in server.messageDocs.values) {
        expect(String.fromCharCodes(doc.ciphertext), isNot(contains('from')));
      }
    });

    test(
      'revoked A2 is removed from MLS, refused by the server, cannot return',
      () async {
        await DeviceTrustService(registries[accountA.value]!).revoke(
          core: cores['a1']!,
          account: accountA,
          deviceIdHex: hex('a2'),
          reason: RevocationReason.lost,
        );
        // Firebase authorization (status) ≠ MLS membership: until the Remove
        // commit A2 still holds the epoch secrets, so senders refuse.
        await services['b1']!.refreshTrust();
        await expectLater(
          services['b1']!.sendText('not for a2'),
          matcher(MessagingFailure.untrustedMember),
        );
        await services['b1']!.reconcileMembership();
        expect(server.epoch, 2);
        expect(
          cores['b1']!
              .roster(GroupId(cid.bytes))
              .map((m) => PendingDeviceRegistration.hexOf(m.deviceId)),
          isNot(contains(hex('a2'))),
        );
        // A2: the server refuses it, and MLS removed it.
        await expectLater(
          services['a2']!.sendText('still here?'),
          matcher(MessagingFailure.deviceNotTrusted),
        );
        await expectLater(
          services['a2']!.publishKeyPackage(),
          matcher(MessagingFailure.deviceNotTrusted),
        );
        expect((await services['a2']!.sync()).removed, isTrue);
        // The others follow and keep talking.
        for (final n in ['a1', 'b2']) {
          await services[n]!.refreshTrust();
          expect((await services[n]!.sync()).epoch, 2);
        }
        expect(
          await services['b1']!.sendText('after removal'),
          SendOutcome.sent,
        );
        await services['a1']!.sync();
        await services['b2']!.sync();
        expect(texts('a1'), contains('after removal'));
        expect(texts('b2'), contains('after removal'));
        // Even a forged write as A2 (stale state, valid session) is refused.
        expect(
          server.statusOf(accountA.value, hex('a2')),
          DeviceStatus.revoked,
        );
      },
    );

    test(
      'offline: queued sealed, uploaded later, re-encrypted after a commit',
      () async {
        server.offline = true;
        expect(
          await services['a1']!.sendText('written offline'),
          SendOutcome.queued,
        );
        final queued = services['a1']!.messages().single;
        expect(queued.state, MessageState.queued);
        expect(server.messageDocs, isEmpty);
        server.offline = false;
        // Meanwhile B1 commits (epoch 1 → 2).
        final staged = cores['b1']!.stageSelfUpdate(cid);
        await submitAs('b1', accountB, staged);
        await services['b1']!.sync();
        // A1 reconnects: the epoch-1 upload is refused as stale, A1 syncs,
        // re-encrypts the SAME message ID and uploads.
        expect(await services['a1']!.flushOutbox(), 1);
        final sent = services['a1']!.messages().single;
        expect(sent.state, MessageState.sent);
        expect(sent.messageIdHex, queued.messageIdHex);
        expect(server.messageDocs.values.single.epoch, 2);
        await services['b2']!.sync();
        expect(texts('b2'), ['written offline']);
      },
    );

    test('a lost acknowledgement never duplicates a message', () async {
      server.loseNextAck = true;
      expect(
        await services['a1']!.sendText('exactly once'),
        SendOutcome.queued,
      );
      expect(server.messageDocs, hasLength(1), reason: 'it did land');
      expect(await services['a1']!.flushOutbox(), 1);
      expect(server.messageDocs, hasLength(1));
      expect(services['a1']!.messages().single.state, MessageState.sent);
      await services['b1']!.sync();
      await services['b1']!.sync();
      expect(texts('b1'), ['exactly once']);
    });

    test(
      'concurrent membership changes: first commit wins, the loser converges',
      () async {
        await enroll('b3', accountB, approver: 'b1');
        await online('b3', accountB);
        for (final n in ['a1', 'a2', 'b1', 'b2']) {
          await services[n]!.refreshTrust();
        }
        // A1 stages an add of B3 but has not submitted yet...
        final a1Staged = cores['a1']!.stageAddMembers(cid, [
          server.keyPackageDocs[hex('b3')]!.keyPackage,
        ]);
        // ...B1 wins the epoch.
        await services['b1']!.reconcileMembership();
        expect(server.epoch, 2);
        // Epoch 1 already has a commit: no authorization is even issued.
        await expectLater(
          submitAs('a1', accountA, a1Staged),
          throwsA(isA<TransportException>()),
        );
        // A1 syncs: discards its staged commit and follows B1's.
        final r = await services['a1']!.sync();
        expect(r.epoch, 2);
        expect(cores['a1']!.stagedCommitEpoch(cid), isNull);
        expect((await services['b3']!.sync()).joined, isTrue);
        expect(
          await services['b3']!.sendText('hello from b3'),
          SendOutcome.sent,
        );
        for (final n in ['a1', 'a2', 'b2']) {
          await services[n]!.sync();
          expect(texts(n), ['hello from b3']);
        }
      },
    );

    test(
      'a staged commit survives a restart and is resolved by sync',
      () async {
        final staged = cores['a1']!.stageSelfUpdate(cid);
        final result = await submitAs('a1', accountA, staged);
        expect(result.outcome, WriteOutcome.accepted);
        cores['a1']!.close();
        cores['a1'] = open('a1');
        serviceFor('a1', accountA);
        expect(cores['a1']!.stagedCommitEpoch(cid), 1);
        expect((await services['a1']!.sync()).epoch, 2);
        expect((await services['b2']!.sync()).epoch, 2);
        expect(
          await services['b2']!.sendText('after restart'),
          SendOutcome.sent,
        );
        await services['a1']!.sync();
        expect(texts('a1'), ['after restart']);
      },
    );

    test('relabelled, forged and malformed messages fail closed', () async {
      expect(await services['a1']!.sendText('genuine'), SendOutcome.sent);
      final genuine = server.messageDocs.values.single;
      // The server relabels the sender account.
      final relabelled = FakeTransport.stamp(
        EncryptedMessageEnvelope(
          messageId: MessageId(Uint8List.fromList(List.filled(16, 1))),
          schemaVersion: 1,
          protocolVersion: 1,
          senderAccountId: accountB.value,
          senderDeviceId: genuine.senderDeviceId,
          epoch: genuine.epoch,
          ciphertext: genuine.ciphertext,
        ),
        5,
      );
      // ...or copies the ciphertext under another message ID.
      final copied = FakeTransport.stamp(
        EncryptedMessageEnvelope(
          messageId: MessageId(Uint8List.fromList(List.filled(16, 2))),
          schemaVersion: 1,
          protocolVersion: 1,
          senderAccountId: accountA.value,
          senderDeviceId: genuine.senderDeviceId,
          epoch: genuine.epoch,
          ciphertext: genuine.ciphertext,
        ),
        6,
      );
      server.messageDocs[relabelled.messageIdHex] = relabelled;
      server.messageDocs[copied.messageIdHex] = copied;
      server.malformed[1] = 2;
      final r = await services['b1']!.sync();
      expect(r.received, 1);
      expect(r.failures, {
        'unauthorized_device': 1,
        'envelopeMismatch': 1,
        'malformed': 2,
      });
      expect(texts('b1'), ['genuine']);
    });

    // Prompt 17, P17-05 (E77), fixed by D-127. Before, any Firebase session
    // of either account could win commits/{epoch} with filler bytes and
    // every device then stalled (stateDiverged). Now the server needs this
    // device's signed, single-use authorization over the exact commit.
    test('a session without the device key cannot move the epoch; the '
        'conversation keeps working', () async {
      final filler = CommitRecord(
        epoch: 1,
        senderAccountId: accountA.value,
        senderDeviceIdHex: hex('a1'),
        commit: Uint8List.fromList(List.filled(500, 1)),
      );
      // A real challenge for A1 (a session may ask), but no device key.
      final c = await server.requestCommitChallenge(
        cid,
        deviceIdHex: hex('a1'),
        fromEpoch: 1,
      );
      expect(
        (await server.submitCommit(
          cid,
          filler,
          const [],
          CommitAuthorization(challengeId: c.challengeId, proof: Uint8List(64)),
        )).outcome,
        WriteOutcome.refused,
      );
      // A genuine authorization for ANOTHER commit cannot carry the filler,
      // and is gone once used (replay).
      final genuine = await server.requestCommitChallenge(
        cid,
        deviceIdHex: hex('a1'),
        fromEpoch: 1,
      );
      final staged = cores['a1']!.stageSelfUpdate(cid);
      final proof = cores['a1']!.deviceProof(
        DeviceProofPurpose.commit,
        commitAuthorizationChallenge(
          nonce: genuine.nonce,
          accountId: accountA.value,
          deviceId: cores['a1']!.publicIdentity().deviceId.bytes,
          conversationId: cid.bytes,
          fromEpoch: 1,
          protocolVersion: MessageVersions.protocol,
          commit: staged.commit,
          welcomes: const [],
        ),
      );
      final auth = CommitAuthorization(
        challengeId: genuine.challengeId,
        proof: proof,
      );
      expect(
        (await server.submitCommit(cid, filler, const [], auth)).outcome,
        WriteOutcome.refused,
      );
      expect(
        (await server.submitCommit(
          cid,
          _commit(staged, accountA.value, hex('a1')),
          const [],
          auth,
        )).outcome,
        WriteOutcome.refused,
        reason: 'single use',
      );
      cores['a1']!.discardCommit(cid, 1);
      // Another device's key, or the partner, cannot sign for A1.
      final a1Staged = cores['a1']!.stageSelfUpdate(cid);
      expect(
        (await submitAs('a1', accountA, a1Staged, signer: 'a2')).outcome,
        WriteOutcome.refused,
      );
      expect(
        (await submitAs('a1', accountA, a1Staged, signer: 'b1')).outcome,
        WriteOutcome.refused,
      );
      cores['a1']!.discardCommit(cid, 1);
      expect(server.epoch, 1);
      // Only the group's creation (epoch 0, from setUp) was ever accepted.
      expect(server.commits.keys, [0]);
      // Nothing stalled: every device syncs and a message flows.
      for (final n in ['a1', 'a2', 'b1', 'b2']) {
        expect((await services[n]!.sync()).epoch, 1, reason: n);
      }
      expect(await services['b1']!.sendText('still here'), SendOutcome.sent);
      await services['a2']!.sync();
      expect(texts('a2'), ['still here']);
    });

    test('a refused authorization never advances local state; a valid one '
        'then does', () async {
      await enroll('a3', accountA, approver: 'a1');
      await online('a3', accountA);
      await services['a1']!.refreshTrust();
      denyCommits = true;
      await services['a1']!.reconcileMembership();
      expect(server.refusedCommits, greaterThan(0));
      expect(server.epoch, 1);
      expect(cores['a1']!.epoch(GroupId(cid.bytes)), 1);
      expect(cores['a1']!.stagedCommitEpoch(cid), isNull);
      expect((await services['a3']!.sync()).joined, isFalse);
      denyCommits = false;
      await services['a1']!.reconcileMembership();
      expect(server.epoch, 2);
      expect((await services['a3']!.sync()).joined, isTrue);
    });

    test(
      'revoked, pending and unknown devices get no commit authorization',
      () async {
        registries[accountA.value]!.statuses[hex('a2')] = DeviceStatus.revoked;
        final staged = cores['a2']!.stageSelfUpdate(cid);
        await expectLater(
          submitAs('a2', accountA, staged),
          throwsA(isA<TransportException>()),
        );
        cores['a2']!.discardCommit(cid, 1);
        await expectLater(
          services['a2']!.reconcileMembership(),
          matcher(MessagingFailure.deviceNotTrusted),
        );
        registries[accountB.value]!.statuses[hex('b2')] = DeviceStatus.pending;
        await expectLater(
          server.requestCommitChallenge(
            cid,
            deviceIdHex: hex('b2'),
            fromEpoch: 1,
          ),
          throwsA(isA<TransportException>()),
        );
        await expectLater(
          server.requestCommitChallenge(
            cid,
            deviceIdHex: 'ab' * 16,
            fromEpoch: 1,
          ),
          throwsA(isA<TransportException>()),
        );
        expect(server.epoch, 1);
      },
    );

    test('an authorization is bound to its device and account: another '
        'account cannot use it', () async {
      final c = await server.requestCommitChallenge(
        cid,
        deviceIdHex: hex('a1'),
        fromEpoch: 1,
      );
      final staged = cores['b1']!.stageSelfUpdate(cid);
      final proof = cores['b1']!.deviceProof(
        DeviceProofPurpose.commit,
        commitAuthorizationChallenge(
          nonce: c.nonce,
          accountId: accountB.value,
          deviceId: cores['b1']!.publicIdentity().deviceId.bytes,
          conversationId: cid.bytes,
          fromEpoch: 1,
          protocolVersion: MessageVersions.protocol,
          commit: staged.commit,
          welcomes: const [],
        ),
      );
      expect(
        (await server.submitCommit(
          cid,
          _commit(staged, accountB.value, hex('b1')),
          const [],
          CommitAuthorization(challengeId: c.challengeId, proof: proof),
        )).outcome,
        WriteOutcome.refused,
      );
      cores['b1']!.discardCommit(cid, 1);
      expect(server.epoch, 1);
    });

    test('a conversation the account is not a member of is unusable', () async {
      final outsider = MessagingService(
        core: cores['a1']!,
        account: accountA,
        conversation: cid,
        transport: FakeTransport(
          members: [accountB.value, 'accountX'],
          statusOf: (_, _) => DeviceStatus.active,
        ),
        registry: registry,
      );
      await expectLater(outsider.sync(), matcher(MessagingFailure.notMember));
      server.active = false;
      await expectLater(
        services['a1']!.sendText('closed'),
        matcher(MessagingFailure.notMember),
      );
    });

    // ---------------------------------------- recovery (Prompt 17C, D-135)

    /// The successor's server, as recoverConversation provisioned it.
    FakeTransport successorServer() => FakeTransport(
      members: [accountA.value, accountB.value],
      statusOf: server.statusOf,
      verifyCommitProof: verifyCommitProof,
    );

    CommitAuthorization recoverySigned(
      String name,
      AccountId account,
      CommitChallenge c,
      int epoch,
      int trust, {
      DeviceProofPurpose purpose = DeviceProofPurpose.conversationRecovery,
    }) => CommitAuthorization(
      challengeId: c.challengeId,
      proof: cores[name]!.deviceProof(
        purpose,
        recoveryAuthorizationChallenge(
          nonce: c.nonce,
          accountId: account.value,
          deviceId: cores[name]!.publicIdentity().deviceId.bytes,
          conversationId: cid.bytes,
          epoch: epoch,
          trustEpoch: trust,
        ),
      ),
    );

    test(
      'recovery: a new group for the couple; old history stays, the old '
      'conversation is read-only, pending messages are not re-sent',
      () async {
        expect(await services['a1']!.sendText('before'), SendOutcome.sent);
        for (final n in ['a2', 'b1', 'b2']) {
          await services[n]!.sync();
        }
        // Queued (offline) in the old group, never silently moved.
        server.offline = true;
        expect(await services['a2']!.sendText('queued'), SendOutcome.queued);
        server.offline = false;

        final next = await services['b1']!.recover();
        expect(server.retired, isTrue);
        expect(
          EncryptedMessageEnvelope.hexOf(next.bytes),
          server.successorIdHex,
        );
        // Every device of both accounts finds the same, verified successor.
        for (final n in ['a1', 'a2', 'b1', 'b2']) {
          final found = await services[n]!.successor();
          expect(found?.bytes, next.bytes, reason: n);
        }
        // The old conversation takes nothing more.
        final before = server.writes;
        await expectLater(
          services['a1']!.sendText('into the old group'),
          matcher(MessagingFailure.retired),
        );
        await expectLater(
          services['a2']!.flushOutbox(),
          matcher(MessagingFailure.retired),
        );
        await expectLater(
          services['b2']!.recover(),
          matcher(MessagingFailure.retired),
        );
        expect(server.writes, before);
        // Old history stays on the phones.
        for (final n in ['a1', 'b1', 'b2']) {
          expect(texts(n), contains('before'), reason: n);
        }

        // The new group: built from verified lineage like a new couple's.
        final fresh = successorServer();
        final successors = <String, MessagingService>{};
        for (final (n, a) in [
          ('a1', accountA),
          ('a2', accountA),
          ('b1', accountB),
          ('b2', accountB),
        ]) {
          final svc = successors[n] = MessagingService(
            core: cores[n]!,
            account: a,
            conversation: next,
            transport: fresh,
            registry: registry,
            clock: () => ++clock,
          );
          await svc.refreshTrust();
          await svc.publishKeyPackage();
        }
        expect((await successors['b1']!.sync()).epoch, 1);
        for (final n in ['a1', 'a2', 'b2']) {
          expect((await successors[n]!.sync()).joined, isTrue, reason: n);
        }
        expect(await successors['a1']!.sendText('after'), SendOutcome.sent);
        expect(await successors['b2']!.sendText('reply'), SendOutcome.sent);
        for (final n in ['a2', 'b1']) {
          final r = await successors[n]!.sync();
          expect(r.failures, isEmpty, reason: n);
          expect([
            for (final m in successors[n]!.messages()) m.text,
          ], containsAll(['after', 'reply']));
        }
        // Nothing from the old outbox reached the new conversation.
        expect(fresh.messageDocs, hasLength(2));
        // The server held only ciphertext in either conversation.
        for (final doc in [
          ...server.messageDocs.values,
          ...fresh.messageDocs.values,
        ]) {
          for (final word in ['before', 'after', 'reply', 'queued']) {
            expect(String.fromCharCodes(doc.ciphertext), isNot(contains(word)));
          }
        }
      },
    );

    test('recovery is device-bound: another device key, another purpose, a '
        'revoked device and another account are refused', () async {
      final trustB = registries[accountB.value]!.trustEpoch;
      Future<CommitChallenge> challenge() => server.requestRecoveryChallenge(
        cid,
        deviceIdHex: hex('b1'),
        epoch: server.epoch,
        trustEpoch: trustB,
      );
      Future<ConversationId> submit(CommitAuthorization a) =>
          server.recoverConversation(
            cid,
            deviceIdHex: hex('b1'),
            epoch: server.epoch,
            trustEpoch: trustB,
            authorization: a,
          );
      // Signed by B2's key, claimed as B1 (a session plus a stolen nonce).
      final c1 = await challenge();
      await expectLater(
        submit(recoverySigned('b2', accountB, c1, server.epoch, trustB)),
        throwsA(isA<TransportException>()),
      );
      // A commit-purpose proof over the right bytes is not a recovery.
      final c2 = await challenge();
      await expectLater(
        submit(
          recoverySigned(
            'b1',
            accountB,
            c2,
            server.epoch,
            trustB,
            purpose: DeviceProofPurpose.commit,
          ),
        ),
        throwsA(isA<TransportException>()),
      );
      expect(server.refusedRecoveries, 2);

      await DeviceTrustService(registries[accountA.value]!).revoke(
        core: cores['a1']!,
        account: accountA,
        deviceIdHex: hex('a2'),
        reason: RevocationReason.lost,
      );
      await expectLater(
        services['a2']!.recover(),
        matcher(MessagingFailure.deviceNotTrusted),
      );
      // Account switch: A1's core under B's account never signs.
      final switched = MessagingService(
        core: cores['a1']!,
        account: accountB,
        conversation: cid,
        transport: server,
        registry: registry,
      );
      await expectLater(switched.recover(), throwsA(isA<CryptoException>()));
      expect(server.retired, isFalse);
      expect(server.successorIdHex, isNull);
    });

    test('recovery is state-bound: a moved trust epoch or conversation '
        'epoch, and a replayed authorization, are refused', () async {
      final trustB = registries[accountB.value]!.trustEpoch;
      final stalled = server.epoch;
      final c1 = await server.requestRecoveryChallenge(
        cid,
        deviceIdHex: hex('b1'),
        epoch: stalled,
        trustEpoch: trustB,
      );
      final signedEarlier = recoverySigned('b1', accountB, c1, stalled, trustB);
      // B's trust moved (an approval, a revocation) since signing.
      registries[accountB.value]!.trustEpoch++;
      final trustNow = registries[accountB.value]!.trustEpoch;
      await expectLater(
        server.recoverConversation(
          cid,
          deviceIdHex: hex('b1'),
          epoch: stalled,
          trustEpoch: trustB,
          authorization: signedEarlier,
        ),
        throwsA(isA<TransportException>()),
      );
      // A commit moved the conversation since signing.
      final c2 = await server.requestRecoveryChallenge(
        cid,
        deviceIdHex: hex('b1'),
        epoch: stalled,
        trustEpoch: trustNow,
      );
      final staged = cores['b1']!.stageSelfUpdate(cid);
      expect(
        (await submitAs('b1', accountB, staged)).outcome,
        WriteOutcome.accepted,
      );
      await services['b1']!.sync();
      expect(server.epoch, stalled + 1);
      await expectLater(
        server.recoverConversation(
          cid,
          deviceIdHex: hex('b1'),
          epoch: stalled,
          trustEpoch: trustNow,
          authorization: recoverySigned('b1', accountB, c2, stalled, trustNow),
        ),
        throwsA(isA<TransportException>()),
      );
      expect(server.retired, isFalse);
      // A valid one succeeds once; its replay is refused.
      final epochNow = server.epoch;
      final c3 = await server.requestRecoveryChallenge(
        cid,
        deviceIdHex: hex('b1'),
        epoch: epochNow,
        trustEpoch: trustNow,
      );
      final good = recoverySigned('b1', accountB, c3, epochNow, trustNow);
      await server.recoverConversation(
        cid,
        deviceIdHex: hex('b1'),
        epoch: epochNow,
        trustEpoch: trustNow,
        authorization: good,
      );
      final first = server.successorIdHex;
      await expectLater(
        server.recoverConversation(
          cid,
          deviceIdHex: hex('b1'),
          epoch: epochNow,
          trustEpoch: trustNow,
          authorization: good,
        ),
        throwsA(isA<TransportException>()),
      );
      expect(server.successorIdHex, first);
    });

    test('a successor is followed only if it names this conversation and '
        'has the same members', () async {
      expect(await services['a1']!.successor(), isNull);
      final target = 'ab' * 16;
      server
        ..retired = true
        ..successorIdHex = target;
      final cidHex = EncryptedMessageEnvelope.hexOf(cid.bytes);
      for (final bad in [
        ConversationRecord(
          members: [accountA.value, 'accountMallory'],
          epoch: 0,
          active: true,
          predecessorIdHex: cidHex,
        ),
        ConversationRecord(
          members: [accountA.value, accountB.value],
          epoch: 0,
          active: true,
          predecessorIdHex: 'cd' * 16,
        ),
        ConversationRecord(
          members: [accountA.value, accountB.value],
          epoch: 0,
          active: true,
        ),
      ]) {
        server.others[target] = bad;
        await expectLater(
          services['a1']!.successor(),
          matcher(MessagingFailure.rejected),
        );
      }
      server.successorIdHex = 'not-hex';
      await expectLater(
        services['a1']!.successor(),
        matcher(MessagingFailure.rejected),
      );
    });

    test('logs carry events and categories only', () async {
      final sink = _Sink();
      AppLogger.configure(sinks: [sink], minimumLevel: LogLevel.debug);
      addTearDown(() => AppLogger.configure(sinks: const [DeveloperLogSink()]));
      await services['a1']!.sendText('very private words');
      await services['b1']!.sync();
      final all = sink.lines.join('\n');
      expect(all, contains('message_sent'));
      expect(all, isNot(contains('private')));
      for (final n in ['a1', 'b1']) {
        expect(all, isNot(contains(hex(n))));
      }
      for (final id in server.messageDocs.keys) {
        expect(all, isNot(contains(id)));
      }
    });
  }, skip: nativeSkip);
}

/// What `MessagingService._submit` sends, for tests that stage by hand.
CommitRecord _commit(StagedCommit s, String account, String deviceHex) =>
    CommitRecord(
      epoch: s.fromEpoch,
      senderAccountId: account,
      senderDeviceIdHex: deviceHex,
      commit: s.commit,
    );
