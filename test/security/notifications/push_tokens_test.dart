// Push token registration and signals (Prompt 11, D-097, D-098). The
// server-side verification of the proof is tested in
// functions/test/emulator/notification.test.mjs.
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sirf_hum/core/logging/app_logger.dart';
import 'package:sirf_hum/security/device/device_registration.dart';
import 'package:sirf_hum/security/notifications/push_tokens.dart';
import 'package:sirf_hum_crypto/sirf_hum_crypto.dart';

import '../device/device_test_support.dart';

class _Source implements PushTokenSource {
  String? current = 'fcm-token-1';
  // Closed by the test tear-down.
  // ignore: close_sinks
  final refresh = StreamController<String>.broadcast();
  final calls = <String>[];

  @override
  Future<String?> token() async => current;

  @override
  Stream<String> get onTokenRefresh => refresh.stream;

  @override
  Future<void> deleteToken() async {
    calls.add('deleteToken');
    current = null;
  }
}

class _Registry implements PushTokenRegistry {
  final calls = <String>[];
  final registered = <({String device, String? token, Uint8List proof})>[];
  final issued = <String, Uint8List>{};
  DeviceRegistryFailure? fail;
  var n = 0;

  @override
  Future<PushTokenChallenge> requestChallenge({
    required String deviceIdHex,
    required String? token,
  }) async {
    calls.add('challenge');
    if (fail case final f?) throw DeviceRegistryException(f);
    final id = 'c${++n}';
    final challenge = Uint8List.fromList(List.filled(32, n));
    issued[id] = challenge;
    return PushTokenChallenge(challengeId: id, challenge: challenge);
  }

  @override
  Future<void> register({
    required String deviceIdHex,
    required String challengeId,
    required String? token,
    required Uint8List proof,
  }) async {
    calls.add('register');
    registered.add((device: deviceIdHex, token: token, proof: proof));
  }
}

class _Sink implements LogSink {
  final lines = <String>[];

  @override
  void write(LogRecord record) => lines.add(record.message);
}

void main() {
  group('PushSignal (strict, content-free)', () {
    test('only the two known kinds are understood', () {
      expect(PushSignal.parse({'v': '1', 'k': 'm'}), PushSignal.message);
      expect(PushSignal.parse({'v': '1', 'k': 's'}), PushSignal.sync);
      for (final bad in <Map<String, Object?>>[
        {},
        {'v': '2', 'k': 'm'},
        {'v': '1', 'k': 'x'},
        {'v': '1'},
        {'v': '1', 'k': 'm', 'text': 'I miss you'},
        {'k': 'm', 'conversation': 'c'},
      ]) {
        expect(PushSignal.parse(bad), PushSignal.unknown, reason: '$bad');
      }
    });
  });

  group('PushTokenRegistrar', () {
    late Directory root;
    late CryptoCore core;
    late _Source source;
    late _Registry registry;
    late PushTokenRegistrar registrar;
    late _Sink sink;

    setUp(() {
      root = Directory.systemTemp.createTempSync('sh_push_');
      core = CryptoCore.initializeWithPlatformKey(
        directory: root.path,
        storeKey: Uint8List.fromList(List.filled(32, 3)),
      )..createIdentity(AccountId('accountA'));
      source = _Source();
      addTearDown(source.refresh.close);
      registry = _Registry();
      registrar = PushTokenRegistrar(
        core: core,
        source: source,
        registry: registry,
      );
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
      'registers the token with a fresh device-key proof per challenge',
      () async {
        expect(await registrar.register(), isTrue);
        source.current = 'fcm-token-2';
        expect(await registrar.register(), isTrue);
        expect(registry.calls, [
          'challenge',
          'register',
          'challenge',
          'register',
        ]);
        final [first, second] = registry.registered;
        expect(first.device, deviceHex());
        expect(first.token, 'fcm-token-1');
        expect(first.proof, hasLength(64));
        expect(second.token, 'fcm-token-2');
        expect(second.proof, isNot(first.proof), reason: 'challenge-bound');
        // The proof is the push-token purpose, not an activation proof.
        expect(
          first.proof,
          isNot(
            core.deviceProof(
              DeviceProofPurpose.activation,
              registry.issued['c1']!,
            ),
          ),
        );
        expect(
          first.proof,
          core.deviceProof(
            DeviceProofPurpose.pushToken,
            registry.issued['c1']!,
          ),
        );
      },
    );

    test(
      'no token (no Play services, permission): nothing registered',
      () async {
        source.current = null;
        expect(await registrar.register(), isFalse);
        expect(registry.calls, isEmpty);
      },
    );

    test('rotation re-registers the new token', () async {
      final sub = registrar.watchRotation();
      addTearDown(sub.cancel);
      source.refresh.add('rotated');
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      expect(registry.registered.single.token, 'rotated');
    });

    test('logout: signed clear first, then the token dies at FCM', () async {
      await registrar.unregister();
      expect(registry.registered.single.token, isNull);
      expect(registry.calls.last, 'register');
      expect(source.calls, ['deleteToken']);
    });

    test('offline logout still deletes the token locally', () async {
      registry.fail = DeviceRegistryFailure.unavailable;
      await registrar.unregister();
      expect(source.calls, ['deleteToken']);
      expect(sink.lines.join(), contains('unavailable'));
    });

    test('a device the server no longer trusts cannot register', () async {
      registry.fail = DeviceRegistryFailure.deviceNotTrusted;
      await expectLater(
        registrar.register(),
        throwsA(
          isA<DeviceRegistryException>().having(
            (e) => e.failure,
            'failure',
            DeviceRegistryFailure.deviceNotTrusted,
          ),
        ),
      );
    });

    test('logs never contain the token or the device ID', () async {
      await registrar.register();
      await registrar.unregister();
      final all = sink.lines.join('\n');
      expect(all, contains('push_token_registered'));
      expect(all, isNot(contains('fcm-token')));
      expect(all, isNot(contains(deviceHex())));
    });

    test('server categories map to safe failures', () {
      expect(
        DeviceRegistryFailure.fromServer('device_not_active'),
        DeviceRegistryFailure.deviceNotTrusted,
      );
    });
  }, skip: nativeSkip);
}
