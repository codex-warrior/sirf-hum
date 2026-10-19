// Multi-device trust service (Prompt 08 §5, §9–12, §15–16): approval by a
// trusted device, rejection, revocation, recovery key, offline revocation,
// and secret-safe logging. Real native cores; fake registry (server
// signature checks are tested in functions/test).
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sirf_hum/core/logging/app_logger.dart';
import 'package:sirf_hum/security/device/device_registration.dart';
import 'package:sirf_hum/security/device/device_status.dart';
import 'package:sirf_hum/security/device/device_trust_service.dart';
import 'package:sirf_hum_crypto/sirf_hum_crypto.dart';

import 'device_test_support.dart';
import 'fake_registry.dart';

class _Sink implements LogSink {
  final records = <String>[];

  @override
  void write(LogRecord record) => records.add(record.message);
}

void main() {
  final account = AccountId('accountA');

  group('native', () {
    late Directory root;
    late FakeRegistry registry;
    late DeviceTrustService service;
    late CryptoCore a;
    late CryptoCore b;

    CryptoCore device(String name, int key) =>
        CryptoCore.initializeWithPlatformKey(
          directory: (Directory('${root.path}/$name')..createSync()).path,
          storeKey: Uint8List.fromList(List.filled(32, key)),
        )..createIdentity(account);

    String id(CryptoCore c) =>
        PendingDeviceRegistration.hexOf(c.publicIdentity().deviceId);

    Future<EnrollmentState> enroll(CryptoCore c) => DeviceRegistrationFlow(
      registry,
    ).enroll(core: c, account: account, platform: DevicePlatform.ios);

    setUp(() async {
      root = Directory.systemTemp.createTempSync('sh_trust_service_');
      registry = FakeRegistry();
      service = DeviceTrustService(registry);
      a = device('a', 21);
      b = device('b', 22);
      expect(await enroll(a), isA<EnrollmentActive>()); // first device
    });
    tearDown(() {
      a.close();
      b.close();
      root.deleteSync(recursive: true);
    });

    test('A approves B: both devices show the same comparison code', () async {
      final waiting = await enroll(b) as EnrollmentAwaitingApproval;
      final candidates = await service.pendingApprovals(
        core: a,
        account: account,
      );
      expect(candidates, hasLength(1));
      expect(
        candidates.single.code,
        waiting.code,
        reason: 'user compares these',
      );
      await service.approve(
        core: a,
        account: account,
        candidate: candidates.single,
      );
      expect(registry.statuses[id(b)], DeviceStatus.active);
      expect(registry.approvedBy[id(b)], id(a));
      expect(registry.submitted['approve'], hasLength(64));
      expect(await enroll(b), isA<EnrollmentActive>());
    });

    test('a device never lists or approves itself', () async {
      await enroll(b);
      final candidates = await service.pendingApprovals(
        core: a,
        account: account,
      );
      expect(
        candidates.map((c) => c.request.deviceIdHex),
        isNot(contains(id(a))),
      );
    });

    test('rejection is terminal for the rejected device', () async {
      await enroll(b);
      final candidate = (await service.pendingApprovals(
        core: a,
        account: account,
      )).single;
      await service.reject(account: account, candidate: candidate);
      expect(registry.statuses[id(b)], DeviceStatus.rejected);
      expect(await enroll(b), isA<EnrollmentTerminal>());
    });

    test('an untrusted (pending) device cannot list or approve', () async {
      await enroll(b);
      await expectLater(
        service.pendingApprovals(core: b, account: account),
        throwsA(
          isA<DeviceRegistryException>().having(
            (e) => e.failure,
            'failure',
            DeviceRegistryFailure.deviceNotTrusted,
          ),
        ),
      );
    });

    test(
      'offline revocation: A, revoked while offline, cannot approve after reconnecting',
      () async {
        await enroll(b);
        final candidate = (await service.pendingApprovals(
          core: a,
          account: account,
        )).single;
        registry.statuses[id(a)] =
            DeviceStatus.revoked; // revoked from elsewhere
        expect(
          await service.refreshStatus(core: a, account: account),
          DeviceStatus.revoked,
        );
        final before = registry.calls.length;
        await expectLater(
          service.approve(core: a, account: account, candidate: candidate),
          throwsA(
            isA<DeviceRegistryException>().having(
              (e) => e.failure,
              'failure',
              DeviceRegistryFailure.deviceNotTrusted,
            ),
          ),
        );
        expect(
          registry.calls.skip(before),
          isNot(contains('approve')),
          reason: 'nothing signed or sent',
        );
        expect(registry.statuses[id(b)], DeviceStatus.pending);
      },
    );

    test('revocation is one call and shows in the device list', () async {
      await service.revoke(account: account, deviceIdHex: id(a));
      final records = await service.devices(account);
      expect(
        records.singleWhere((r) => r.deviceIdHex == id(a)).status,
        DeviceStatus.revoked,
      );
    });

    test(
      'recovery: A creates a key; all devices lost; B recovers once',
      () async {
        final secret = await service.createRecoveryKey(
          core: a,
          account: account,
        );
        expect(secret, startsWith('SHRK1-'));
        expect(registry.recoveryPublicKey, hasLength(32));
        expect(registry.submitted['registerRecoveryKey'], hasLength(64));
        registry.statuses[id(a)] = DeviceStatus.revoked; // A lost
        final waiting = await enroll(b) as EnrollmentAwaitingApproval;
        await service.recover(
          core: b,
          account: account,
          enrollment: waiting,
          recoveryKey: secret,
        );
        expect(registry.statuses[id(b)], DeviceStatus.active);
        expect(registry.recoveryPublicKey, isNull, reason: 'single-use');
      },
    );

    test(
      'a typo in the recovery key fails locally, before anything is sent',
      () async {
        final secret = await service.createRecoveryKey(
          core: a,
          account: account,
        );
        final waiting = await enroll(b) as EnrollmentAwaitingApproval;
        final typo = secret.replaceRange(
          secret.length - 1,
          null,
          secret.endsWith('A') ? 'B' : 'A',
        );
        await expectLater(
          service.recover(
            core: b,
            account: account,
            enrollment: waiting,
            recoveryKey: typo,
          ),
          throwsA(
            isA<CryptoException>().having(
              (e) => e.code,
              'code',
              CryptoErrorCode.recoveryKeyInvalid,
            ),
          ),
        );
        expect(registry.calls, isNot(contains('recover')));
      },
    );

    test(
      'no recovery key registered: recovery is unavailable, not faked',
      () async {
        final waiting = await enroll(b) as EnrollmentAwaitingApproval;
        // A key that was never registered (made on an unrelated device).
        final stray = device(
          'stray',
          23,
        ).createRecoveryKey(challenge: Uint8List(32), expiresAtUnix: 1);
        await expectLater(
          service.recover(
            core: b,
            account: account,
            enrollment: waiting,
            recoveryKey: stray.secret,
          ),
          throwsA(
            isA<DeviceRegistryException>().having(
              (e) => e.failure,
              'failure',
              DeviceRegistryFailure.recoveryUnavailable,
            ),
          ),
        );
        expect(registry.statuses[id(b)], DeviceStatus.pending);
      },
    );

    test('the recovery key, signatures and codes are never logged', () async {
      final sink = _Sink();
      AppLogger.configure(sinks: [sink], minimumLevel: LogLevel.debug);
      addTearDown(
        () => AppLogger.configure(
          sinks: const [DeveloperLogSink()],
          minimumLevel: LogLevel.debug,
        ),
      );
      final secret = await service.createRecoveryKey(core: a, account: account);
      final waiting = await enroll(b) as EnrollmentAwaitingApproval;
      final candidate = (await service.pendingApprovals(
        core: a,
        account: account,
      )).single;
      await service.approve(core: a, account: account, candidate: candidate);
      final logs = sink.records.join('\n');
      final body = secret.replaceAll('-', '').substring(5);
      for (final chunk in [
        secret,
        body.substring(0, 12),
        id(a),
        id(b),
        waiting.request.requestId,
        waiting.code.toString().padLeft(6, '0'),
      ]) {
        expect(logs, isNot(contains(chunk)));
      }
      expect(logs, contains('recovery_key_created'));
      expect(logs, contains('device_approved'));
    });

    test('approval candidates and states print redacted', () async {
      final waiting = await enroll(b) as EnrollmentAwaitingApproval;
      expect(waiting.toString(), contains('<redacted>'));
      final candidate = (await service.pendingApprovals(
        core: a,
        account: account,
      )).single;
      expect(candidate.toString(), contains('<redacted>'));
      expect(candidate.request.toString(), contains('<redacted>'));
    });
  }, skip: nativeSkip);
}
