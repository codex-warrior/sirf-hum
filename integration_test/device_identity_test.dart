import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:sirf_hum/platform/secure_key_store.dart';
import 'package:sirf_hum/security/device/local_device_identity.dart';
import 'package:sirf_hum_crypto/sirf_hum_crypto.dart';

/// Device identity on a real device (Android emulator / iOS simulator in CI)
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
}
