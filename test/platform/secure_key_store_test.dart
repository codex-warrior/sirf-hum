import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sirf_hum/platform/secure_key_store.dart';
import 'package:sirf_hum/security/device/device_key_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel(PlatformSecureKeyStore.channelName);
  final calls = <MethodCall>[];

  void respond(Object? Function(MethodCall call) handler) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          return handler(call);
        });
  }

  setUp(calls.clear);
  tearDown(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null),
  );

  const store = PlatformSecureKeyStore(supported: true);

  test('passes slot and create flag; returns the key bytes', () async {
    respond((_) => Uint8List.fromList(List.filled(32, 3)));
    final key = await store.storeKey('accountA', create: true);
    expect(key, hasLength(32));
    expect(calls.single.method, 'storeKey');
    expect(calls.single.arguments, {'slot': 'accountA', 'create': true});
  });

  test('a missing key is null, not an error', () async {
    respond((_) => throw PlatformException(code: 'key_missing'));
    expect(await store.storeKey('accountA', create: false), isNull);
  });

  test('platform errors become categories without messages', () async {
    respond(
      (_) => throw PlatformException(code: 'keystore_failure', message: 'x'),
    );
    await expectLater(
      store.storeKey('accountA', create: false),
      throwsA(
        isA<DeviceKeyStoreException>().having(
          (e) => e.failure,
          'failure',
          DeviceKeyStoreFailure.keystoreFailure,
        ),
      ),
    );
    respond((_) => throw PlatformException(code: 'invalid_slot'));
    await expectLater(
      store.slotDirectory('bad'),
      throwsA(
        isA<DeviceKeyStoreException>().having(
          (e) => e.failure,
          'failure',
          DeviceKeyStoreFailure.invalidSlot,
        ),
      ),
    );
  });

  test('unsupported platforms never reach the channel', () async {
    respond((_) => fail('channel must not be called'));
    const web = PlatformSecureKeyStore(supported: false);
    expect(web.isSupported, isFalse);
    await expectLater(
      web.storeKey('accountA', create: true),
      throwsA(
        isA<DeviceKeyStoreException>().having(
          (e) => e.failure,
          'failure',
          DeviceKeyStoreFailure.unsupported,
        ),
      ),
    );
    expect(calls, isEmpty);
  });

  test('removeSlot and slotDirectory use the documented methods', () async {
    respond((call) => call.method == 'slotDirectory' ? '/data/slot' : null);
    expect(await store.slotDirectory('accountA'), '/data/slot');
    await store.removeSlot('accountA');
    expect(calls.map((c) => c.method), ['slotDirectory', 'removeSlot']);
  });
}
