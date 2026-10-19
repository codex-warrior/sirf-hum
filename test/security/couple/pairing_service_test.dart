// Pairing client (Prompt 12, D-101–D-104). The server-side verification and
// state machine are tested in functions/test/emulator/pairing.test.mjs.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sirf_hum/core/logging/app_logger.dart';
import 'package:sirf_hum/security/couple/pairing.dart';
import 'package:sirf_hum/security/device/device_registration.dart';
import 'package:sirf_hum_crypto/sirf_hum_crypto.dart';

import '../device/device_test_support.dart';

// A well-formed test token (16 bytes 0..15, base64url, unpadded), built at
// runtime so it is obviously not a credential.
final _token = base64Url
    .encode(List<int>.generate(16, (i) => i))
    .replaceAll('=', '');
const _pairingId = '0123456789abcdef0123456789abcdef';

class _Backend implements PairingBackend {
  final calls = <String>[];
  final challenges = <({PairingStep step, String? token, String? pairingId})>[];
  final signed = <SignedPairingStep>[];
  final issued = <String, Uint8List>{};
  PairingFailure? fail;
  var n = 0;

  @override
  Future<PairingChallenge> requestChallenge({
    required String deviceIdHex,
    required PairingStep step,
    String? token,
    String? pairingId,
  }) async {
    calls.add('challenge:${step.name}');
    challenges.add((step: step, token: token, pairingId: pairingId));
    final id = 'c${++n}';
    final challenge = Uint8List.fromList(List.filled(32, n));
    issued[id] = challenge;
    return PairingChallenge(challengeId: id, challenge: challenge);
  }

  Future<void> _step(String name, SignedPairingStep step) async {
    calls.add(name);
    signed.add(step);
    if (fail case final f?) throw PairingException(f);
  }

  @override
  Future<PairingInvitation> create(SignedPairingStep step) async {
    await _step('create', step);
    return PairingInvitation(
      pairingId: _pairingId,
      token: _token,
      expiresAt: DateTime.utc(2030),
    );
  }

  @override
  Future<PairingAcceptance> accept(SignedPairingStep step, String token) async {
    await _step('accept', step);
    return PairingAcceptance(
      pairingId: _pairingId,
      code: '042137',
      partnerDisplayName: 'Asha',
      confirmBy: DateTime.utc(2030),
    );
  }

  @override
  Future<CoupleMembership> confirm(
    SignedPairingStep step,
    String pairingId,
  ) async {
    await _step('confirm', step);
    return const CoupleMembership(coupleId: 'c', conversationId: 'v');
  }

  @override
  Future<void> reject(SignedPairingStep step, String pairingId) =>
      _step('reject', step);

  @override
  Future<void> cancel(SignedPairingStep step, String pairingId) =>
      _step('cancel', step);

  @override
  Future<PairingState> state() async => const PairingNone();
}

class _Sink implements LogSink {
  final lines = <String>[];

  @override
  void write(LogRecord record) =>
      lines.add('${record.message} ${record.fields}');
}

