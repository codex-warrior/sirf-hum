import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sirf_hum/infrastructure/firebase/firebase_bootstrap.dart';
import 'package:sirf_hum/infrastructure/firebase/firebase_config.dart';

FirebaseConfig _config({String webApiKey = 'web-key'}) => FirebaseConfig(
  projectId: 'sirf-hum-dev',
  messagingSenderId: '123',
  platform: FirebasePlatform.web,
  apps: {
    FirebasePlatform.web: FirebaseAppCredentials(
      appId: '1:123:web:abc',
      apiKey: webApiKey,
    ),
  },
);

void main() {
  test(
    'does not initialize Firebase when configuration is incomplete',
    () async {
      var called = false;
      final bootstrap = FirebaseBootstrap(
        initializer: (_) async => called = true,
      );

      expect(
        await bootstrap.initialize(_config(webApiKey: '')),
        FirebaseStatus.notConfigured,
      );
      expect(called, isFalse);
    },
  );

  test('initializes with options built from configuration', () async {
    FirebaseOptions? received;
    final bootstrap = FirebaseBootstrap(
      initializer: (options) async => received = options,
    );

    expect(await bootstrap.initialize(_config()), FirebaseStatus.ready);
    expect(received?.projectId, 'sirf-hum-dev');
    expect(received?.appId, '1:123:web:abc');
  });

  test('reports failure instead of crashing app start', () async {
    final bootstrap = FirebaseBootstrap(
      initializer: (_) async => throw FirebaseException(plugin: 'core'),
    );

    expect(await bootstrap.initialize(_config()), FirebaseStatus.failed);
  });

  test(
    'an initialization that never returns does not hang app start',
    () async {
      final bootstrap = FirebaseBootstrap(
        initializer: (_) => Completer<void>().future,
        timeout: const Duration(milliseconds: 20),
      );
      expect(await bootstrap.initialize(_config()), FirebaseStatus.failed);
    },
  );

  test(
    'an immediate failure returns at once, without waiting the bound',
    () async {
      // With a one-hour bound, this test would time out if failure waited.
      final bootstrap = FirebaseBootstrap(
        initializer: (_) async => throw FirebaseException(plugin: 'core'),
        timeout: const Duration(hours: 1),
      );
      final watch = Stopwatch()..start();
      expect(await bootstrap.initialize(_config()), FirebaseStatus.failed);
      expect(watch.elapsed, lessThan(const Duration(seconds: 5)));
    },
  );

  test('the default bound is short enough to show the app', () {
    expect(
      FirebaseBootstrap.defaultTimeout,
      lessThanOrEqualTo(const Duration(seconds: 15)),
    );
  });
}
