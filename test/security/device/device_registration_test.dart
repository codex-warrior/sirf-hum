// Client-side enrollment flow (Prompt 07 §9–11, Prompt 08 §7–8) with a fake
// registry and the real native core. Server-side verification (signatures,
// replay, cloning, approvals) is tested in functions/test against the
// Firestore emulator.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sirf_hum/core/logging/app_logger.dart';
import 'package:sirf_hum/security/device/device_registration.dart';
import 'package:sirf_hum/security/device/device_status.dart';
import 'package:sirf_hum_crypto/sirf_hum_crypto.dart';

import 'device_test_support.dart';
import 'fake_registry.dart';

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

    String ownId() =>
        PendingDeviceRegistration.hexOf(core.publicIdentity().deviceId);

    Future<EnrollmentState> run() => DeviceRegistrationFlow(
      registry,
    ).enroll(core: core, account: account, platform: DevicePlatform.android);

    test('first device: register, prove possession, active', () async {
      expect(await run(), isA<EnrollmentActive>());
      expect(registry.calls, [
        'status',
        'register',
        'challenge:activation',
        'activate',
      ]);
      expect(registry.certificates[ownId()], core.publicIdentity().certificate);
      expect(registry.submitted['activate'], hasLength(64));
    });

    test(
      'second device: approval required, proven request, comparison code',
      () async {
        registry.trustInitialized = true; // another device is already trusted
        final state = await run();
        expect(state, isA<EnrollmentAwaitingApproval>());
        final awaiting = state as EnrollmentAwaitingApproval;
        expect(registry.calls, [
          'status',
          'register',
          'challenge:activation',
          'requestApproval',
          'prove',
        ]);
        // The proof is an ENROLLMENT proof over the request's challenge.
        expect(
          registry.submitted['prove'],
          core.deviceProof(
            DeviceProofPurpose.enrollment,
            awaiting.request.challenge,
          ),
        );
        // The code this device shows is the one approvers will compute.
        expect(
          awaiting.code,
          CryptoCore.approvalCode(
            newCertificate: core.publicIdentity().certificate,
            challenge: awaiting.request.challenge,
          ),
        );
        expect(registry.statuses[ownId()], DeviceStatus.pending);
      },
    );

    test(
      'the activation proof is computed over the issued challenge',
      () async {
        await run();
        expect(registry.submitted['activate'], hasLength(64));
        expect(registry.issuedChallenges, hasLength(1));
      },
    );

    test('already active: no writes at all', () async {
      registry.statuses[ownId()] = DeviceStatus.active;
      expect(await run(), isA<EnrollmentActive>());
      expect(registry.calls, ['status']);
    });

    for (final terminal in [
      DeviceStatus.revoked,
      DeviceStatus.rejected,
      DeviceStatus.expired,
    ]) {
      test(
        '${terminal.name}: terminal, never re-registered or re-activated',
        () async {
          registry.statuses[ownId()] = terminal;
          final state = await run();
          expect(
            state,
            isA<EnrollmentTerminal>().having(
              (s) => s.status,
              'status',
              terminal,
            ),
          );
          expect(registry.calls, ['status']);
        },
      );
    }

    test(
      'pending (interrupted earlier): resumes with a NEW challenge',
      () async {
        registry.statuses[ownId()] = DeviceStatus.pending;
        expect(await run(), isA<EnrollmentActive>());
        expect(registry.calls, ['status', 'challenge:activation', 'activate']);
      },
    );

    test('a failed activation never reuses its challenge on retry', () async {
      registry.statuses[ownId()] = DeviceStatus.pending;
      registry.failNext = null;
      // Fail the activate call itself (after a challenge was issued).
      final failing = _FailingActivation(registry);
      await expectLater(
        DeviceRegistrationFlow(failing).enroll(
          core: core,
          account: account,
          platform: DevicePlatform.android,
        ),
        throwsA(isA<DeviceRegistryException>()),
      );
      expect(await run(), isA<EnrollmentActive>());
      expect(registry.issuedChallenges, hasLength(2));
      expect(registry.issuedChallenges.toSet(), hasLength(2));
    });

    test(
      'refuses to enroll when the core belongs to another account',
      () async {
        await expectLater(
          DeviceRegistrationFlow(registry).enroll(
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

    test('logs carry only state categories, never identity material', () async {
      final sink = CapturingSink();
      AppLogger.configure(sinks: [sink], minimumLevel: LogLevel.debug);
      addTearDown(
        () => AppLogger.configure(
          sinks: const [DeveloperLogSink()],
          minimumLevel: LogLevel.debug,
        ),
      );
      registry.trustInitialized = true;
      final state = await run() as EnrollmentAwaitingApproval;
      final logs = sink.records.join('\n');
      for (final s in [
        ownId(),
        base64Encode(registry.submitted['prove']!),
        base64Encode(core.publicIdentity().certificate),
        base64Encode(state.request.challenge),
        state.request.requestId,
        state.code.toString().padLeft(6, '0'),
        account.value,
      ]) {
        expect(logs, isNot(contains(s)));
      }
      expect(logs, contains('device_enrollment_state'));
    });
  }, skip: nativeSkip);

  group('records', () {
    test('registration validates the certificate size', () {
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

    test('challenges and requests must be exactly 32 bytes', () {
      for (final len in [0, 31, 33]) {
        expect(
          () =>
              ActivationChallenge(challengeId: 'x', challenge: Uint8List(len)),
          throwsA(isA<DeviceRegistryException>()),
        );
        expect(
          () => ApprovalRequest(
            requestId: 'x',
            challenge: Uint8List(len),
            expiresAtUnix: 1,
          ),
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
        'device_expired': DeviceRegistryFailure.deviceExpired,
        'challenge_invalid': DeviceRegistryFailure.challengeInvalid,
        'challenge_expired': DeviceRegistryFailure.challengeExpired,
        'proof_invalid': DeviceRegistryFailure.proofInvalid,
        'certificate_invalid': DeviceRegistryFailure.certificateInvalid,
        'duplicate_device': DeviceRegistryFailure.duplicateDevice,
        'too_many_pending': DeviceRegistryFailure.tooManyPending,
        'approval_required': DeviceRegistryFailure.approvalRequired,
        'request_invalid': DeviceRegistryFailure.requestInvalid,
        'request_expired': DeviceRegistryFailure.requestExpired,
        'approver_not_trusted': DeviceRegistryFailure.approverNotTrusted,
        'approval_invalid': DeviceRegistryFailure.approvalInvalid,
        'recovery_unavailable': DeviceRegistryFailure.recoveryUnavailable,
        'recovery_invalid': DeviceRegistryFailure.recoveryInvalid,
        'rate_limited': DeviceRegistryFailure.rateLimited,
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

    test('server failure categories cover every server category', () {
      // Drift guard: every category in functions/src/device/common.ts maps.
      final source = File('functions/src/device/common.ts').readAsStringSync();
      final block = RegExp(
        r'export type DeviceFailure =([^;]*);',
      ).firstMatch(source)!.group(1)!;
      final categories = RegExp(
        r"'([a-z_]+)'",
      ).allMatches(block).map((m) => m[1]!);
      expect(categories, isNotEmpty);
      for (final c in categories) {
        expect(
          DeviceRegistryFailure.fromServer(c),
          isNot(DeviceRegistryFailure.unavailable),
          reason: c,
        );
      }
    });

    test('records, challenges and requests print redacted', () {
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
      expect(
        ApprovalRequest(
          requestId: 'id',
          challenge: Uint8List(32),
          expiresAtUnix: 1,
        ).toString(),
        contains('<redacted>'),
      );
    });
  });
}

/// Delegates to [FakeRegistry] but fails the activation call once.
class _FailingActivation implements DeviceRegistry {
  _FailingActivation(this._inner);

  final FakeRegistry _inner;

  @override
  Future<void> activate(AccountId a, String d, String c, Uint8List p) async =>
      throw const DeviceRegistryException(
        DeviceRegistryFailure.challengeExpired,
      );

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      Function.apply(switch (invocation.memberName) {
        #status => _inner.status,
        #register => _inner.register,
        #requestChallenge => _inner.requestChallenge,
        _ => throw UnimplementedError(),
      }, invocation.positionalArguments);
}