void main() {
  group('PairingFailure', () {
    test('maps every server category; unknown is retryable, never success', () {
      expect(
        PairingFailure.fromServer('invitation_invalid'),
        PairingFailure.invitationInvalid,
      );
      expect(
        PairingFailure.fromServer('pairing_invalidated'),
        PairingFailure.pairingInvalidated,
      );
      expect(
        PairingFailure.fromServer('identity_reset_pending'),
        PairingFailure.identityResetPending,
      );
      for (final c in ['device_not_active', 'proof_invalid']) {
        expect(PairingFailure.fromServer(c), PairingFailure.deviceNotTrusted);
      }
      for (final c in [null, '', 'ok', 'accepted', 'internal']) {
        expect(PairingFailure.fromServer(c), PairingFailure.unavailable);
      }
    });
  });

  group('PairingState.parse (strict)', () {
    test('understands the four server states', () {
      expect(PairingState.parse({'state': 'none'}), isA<PairingNone>());
      final invited = PairingState.parse({
        'state': 'invited',
        'pairingId': _pairingId,
        'expiresAtMillis': 1000,
      });
      expect((invited as PairingInvited).pairingId, _pairingId);
      final waiting = PairingState.parse({
        'state': 'awaiting_confirmation',
        'role': 'invitee',
        'pairingId': _pairingId,
        'confirmationCode': '042137',
        'partnerDisplayName': null,
        'expiresAtMillis': 2000,
      });
      waiting as PairingAwaitingConfirmation;
      expect(waiting.isInviter, isFalse);
      expect(waiting.code, '042137');
      expect(waiting.toString(), isNot(contains('042137')));
      final paired = PairingState.parse({
        'state': 'paired',
        'coupleId': _pairingId,
        'conversationId': _pairingId,
      });
      expect((paired as PairingPaired).coupleId, _pairingId);
    });

    test('anything unexpected is a failure, never a state', () {
      for (final bad in <Map<Object?, Object?>>[
        {},
        {'state': 'accepted'},
        {'state': 'invited', 'pairingId': 'x', 'expiresAtMillis': 1},
        {'state': 'invited', 'pairingId': _pairingId},
        {
          'state': 'awaiting_confirmation',
          'role': 'admin',
          'pairingId': _pairingId,
          'confirmationCode': '000000',
          'expiresAtMillis': 1,
        },
        {
          'state': 'awaiting_confirmation',
          'role': 'inviter',
          'pairingId': _pairingId,
          'confirmationCode': '12',
          'expiresAtMillis': 1,
        },
        {'state': 'paired', 'coupleId': 'not-hex'},
      ]) {
        expect(
          () => PairingState.parse(bad),
          throwsA(isA<PairingException>()),
          reason: '$bad',
        );
      }
    });
  });

  group('PairingService', () {
    late Directory root;
    late CryptoCore core;
    late _Backend backend;
    late PairingService service;
    late _Sink sink;

    setUp(() {
      root = Directory.systemTemp.createTempSync('sh_pairing_');
      core = CryptoCore.initializeWithPlatformKey(
        directory: root.path,
        storeKey: Uint8List.fromList(List.filled(32, 5)),
      )..createIdentity(AccountId('accountA'));
      backend = _Backend();
      service = PairingService(core: core, backend: backend);
      sink = _Sink();
      AppLogger.configure(sinks: [sink], minimumLevel: LogLevel.debug);
    });

    tearDown(() {
      AppLogger.configure(sinks: const [DeveloperLogSink()]);
      core.close();
      root.deleteSync(recursive: true);
    });

    String deviceHex() =>
        PendingDeviceRegistration.hexOf(core.publicIdentity().deviceId);

    test(
      'every step is a fresh challenge answered with a pairing-purpose proof',
      () async {
        await service.createInvitation();
        await service.acceptInvitation(_token);
        await service.confirm(_pairingId);
        await service.reject(_pairingId);
        await service.cancel(_pairingId);
        expect(backend.calls, [
          'challenge:create',
          'create',
          'challenge:accept',
          'accept',
          'challenge:confirm',
          'confirm',
          'challenge:reject',
          'reject',
          'challenge:cancel',
          'cancel',
        ]);
        // Each challenge names its subject, so the server can bind it.
        expect(backend.challenges[0].token, isNull);
        expect(backend.challenges[1].token, _token);
        expect(backend.challenges[2].pairingId, _pairingId);
        for (final (i, step) in backend.signed.indexed) {
          final challenge = backend.issued['c${i + 1}']!;
          expect(step.deviceIdHex, deviceHex());
          expect(step.challengeId, 'c${i + 1}');
          expect(
            step.proof,
            core.deviceProof(DeviceProofPurpose.pairing, challenge),
          );
          // Not usable as a proof for any other purpose.
          for (final other in DeviceProofPurpose.values.where(
            (p) => p != DeviceProofPurpose.pairing,
          )) {
            expect(step.proof, isNot(core.deviceProof(other, challenge)));
          }
        }
        expect(
          backend.signed.map((s) => s.proof.join(',')).toSet(),
          hasLength(5),
          reason: 'challenge-bound',
        );
      },
    );

    test('a malformed token fails locally, without a server call', () async {
      for (final bad in [
        '',
        'short',
        '${_token}x',
        '${_token.substring(1)}=',
      ]) {
        await expectLater(
          service.acceptInvitation(bad),
          throwsA(
            isA<PairingException>().having(
              (e) => e.failure,
              'failure',
              PairingFailure.invitationInvalid,
            ),
          ),
        );
      }
      expect(backend.calls, isEmpty);
    });

    test('server refusals surface as categories', () async {
      backend.fail = PairingFailure.pairingInvalidated;
      await expectLater(
        service.confirm(_pairingId),
        throwsA(
          isA<PairingException>().having(
            (e) => e.failure,
            'failure',
            PairingFailure.pairingInvalidated,
          ),
        ),
      );
      expect(sink.lines.join(), contains('pairingInvalidated'));
    });

    test(
      'logs carry the step and outcome only: no token, code or IDs',
      () async {
        final invitation = await service.createInvitation();
        final acceptance = await service.acceptInvitation(_token);
        await service.confirm(_pairingId);
        final logs = sink.lines.join('\n');
        expect(logs, contains('pairing_step'));
        for (final secret in [
          _token,
          acceptance.code,
          _pairingId,
          deviceHex(),
          'Asha',
        ]) {
          expect(logs, isNot(contains(secret)), reason: secret);
        }
        expect(invitation.toString(), isNot(contains(_token)));
        expect(acceptance.toString(), isNot(contains('042137')));
      },
    );
  }, skip: nativeSkip);
}
