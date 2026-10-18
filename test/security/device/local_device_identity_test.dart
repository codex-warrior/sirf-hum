// Local device identity (Prompt 07 §3, §12, §13) through the real native
// crypto core, with an in-memory stand-in for the platform key store.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sirf_hum/security/device/local_device_identity.dart';
import 'package:sirf_hum_crypto/sirf_hum_crypto.dart';

import 'device_test_support.dart';

void main() {
  late Directory root;
  late FakeDeviceKeyStore keys;
  late LocalDeviceIdentityService service;
  final accountA = AccountId('accountA');
  final accountB = AccountId('accountB');

  setUp(() {
    root = Directory.systemTemp.createTempSync('sh_identity_');
    keys = FakeDeviceKeyStore(root);
    service = LocalDeviceIdentityService(keyStore: keys, isWeb: false);
  });
  tearDown(() => root.deleteSync(recursive: true));

  Future<LocalIdentityReady> ready(AccountId account) async {
    final result = await service.open(account);
    expect(result, isA<LocalIdentityReady>());
    return result as LocalIdentityReady;
  }

  group('native', () {
    test('first open creates an identity; later opens restore it', () async {
      final first = await ready(accountA);
      expect(first.created, isTrue);
      final id = first.identity.deviceId;
      first.core.close();

      final again = await ready(accountA);
      expect(again.created, isFalse);
      expect(again.identity.deviceId, id);
      again.core.close();
    });

    test('device IDs are random, 16 bytes, and differ per account', () async {
      final a = await ready(accountA);
      final b = await ready(accountB);
      expect(a.identity.deviceId.bytes, hasLength(16));
      expect(a.identity.deviceId, isNot(b.identity.deviceId));
      expect(a.identity.personKey, isNot(b.identity.personKey));
      a.core.close();
      b.core.close();
    });

    test('account switch never reuses another account identity', () async {
      final a = await ready(accountA);
      final aId = a.identity.deviceId;
      a.core.close(); // "log out" of A: nothing is deleted
      final b = await ready(accountB); // "log in" as B
      expect(b.identity.deviceId, isNot(aId));
      expect(
        () => b.core.checkAccount(accountA),
        throwsA(
          isA<CryptoException>().having(
            (e) => e.code,
            'code',
            CryptoErrorCode.accountMismatch,
          ),
        ),
      );
      b.core.close();
      // Back to A: A's own identity, unchanged.
      final a2 = await ready(accountA);
      expect(a2.identity.deviceId, aId);
      a2.core.close();
    });

    test(
      'a slot holding another account identity is reported, not used',
      () async {
        (await ready(accountA)).core.close();
        // Simulate a misplaced slot: B's slot gets A's state and key.
        Directory('${root.path}/accountA').renameSync('${root.path}/accountB');
        keys.keys['accountB'] = keys.keys.remove('accountA')!;
        final result = await service.open(accountB);
        expect(
          result,
          isA<LocalIdentityCorrupted>().having(
            (r) => r.reason,
            'reason',
            LocalIdentityCorruptionReason.accountMismatch,
          ),
        );
      },
    );

    test('corrupted state is detected and never silently replaced', () async {
      (await ready(accountA)).core.close();
      final record = File('${root.path}/accountA/mls_state.shrec');
      final bytes = record.readAsBytesSync()..[40] ^= 0xff;
      record.writeAsBytesSync(bytes);
      final result = await service.open(accountA);
      expect(
        result,
        isA<LocalIdentityCorrupted>().having(
          (r) => r.reason,
          'reason',
          LocalIdentityCorruptionReason.undecryptable,
        ),
      );
      // The damaged state is still there: no automatic wipe.
      expect(record.existsSync(), isTrue);
    });

    test(
      'state without its key (lost or cloned elsewhere) fails closed',
      () async {
        (await ready(accountA)).core.close();
        keys.keys.remove('accountA');
        expect(await service.open(accountA), isA<LocalIdentityCorrupted>());
      },
    );

    test(
      'partial write: a leftover temp file does not break the state',
      () async {
        final first = await ready(accountA);
        final id = first.identity.deviceId;
        first.core.close();
        File(
          '${root.path}/accountA/.mls_state.shrec.tmp',
        ).writeAsBytesSync([1, 2, 3]);
        final again = await ready(accountA);
        expect(again.identity.deviceId, id);
        again.core.close();
      },
    );

    test('a stale key without state (iOS reinstall) is rotated', () async {
      // Keychain item survived, app data did not.
      await keys.storeKey('accountA', create: true);
      final createdBefore = keys.created;
      final result = await ready(accountA);
      expect(result.created, isTrue);
      expect(
        keys.created,
        createdBefore + 1,
        reason: 'fresh key for new identity',
      );
      result.core.close();
    });

    test(
      'remove account deletes key then state; next open is a NEW device',
      () async {
        final first = await ready(accountA);
        final oldId = first.identity.deviceId;
        first.core.close();
        await service.removeAccount(accountA);
        expect(keys.keys.containsKey('accountA'), isFalse);
        expect(Directory('${root.path}/accountA').existsSync(), isFalse);
        final fresh = await ready(accountA);
        expect(fresh.created, isTrue);
        expect(fresh.identity.deviceId, isNot(oldId));
        fresh.core.close();
      },
    );

    test('every store key handed out is wiped after use', () async {
      (await ready(accountA)).core.close();
      (await ready(accountA)).core.close();
      expect(keys.handedOut, isNotEmpty);
      for (final key in keys.handedOut) {
        expect(key.every((b) => b == 0), isTrue);
      }
    });
  }, skip: nativeSkip);

  group('platform limits', () {
    test('Web never gets a device identity', () async {
      final web = LocalDeviceIdentityService(keyStore: keys, isWeb: true);
      expect(
        await web.open(accountA),
        isA<LocalIdentityUnavailable>().having(
          (r) => r.reason,
          'reason',
          LocalIdentityUnavailableReason.web,
        ),
      );
    });

    test(
      'no platform key store: unavailable, never an unprotected fallback',
      () async {
        keys.isSupported = false;
        expect(
          await service.open(accountA),
          isA<LocalIdentityUnavailable>().having(
            (r) => r.reason,
            'reason',
            LocalIdentityUnavailableReason.noKeyStore,
          ),
        );
      },
    );

    test('no native core: unavailable', () async {
      final noCore = LocalDeviceIdentityService(
        keyStore: keys,
        isWeb: false,
        nativeAvailable: () => false,
      );
      expect(
        await noCore.open(accountA),
        isA<LocalIdentityUnavailable>().having(
          (r) => r.reason,
          'reason',
          LocalIdentityUnavailableReason.noNativeCore,
        ),
      );
    });

    test('account IDs that cannot name a slot are rejected', () {
      for (final bad in ['../evil', 'a/b', 'with space', 'é']) {
        expect(
          () => LocalDeviceIdentityService.slotFor(AccountId(bad)),
          throwsA(isA<InvalidAccountSlotException>()),
        );
      }
      expect(LocalDeviceIdentityService.slotFor(accountA), 'accountA');
    });
  });
}
