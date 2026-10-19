import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:sirf_hum/platform/secure_key_store.dart';
import 'package:sirf_hum/security/device/local_device_identity.dart';
import 'package:sirf_hum_crypto/sirf_hum_crypto.dart';

/// Device identity on a real device (Android emulator in CI)
/// with the REAL platform key store: Android Keystore-wrapped / iOS Keychain
/// store keys. Uses throwaway test account IDs; every slot is removed again.
/// Run: `flutter test integration_test/device_identity_test.dart -d <device>`.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  const keyStore = PlatformSecureKeyStore();
  final service = LocalDeviceIdentityService(keyStore: keyStore);
  final accountA = AccountId('itDeviceAccountA');
  final accountB = AccountId('itDeviceAccountB');

  setUp(() async {
    await service.removeAccount(accountA);
    await service.removeAccount(accountB);
  });
  tearDown(() async {
    await service.removeAccount(accountA);
    await service.removeAccount(accountB);
  });

  Future<LocalIdentityReady> ready(AccountId account) async {
    final result = await service.open(account);
    expect(result, isA<LocalIdentityReady>(), reason: '$result');
    return result as LocalIdentityReady;
  }

  test('platform key store is available and keys are 32 bytes', () async {
    expect(keyStore.isSupported, isTrue);
    expect(await keyStore.storeKey('itProbe', create: false), isNull);
    final key = (await keyStore.storeKey('itProbe', create: true))!;
    expect(key, hasLength(32));
    expect(key.any((b) => b != 0), isTrue);
    final again = await keyStore.storeKey('itProbe', create: false);
    expect(again, key, reason: 'the same key is returned until replaced');
    await keyStore.removeSlot('itProbe');
    expect(await keyStore.storeKey('itProbe', create: false), isNull);
  });

  test('identity persists across reopen with the platform key', () async {
    final first = await ready(accountA);
    expect(first.created, isTrue);
    final id = first.identity.deviceId;
    first.core.close();
    final again = await ready(accountA);
    expect(again.created, isFalse);
    expect(again.identity.deviceId, id);
    expect(
      again.core.deviceProof(DeviceProofPurpose.activation, Uint8List(32)),
      hasLength(64),
    );
    again.core.close();
  });

  test('accounts are isolated on one device', () async {
    final a = await ready(accountA);
    final b = await ready(accountB);
    expect(a.identity.deviceId, isNot(b.identity.deviceId));
    a.core.close();
    b.core.close();
  });

  test(
    'removing an account destroys its identity (new device next time)',
    () async {
      final first = await ready(accountA);
      final id = first.identity.deviceId;
      first.core.close();
      await service.removeAccount(accountA);
      final fresh = await ready(accountA);
      expect(fresh.created, isTrue);
      expect(fresh.identity.deviceId, isNot(id));
      fresh.core.close();
    },
  );

  test('state without its platform key fails closed', () async {
    (await ready(accountA)).core.close();
    // Replace the key: the sealed state can no longer be opened.
    await keyStore.storeKey(
      LocalDeviceIdentityService.slotFor(accountA),
      create: true,
    );
    expect(await service.open(accountA), isA<LocalIdentityCorrupted>());
  });

  test(
    'multi-device trust ops run natively with platform keys (Prompt 08)',
    () async {
      final a = await ready(accountA);
      // A second device of the SAME account, in its own slot with its own
      // platform key (on one phone only for this test).
      const slot = 'itSecondDevice';
      final dir = await keyStore.slotDirectory(slot);
      final key = (await keyStore.storeKey(slot, create: true))!;
      final b = CryptoCore.initializeWithPlatformKey(
        directory: dir,
        storeKey: key,
      )..createIdentity(accountA);
      addTearDown(() async {
        b.close();
        await keyStore.removeSlot(slot);
      });
      final challenge = Uint8List.fromList(List.filled(32, 3));
      final certB = b.publicIdentity().certificate;
      expect(a.identity.personKey, isNot(b.publicIdentity().personKey));
      final approval = a.core.approveDevice(
        newCertificate: certB,
        challenge: challenge,
        expiresAtUnix: 1900000000,
      );
      expect(approval, hasLength(64));
      expect(
        CryptoCore.approvalCode(newCertificate: certB, challenge: challenge),
        inInclusiveRange(0, 999999),
      );
      final bundle = a.core.createRecoveryKey(
        challenge: challenge,
        expiresAtUnix: 1900000000,
      );
      expect(bundle.secret, startsWith('SHRK1-'));
      final recovered = b.recoveryApproval(
        recoveryKey: bundle.secret,
        challenge: challenge,
        expiresAtUnix: 1900000000,
      );
      expect(recovered.recoveryPublicKey, bundle.publicKey);
      a.core.close();
    },
  );
  test(
    'revocation, trust epoch and lineage run natively (Prompt 09)',
    () async {
      final a = await ready(accountA);
      const slot = 'itSecondDevice';
      final dir = await keyStore.slotDirectory(slot);
      final key = (await keyStore.storeKey(slot, create: true))!;
      final b = CryptoCore.initializeWithPlatformKey(
        directory: dir,
        storeKey: key,
      )..createIdentity(accountA);
      addTearDown(() async {
        b.close();
        await keyStore.removeSlot(slot);
      });
      Uint8List bytes(int v) => Uint8List.fromList(List.filled(32, v));
      final certA = a.identity.certificate;
      final certB = b.publicIdentity().certificate;
      final approval = a.core.approveDevice(
        newCertificate: certB,
        challenge: bytes(1),
        expiresAtUnix: 1900000000,
      );
      final revocation = a.core.signRevocation(
        revokedCertificate: certB,
        reason: RevocationReason.lost,
        challenge: bytes(2),
        expiresAtUnix: 1900000000,
      );
      expect(revocation, hasLength(64));
      expect(
        b.signResetCancellation(challenge: bytes(3), expiresAtUnix: 1900000000),
        hasLength(64),
      );
      final chain = LineageRequest(
        accountId: accountA.value,
        rootCertificate: certA,
        links: [
          ApprovalLink(
            approverCertificate: certA,
            newCertificate: certB,
            challenge: bytes(1),
            expiresAtUnix: 1900000000,
            signature: approval,
          ),
        ],
      );
      expect(CryptoCore.verifyLineage(chain), hasLength(2));
      final revoked = LineageRequest(
        accountId: accountA.value,
        rootCertificate: certA,
        links: chain.links,
        revocations: [
          SignedRevocation(
            revokerCertificate: certA,
            revokedCertificate: certB,
            reason: RevocationReason.lost.wireValue,
            challenge: bytes(2),
            expiresAtUnix: 1900000000,
            signature: revocation,
          ),
        ],
      );
      expect(CryptoCore.verifyLineage(revoked).map((d) => d.bytes), [
        a.identity.deviceId.bytes,
      ]);
      // The epoch survives a restart under the platform key (D-083).
      a.core.observeTrustEpoch(5);
      a.core.close();
      final again = await ready(accountA);
      expect(again.core.observeTrustEpoch(5), 5);
      expect(
        () => again.core.observeTrustEpoch(4),
        throwsA(
          isA<CryptoException>().having(
            (e) => e.code,
            'code',
            CryptoErrorCode.trustStateStale,
          ),
        ),
      );
      again.core.close();
    },
  );
}
