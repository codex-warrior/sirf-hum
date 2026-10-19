// ABI v5 end to end through the real native library (CI: crypto-core job,
// SIRF_HUM_REQUIRE_NATIVE_CRYPTO=1). TEST ONLY: insecure test key stores.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:sirf_hum_crypto/sirf_hum_crypto.dart';
import 'package:test/test.dart';

final bool _required =
    Platform.environment['SIRF_HUM_REQUIRE_NATIVE_CRYPTO'] == '1';

Matcher _fails(CryptoErrorCode code) =>
    throwsA(isA<CryptoException>().having((e) => e.code, 'code', code));

Uint8List _bytes(String s) => Uint8List.fromList(utf8.encode(s));

class _Device {
  _Device(this.dir, String account) {
    core = CryptoCore.initialize(
      directory: dir.path,
      keyStore: KeyStoreKind.insecureTestFile,
    );
    public = core.createIdentity(AccountId(account));
  }

  final Directory dir;
  late CryptoCore core;
  late PublicIdentity public;

  void restart() {
    core.close();
    core = CryptoCore.initialize(
      directory: dir.path,
      keyStore: KeyStoreKind.insecureTestFile,
    );
  }

  ReceivedMessage receive(
    ConversationId c,
    _Device from,
    SentMessage m, {
    MessageId? messageId,
    DeviceId? sender,
    int? epoch,
    int protocolVersion = MessageVersions.protocol,
  }) => core.receiveMessage(
    c,
    messageId: messageId ?? m.messageId,
    sender: sender ?? from.public.deviceId,
    epoch: epoch ?? m.epoch,
    schemaVersion: MessageVersions.schema,
    protocolVersion: protocolVersion,
    ciphertext: m.ciphertext,
    serverTimeMs: 0,
  );
}

