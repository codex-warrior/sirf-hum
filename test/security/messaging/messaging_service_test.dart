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
import 'package:sirf_hum/security/messaging/conversation_transport.dart';
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

    setUp(() async {
      root = Directory.systemTemp.createTempSync('sh_messaging_');
      registries = {
        accountA.value: FakeRegistry(),
        accountB.value: FakeRegistry(),
      };
      registry = _Registries(registries);
      server = FakeTransport(
        members: [accountA.value, accountB.value],
        statusOf: (account, device) =>
            registries[account]?.statuses[device] ?? DeviceStatus.unknown,
      );
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
        await server.submitCommit(
          cid,
          _commit(staged, accountB.value, hex('b1')),
          const [],
        );
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
        expect(
          (await server.submitCommit(
            cid,
            _commit(a1Staged, accountA.value, hex('a1')),
            const [],
          )).outcome,
          WriteOutcome.refused,
          reason: 'epoch 1 already has a commit',
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
        final result = await server.submitCommit(
          cid,
          _commit(staged, accountA.value, hex('a1')),
          const [],
        );
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
