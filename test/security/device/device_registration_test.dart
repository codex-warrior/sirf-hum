// Client-side registration flow (Prompt 07 §9–11) with a fake registry and
// the real native core. Server-side verification (signature checks, replay,
// cloning) is tested in functions/test against the Firestore emulator.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sirf_hum/core/logging/app_logger.dart';
import 'package:sirf_hum/security/device/device_registration.dart';
import 'package:sirf_hum/security/device/device_status.dart';
import 'package:sirf_hum_crypto/sirf_hum_crypto.dart';

import 'device_test_support.dart';

class FakeRegistry implements DeviceRegistry {
  DeviceStatus serverStatus = DeviceStatus.unknown;
  final calls = <String>[];
  PendingDeviceRegistration? created;
  final issued = <ActivationChallenge>[];
  Uint8List? submittedProof;
  String? submittedChallengeId;
  DeviceRegistryException? failActivation;
  int _next = 0;

  @override
  Future<DeviceStatus> status(AccountId account, String deviceIdHex) async {
    calls.add('status');
    return serverStatus;
  }

  @override
  Future<void> createPending(PendingDeviceRegistration registration) async {
    calls.add('createPending');
    created = registration;
    serverStatus = DeviceStatus.pending;
  }

  @override
  Future<ActivationChallenge> requestActivationChallenge(
    AccountId account,
    String deviceIdHex,
  ) async {
    calls.add('challenge');
    _next++;
    final challenge = ActivationChallenge(
      challengeId: 'c$_next'.padRight(32, '0'),
      challenge: Uint8List.fromList(List.filled(32, _next)),
    );
    issued.add(challenge);
    return challenge;
  }

  @override
  Future<void> activate(
    AccountId account,
    String deviceIdHex,
    String challengeId,
    Uint8List proof,
  ) async {
    calls.add('activate');
    submittedChallengeId = challengeId;
    submittedProof = proof;
    final failure = failActivation;
    if (failure != null) throw failure;
    serverStatus = DeviceStatus.active;
  }
}

class CapturingSink implements LogSink {
  final records = <String>[];

  @override
  void write(LogRecord record) => records.add(record.message);
}