void main() {
  final available = CryptoCore.isAvailable;

  group(
    'messaging (ABI v5)',
    () {
      late Directory root;
      late _Device a;
      late _Device b;
      final cid = ConversationId(Uint8List.fromList(List.filled(16, 9)));

      setUp(() {
        root = Directory.systemTemp.createTempSync('sh_msg_test_');
        a = _Device(Directory('${root.path}/a')..createSync(), 'accountA');
        b = _Device(Directory('${root.path}/b')..createSync(), 'accountB');
        a.core.trustVerifiedPersonKey(b.public.personKey);
        b.core.trustVerifiedPersonKey(a.public.personKey);
        final staged = a.core.createConversationGroup(cid, [
          b.core.keyPackage(),
        ]);
        expect(staged.fromEpoch, 0);
        expect(a.core.epoch(GroupId(cid.bytes)), 0, reason: 'staged only');
        expect(a.core.confirmCommit(cid, 0), 1);
        expect(b.core.joinConversation(cid, staged.welcome!), 1);
      });

      tearDown(() {
        a.core.close();
        b.core.close();
        root.deleteSync(recursive: true);
      });

      test('text round trip with sealed history on both sides', () {
        final sent = a.core.sendMessage(cid, _bytes('hello'));
        final got = b.receive(cid, a, sent);
        expect(got.duplicate, isFalse);
        expect(got.payload, _bytes('hello'));
        expect(b.receive(cid, a, sent).duplicate, isTrue);
        a.core.markMessageSent(cid, sent.messageId, serverTimeMs: 77);
        a.restart();
        b.restart();
        final mine = a.core.history(cid).single;
        expect(mine.direction, MessageDirection.outgoing);
        expect(mine.state, MessageState.sent);
        expect(mine.serverTimeMs, 77);
        expect(mine.ciphertext, isNull);
        final theirs = b.core.history(cid).single;
        expect(theirs.payload, _bytes('hello'));
        expect(theirs.senderDeviceId, a.public.deviceId);
        b.core.deleteLocalMessage(cid, sent.messageId);
        expect(b.core.history(cid), isEmpty);
      });

      test('every routing field is authenticated', () {
        final sent = a.core.sendMessage(cid, _bytes('bound'));
        final otherId = MessageId(Uint8List.fromList(List.filled(16, 1)));
        expect(
          () => b.receive(cid, a, sent, messageId: otherId),
          _fails(CryptoErrorCode.envelopeMismatch),
        );
        expect(
          () => b.receive(cid, a, sent, sender: b.public.deviceId),
          _fails(CryptoErrorCode.envelopeMismatch),
        );
        expect(
          () => b.receive(cid, a, sent, protocolVersion: 2),
          _fails(CryptoErrorCode.envelopeMismatch),
        );
        expect(
          () => b.receive(cid, a, sent, epoch: sent.epoch + 1),
          _fails(CryptoErrorCode.envelopeMismatch),
        );
        final other = ConversationId(Uint8List.fromList(List.filled(16, 8)));
        expect(
          () => b.receive(other, a, sent),
          _fails(CryptoErrorCode.envelopeMismatch),
        );
        expect(b.receive(cid, a, sent).payload, _bytes('bound'));
      });

      test('staged commits: confirm, discard, conflicts, restart', () {
        final staged = a.core.stageSelfUpdate(cid);
        expect(a.core.stagedCommitEpoch(cid), 1);
        expect(
          () => a.core.sendMessage(cid, _bytes('x')),
          _fails(CryptoErrorCode.commitPending),
        );
        a.restart();
        expect(a.core.stagedCommitEpoch(cid), 1);
        expect(
          () => a.core.confirmCommit(cid, 0),
          _fails(CryptoErrorCode.noStagedCommit),
        );
        expect(a.core.confirmCommit(cid, 1), 2);
        expect(a.core.confirmCommit(cid, 1), 2, reason: 'idempotent');
        final applied = b.core.processCommit(
          cid,
          epoch: 1,
          sender: a.public.deviceId,
          commit: staged.commit,
        );
        expect(applied, isA<IncomingCommit>().having((c) => c.epoch, 'e', 2));
        final discarded = b.core.stageSelfUpdate(cid);
        b.core.discardCommit(cid, discarded.fromEpoch);
        expect(b.core.stagedCommitEpoch(cid), isNull);
        expect(
          () => b.core.confirmCommit(cid, discarded.fromEpoch),
          _fails(CryptoErrorCode.noStagedCommit),
        );
      });

      test(
        'future epochs wait; offline sends re-encrypt under the new one',
        () {
          final queued = a.core.sendMessage(cid, _bytes('offline'));
          final update = b.core.stageSelfUpdate(cid);
          b.core.confirmCommit(cid, 1);
          final ahead = b.core.sendMessage(cid, _bytes('ahead'));
          expect(
            () => a.receive(cid, b, ahead),
            _fails(CryptoErrorCode.futureEpoch),
          );
          a.core.processCommit(
            cid,
            epoch: 1,
            sender: b.public.deviceId,
            commit: update.commit,
          );
          expect(a.receive(cid, b, ahead).payload, _bytes('ahead'));
          expect(
            () => b.receive(cid, a, queued),
            _fails(CryptoErrorCode.staleEpoch),
            reason: 'the refused epoch-1 ciphertext never decrypts after',
          );
          final again = a.core.reencryptMessage(cid, queued.messageId);
          expect(again.epoch, 2);
          expect(again.messageId, queued.messageId);
          expect(b.receive(cid, a, again).payload, _bytes('offline'));
        },
      );

      test('revoked members block sending until removed', () {
        b.core.revokeDevice(a.public.deviceId);
        expect(
          () => b.core.sendMessage(cid, _bytes('x')),
          _fails(CryptoErrorCode.unauthorizedDevice),
        );
        final removal = b.core.stageRemoveMembers(cid, [a.public.deviceId]);
        expect(b.core.confirmCommit(cid, removal.fromEpoch), 2);
        expect(
          a.core.processCommit(
            cid,
            epoch: 1,
            sender: b.public.deviceId,
            commit: removal.commit,
          ),
          isA<IncomingRemoved>(),
        );
        expect(
          () => a.core.sendMessage(cid, _bytes('x')),
          _fails(CryptoErrorCode.unknownGroup),
        );
      });
    },
    skip: available
        ? false
        : (_required ? false : 'no native crypto core on this host'),
  );
}
