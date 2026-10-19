import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:sirf_hum/platform/secure_key_store.dart';
import 'package:sirf_hum/security/device/local_device_identity.dart';
import 'package:sirf_hum_crypto/sirf_hum_crypto.dart';

/// The ABI v5 messaging core on a real device (Android emulator in CI) with
/// the REAL platform key store: two accounts' device identities in their own
/// Keystore-protected slots, a staged
/// conversation group, authenticated messages and sealed history that
/// survives reopening. Throwaway account IDs; slots are removed again.
/// Run: `flutter test integration_test/messaging_test.dart -d <device>`.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  const keyStore = PlatformSecureKeyStore();
  final service = LocalDeviceIdentityService(keyStore: keyStore);
  final accountA = AccountId('itMessagingA');
  final accountB = AccountId('itMessagingB');
  final cid = ConversationId(Uint8List.fromList(List.filled(16, 0x77)));

  Future<void> clean() async {
    await service.removeAccount(accountA);
    await service.removeAccount(accountB);
  }

  setUp(clean);
  tearDown(clean);

  Future<CryptoCore> open(AccountId account) async {
    final result = await service.open(account);
    expect(result, isA<LocalIdentityReady>(), reason: '$result');
    return (result as LocalIdentityReady).core;
  }

  test(
    'conversation, messages and sealed history with the platform key store',
    () async {
      final a = await open(accountA);
      final b = await open(accountB);
      a.trustVerifiedPersonKey(b.publicIdentity().personKey);
      b.trustVerifiedPersonKey(a.publicIdentity().personKey);

      final staged = a.createConversationGroup(cid, [b.keyPackage()]);
      expect(a.epoch(GroupId(cid.bytes)), 0, reason: 'staged, not active');
      expect(a.confirmCommit(cid, staged.fromEpoch), 1);
      expect(b.joinConversation(cid, staged.welcome!), 1);

      final sent = a.sendMessage(
        cid,
        Uint8List.fromList(utf8.encode('on a real device')),
      );
      ReceivedMessage receive(SentMessage m, {MessageId? id}) =>
          b.receiveMessage(
            cid,
            messageId: id ?? m.messageId,
            sender: a.publicIdentity().deviceId,
            epoch: m.epoch,
            schemaVersion: MessageVersions.schema,
            protocolVersion: MessageVersions.protocol,
            ciphertext: m.ciphertext,
            serverTimeMs: 1,
          );
      expect(
        () => receive(sent, id: MessageId(Uint8List(16))),
        throwsA(
          isA<CryptoException>().having(
            (e) => e.code,
            'code',
            CryptoErrorCode.envelopeMismatch,
          ),
        ),
      );
      expect(utf8.decode(receive(sent).payload), 'on a real device');

      // Reopen both slots: history is sealed under each platform key.
      a.close();
      b.close();
      final a2 = await open(accountA);
      final b2 = await open(accountB);
      expect(a2.history(cid).single.direction, MessageDirection.outgoing);
      expect(utf8.decode(b2.history(cid).single.payload), 'on a real device');

      // Timing baseline on this device (reported, not asserted).
      final text = Uint8List.fromList(utf8.encode('x' * 1024));
      final clock = Stopwatch()..start();
      final batch = [for (var i = 0; i < 20; i++) a2.sendMessage(cid, text)];
      final encryptMs = clock.elapsedMilliseconds / batch.length;
      clock.reset();
      for (final m in batch) {
        b2.receiveMessage(
          cid,
          messageId: m.messageId,
          sender: a2.publicIdentity().deviceId,
          epoch: m.epoch,
          schemaVersion: MessageVersions.schema,
          protocolVersion: MessageVersions.protocol,
          ciphertext: m.ciphertext,
          serverTimeMs: 2,
        );
      }
      final decryptMs = clock.elapsedMilliseconds / batch.length;
      clock.reset();
      final loaded = b2.history(cid).length;
      debugPrint(
        'messaging_baseline encrypt_ms=$encryptMs decrypt_ms=$decryptMs '
        'history_records=$loaded history_ms=${clock.elapsedMilliseconds}',
      );
      a2.close();
      b2.close();
    },
  );
}