void main() {
  final account = AccountId('accountA');

  group('native', () {
    late Directory dir;
    late CryptoCore core;
    late FakeRegistry registry;

    setUp(() {
      dir = Directory.systemTemp.createTempSync('sh_reg_');
      core = CryptoCore.initializeWithPlatformKey(
        directory: dir.path,
        storeKey: Uint8List.fromList(List.filled(32, 9)),
      )..createIdentity(account);
      registry = FakeRegistry();
    });
    tearDown(() {
      core.close();
      dir.deleteSync(recursive: true);
    });

    Future<DeviceStatus> run() => DeviceRegistrationFlow(registry).ensureActive(
      core: core,
      account: account,
      platform: DevicePlatform.android,
    );

    test('new device: register pending, prove possession, active', () async {
      expect(await run(), DeviceStatus.active);
      expect(registry.calls, [
        'status',
        'createPending',
        'challenge',
        'activate',
      ]);
      final created = registry.created!;
      expect(created.deviceIdHex, hasLength(32));
      expect(created.certificate, core.publicIdentity().certificate);
      expect(registry.submittedProof, hasLength(64));
      expect(registry.submittedChallengeId, registry.issued.single.challengeId);
    });

    test('the proof is computed over the issued challenge', () async {
      await run();
      expect(
        registry.submittedProof,
        core.deviceProof(
          DeviceProofPurpose.activation,
          registry.issued.single.challenge,
        ),
      );
    });

    test('already active: no writes at all', () async {
      registry.serverStatus = DeviceStatus.active;
      expect(await run(), DeviceStatus.active);
      expect(registry.calls, ['status']);
    });

    test('revoked: terminal, never re-registered or re-activated', () async {
      registry.serverStatus = DeviceStatus.revoked;
      expect(await run(), DeviceStatus.revoked);
      expect(registry.calls, ['status']);
    });

    test(
      'pending (interrupted earlier): resumes with a NEW challenge',
      () async {
        registry.serverStatus = DeviceStatus.pending;
        expect(await run(), DeviceStatus.active);
        expect(registry.calls, ['status', 'challenge', 'activate']);
      },
    );

    test('a failed activation never reuses its challenge on retry', () async {
      registry.failActivation = const DeviceRegistryException(
        DeviceRegistryFailure.challengeExpired,
      );
      await expectLater(run(), throwsA(isA<DeviceRegistryException>()));
      registry.failActivation = null;
      expect(await run(), DeviceStatus.active);
      expect(registry.issued, hasLength(2));
      expect(
        registry.submittedChallengeId,
        isNot(registry.issued.first.challengeId),
      );
    });

    test(
      'refuses to register when the core belongs to another account',
      () async {
        await expectLater(
          DeviceRegistrationFlow(registry).ensureActive(
            core: core,
            account: AccountId('accountB'),
            platform: DevicePlatform.ios,
          ),
          throwsA(
            isA<CryptoException>().having(
              (e) => e.code,
              'code',
              CryptoErrorCode.accountMismatch,
            ),
          ),
        );
        expect(registry.calls, isEmpty, reason: 'nothing sent to the server');
      },
    );

    test(
      'logs carry only status categories, never identity material',
      () async {
        final sink = CapturingSink();
        AppLogger.configure(sinks: [sink], minimumLevel: LogLevel.debug);
        addTearDown(
          () => AppLogger.configure(
            sinks: const [DeveloperLogSink()],
            minimumLevel: LogLevel.debug,
          ),
        );
        await run();
        final logs = sink.records.join('\n');
        final secrets = [
          PendingDeviceRegistration.hexOf(core.publicIdentity().deviceId),
          base64Encode(registry.submittedProof!),
          base64Encode(core.publicIdentity().certificate),
          base64Encode(registry.issued.single.challenge),
          account.value,
        ];
        for (final s in secrets) {
          expect(logs, isNot(contains(s)));
        }
        expect(logs, contains('device_registration_status'));
      },
    );
  }, skip: nativeSkip);

  group('records', () {
    test('pending record validates the certificate size', () {
      final id = DeviceId(Uint8List(16));
      for (final bad in [Uint8List(0), Uint8List(513)]) {
        expect(
          () => PendingDeviceRegistration(
            accountId: account,
            deviceId: id,
            platform: DevicePlatform.android,
            certificate: bad,
          ),
          throwsA(isA<DeviceRegistryException>()),
        );
      }
    });

    test('device ID is lower-case hex, 32 characters', () {
      final id = DeviceId(Uint8List.fromList(List.generate(16, (i) => i * 17)));
      final hex = PendingDeviceRegistration.hexOf(id);
      expect(hex, '00112233445566778899aabbccddeeff');
      expect(RegExp(r'^[0-9a-f]{32}$').hasMatch(hex), isTrue);
    });

    test('challenges must be exactly 32 bytes', () {
      for (final len in [0, 31, 33]) {
        expect(
          () =>
              ActivationChallenge(challengeId: 'x', challenge: Uint8List(len)),
          throwsA(isA<DeviceRegistryException>()),
        );
      }
    });

    test('server failure categories map exactly; unknown is retryable', () {
      const expected = {
        'invalid_argument': DeviceRegistryFailure.invalidRecord,
        'unauthenticated': DeviceRegistryFailure.unauthenticated,
        'device_not_found': DeviceRegistryFailure.deviceNotFound,
        'device_not_pending': DeviceRegistryFailure.deviceNotPending,
        'challenge_invalid': DeviceRegistryFailure.challengeInvalid,
        'challenge_expired': DeviceRegistryFailure.challengeExpired,
        'proof_invalid': DeviceRegistryFailure.proofInvalid,
        'certificate_invalid': DeviceRegistryFailure.certificateInvalid,
        'duplicate_device': DeviceRegistryFailure.duplicateDevice,
      };
      expected.forEach((category, failure) {
        expect(DeviceRegistryFailure.fromServer(category), failure);
      });
      for (final other in [null, '', 'internal', 'ok']) {
        expect(
          DeviceRegistryFailure.fromServer(other),
          DeviceRegistryFailure.unavailable,
        );
      }
    });

    test('records and challenges print redacted', () {
      final r = PendingDeviceRegistration(
        accountId: account,
        deviceId: DeviceId(Uint8List(16)),
        platform: DevicePlatform.ios,
        certificate: Uint8List(10),
      );
      expect(r.toString(), contains('<redacted>'));
      expect(
        ActivationChallenge(
          challengeId: 'id',
          challenge: Uint8List(32),
        ).toString(),
        contains('<redacted>'),
      );
    });
  });
}
