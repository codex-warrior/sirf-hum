import 'package:flutter_test/flutter_test.dart';
import 'package:sirf_hum/infrastructure/firebase/firebase_config.dart';

const _apps = {
  FirebasePlatform.android: FirebaseAppCredentials(
    appId: '1:1:android:a',
    apiKey: 'android-key',
  ),
  FirebasePlatform.ios: FirebaseAppCredentials(
    appId: '1:1:ios:i',
    apiKey: 'ios-key',
  ),
  FirebasePlatform.web: FirebaseAppCredentials(
    appId: '1:1:web:w',
    apiKey: 'web-key',
  ),
};

FirebaseConfig _on(
  FirebasePlatform platform, {
  Map<FirebasePlatform, FirebaseAppCredentials> apps = _apps,
}) => FirebaseConfig(
  projectId: 'sirf-hum-staging',
  messagingSenderId: '1',
  apps: apps,
  iosBundleId: 'com.sirfhum.app.staging',
  platform: platform,
);

void main() {
  test('each platform uses its own app ID and API key', () {
    for (final platform in FirebasePlatform.values) {
      final options = _on(platform).toOptions();
      expect(options.appId, _apps[platform]!.appId);
      expect(options.apiKey, _apps[platform]!.apiKey);
      expect(options.projectId, 'sirf-hum-staging');
    }
  });

  test('iOS bundle ID is only passed on iOS', () {
    expect(
      _on(FirebasePlatform.ios).toOptions().iosBundleId,
      'com.sirfhum.app.staging',
    );
    expect(_on(FirebasePlatform.android).toOptions().iosBundleId, isNull);
  });

  test('is incomplete when the running platform has no credentials', () {
    final config = _on(
      FirebasePlatform.android,
      apps: {FirebasePlatform.web: _apps[FirebasePlatform.web]!},
    );
    expect(config.isComplete, isFalse);
    expect(config.toOptions, throwsStateError);
  });

  test('a build without defines has no Firebase configuration', () {
    expect(FirebaseConfig.fromEnvironment().isComplete, isFalse);
  });
}
