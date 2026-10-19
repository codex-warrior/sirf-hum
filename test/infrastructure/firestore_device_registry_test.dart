import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sirf_hum/infrastructure/firebase/firestore_device_registry.dart';
import 'package:sirf_hum/security/device/device_registration.dart';
import 'package:sirf_hum_crypto/sirf_hum_crypto.dart';

void main() {
  final registration = PendingDeviceRegistration(
    accountId: AccountId('accountA'),
    deviceId: DeviceId(Uint8List(16)),
    platform: DevicePlatform.ios,
    certificate: Uint8List.fromList(List.filled(185, 1)),
  );

  test('registration sends exactly what registerDevice reads', () {
    // Prompt 08: the server writes the pending record itself; the client
    // sends only these three inputs (functions/src/device/registration.ts).
    final payload = FirestoreDeviceRegistry.registrationPayload(registration);
    expect(payload.keys.toSet(), {'deviceId', 'platform', 'certificate'});
    final server = File(
      'functions/src/device/registration.ts',
    ).readAsStringSync();
    for (final key in payload.keys) {
      expect(server, contains('args.$key'), reason: 'server reads $key');
    }
    expect(payload['deviceId'], registration.deviceIdHex);
    expect(payload['platform'], 'ios');
    expect(
      base64Decode(payload['certificate']! as String),
      registration.certificate,
    );
  });

  test('revocation sends exactly what revokeDevice reads (D-081)', () {
    final payload = FirestoreDeviceRegistry.revocationPayload(
      revokerDeviceIdHex: 'a' * 32,
      deviceIdHex: 'b' * 32,
      reason: RevocationReason.stolen,
      challengeId: 'c' * 32,
      signature: Uint8List(64),
    );
    final server = File(
      'functions/src/device/revocation.ts',
    ).readAsStringSync();
    for (final key in payload.keys) {
      expect(server, contains('args.$key'), reason: 'server reads $key');
    }
    expect(payload['reason'], 3);
  });

  test('the rules deny every client write to device records', () {
    final rules = File('firebase/firestore.rules').readAsStringSync();
    final devices = RegExp(
      r'match /users/\{accountId\}/devices/\{deviceId\} \{([^}]*)\}',
    ).firstMatch(rules)!.group(1)!;
    expect(devices, contains('allow write: if false'));
    expect(devices, isNot(contains('allow update')));
  });

  group('trust state parsing', () {
    test('absent document: no trust yet', () {
      expect(FirestoreDeviceRegistry.trustStateFrom(null).trustEpoch, 0);
    });

    test('pending reset and epochs', () {
      final s = FirestoreDeviceRegistry.trustStateFrom({
        'trustEpoch': 7,
        'identityEpoch': 1,
        'reset': {'status': 'pending', 'effectiveAtMillis': 1000},
      });
      expect(s.trustEpoch, 7);
      expect(s.identityEpoch, 1);
      expect(s.resetEffectiveAt, DateTime.utc(1970, 1, 1, 0, 0, 1));
    });

    test('a malformed epoch fails closed', () {
      for (final bad in [null, -1, '3', 1.5]) {
        expect(
          () => FirestoreDeviceRegistry.trustStateFrom({'trustEpoch': bad}),
          throwsA(isA<DeviceRegistryException>()),
          reason: '$bad',
        );
      }
    });
  });

  group('lineage from stored evidence (D-084)', () {
    final account = AccountId('accountA');
    Uint8List b(int v, [int n = 8]) => Uint8List.fromList(List.filled(n, v));
    Map<String, Object?> approval(int approver) => {
      'protocolVersion': 1,
      'approverCertificate': b(approver),
      'challenge': b(9, 32),
      'expiresAtUnix': 5,
      'signature': b(8, 64),
    };
    final idA = '11' * 16;
    final idB = '22' * 16;
    final idC = '33' * 16;
    final idOld = '44' * 16;

    Map<String, Map<String, Object?>> records() => {
      // C was approved by B after B: insertion order must not matter.
      idC: {
        'status': 'active',
        'certificate': b(3),
        'activationMethod': 'approval',
        'activatedEpoch': 7,
        'approval': approval(2),
      },
      idB: {
        'status': 'revoked',
        'certificate': b(2),
        'activationMethod': 'approval',
        'activatedEpoch': 6,
        'revokedEpoch': 8,
        'approval': approval(1),
        'revocation': {
          'protocolVersion': 1,
          'authority': 'device',
          'revokerCertificate': b(1),
          'reason': 3,
          'challenge': b(7, 32),
          'expiresAtUnix': 5,
          'signature': b(6, 64),
        },
      },
      idA: {
        'status': 'active',
        'certificate': b(1),
        'activationMethod': 'first_device',
        'activatedEpoch': 5,
      },
      // A device from before an identity reset.
      idOld: {
        'status': 'revoked',
        'certificate': b(4),
        'activationMethod': 'first_device',
        'activatedEpoch': 1,
        'revokedEpoch': 4,
        'revocation': {'authority': 'identity_reset'},
      },
    };

    LineageRequest? build(Map<String, Map<String, Object?>> r) =>
        FirestoreDeviceRegistry.lineageFrom(
          account: account,
          trust: {'trustEpoch': 8, 'firstDeviceId': idA},
          records: r,
        );

    test('root, links in activation order, signed revocations', () {
      final req = build(records())!;
      expect(req.rootCertificate, b(1));
      expect(req.links.map((l) => (l as ApprovalLink).newCertificate), [
        b(2),
        b(3),
      ]);
      expect(req.revocations.single.revokedCertificate, b(2));
      expect(req.revocations.single.reason, 3);
      expect(req.revokedDeviceIds, isEmpty, reason: 'old identity excluded');
    });

    test('Firestore Blob values parse like bytes', () {
      final r = records();
      r[idA]!['certificate'] = Blob(b(1));
      expect(build(r)!.rootCertificate, b(1));
    });

    test('no current identity: no lineage', () {
      expect(
        FirestoreDeviceRegistry.lineageFrom(
          account: account,
          trust: {
            'trustEpoch': 4,
            'bootstrapOpen': true,
            'firstDeviceId': idOld,
          },
          records: records(),
        ),
        isNull,
      );
      expect(
        FirestoreDeviceRegistry.lineageFrom(
          account: account,
          trust: null,
          records: const {},
        ),
        isNull,
      );
    });

    test(
      'missing or malformed evidence fails closed, never a shorter chain',
      () {
        for (final mutate in <void Function(Map<String, Map<String, Object?>>)>[
          (r) => r[idC]!.remove('approval'),
          (r) => r[idC]!['activationMethod'] = 'magic',
          (r) => (r[idC]!['approval']! as Map)['signature'] = 'not bytes',
          (r) => r.remove(idA),
          (r) => r[idA]!.remove('activatedEpoch'),
          (r) => (r[idB]!['revocation']! as Map).remove('signature'),
        ]) {
          final r = records();
          mutate(r);
          expect(
            () => build(r),
            throwsA(
              isA<DeviceRegistryException>().having(
                (e) => e.failure,
                'failure',
                DeviceRegistryFailure.unexpectedState,
              ),
            ),
          );
        }
      },
    );
  });

  test('implementation string matches the crypto core', () {
    expect(PendingDeviceRegistration.implementation, 'openmls/0.9.1');
  });
}
