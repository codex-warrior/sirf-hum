import 'package:flutter_test/flutter_test.dart';
import 'package:sirf_hum/app/app_config.dart';
import 'package:sirf_hum/app/environment_guard.dart';
import 'package:sirf_hum/core/config/app_environment.dart';
import 'package:sirf_hum/infrastructure/firebase/app_check_config.dart';
import 'package:sirf_hum/infrastructure/firebase/firebase_config.dart';

FirebaseConfig _firebase(String projectId) => FirebaseConfig(
  projectId: projectId,
  messagingSenderId: '1',
  platform: FirebasePlatform.android,
  apps: const {
    FirebasePlatform.android: FirebaseAppCredentials(appId: 'a', apiKey: 'k'),
  },
);

const _unconfigured = FirebaseConfig(
  projectId: '',
  messagingSenderId: '',
  apps: {},
  platform: FirebasePlatform.android,
);

AppConfig _config(
  AppEnvironment env, {
  FirebaseConfig? firebase,
  AppCheckProvider appCheck = AppCheckProvider.attestation,
}) => AppConfig(
  environment: env,
  firebase: firebase ?? _firebase(env.firebaseProjectId),
  appCheck: AppCheckConfig(provider: appCheck),
  crashReportingEnabled: false,
);

void main() {
  test('each environment is consistent with its own project and flavor', () {
    for (final env in AppEnvironment.values) {
      expect(
        environmentViolations(_config(env), nativeFlavor: env.name),
        isEmpty,
      );
    }
  });

  test('rejects a flavor that disagrees with SH_ENV', () {
    expect(
      environmentViolations(
        _config(AppEnvironment.production),
        nativeFlavor: 'development',
      ),
      hasLength(1),
    );
  });

  test('a development build can never use the production project', () {
    final config = _config(
      AppEnvironment.development,
      firebase: _firebase('sirf-hum-prod'),
    );
    expect(environmentViolations(config), hasLength(1));
    expect(
      () => ensureEnvironmentIsConsistent(config),
      throwsA(isA<EnvironmentMismatchError>()),
    );
  });

  test('every environment fails closed with every other project', () {
    // Covers e.g. development+production, staging+development,
    // production+staging config.
    for (final env in AppEnvironment.values) {
      for (final other in AppEnvironment.values.where((e) => e != env)) {
        expect(
          () => ensureEnvironmentIsConsistent(
            _config(env, firebase: _firebase(other.firebaseProjectId)),
          ),
          throwsA(isA<EnvironmentMismatchError>()),
          reason: '${env.name} build with ${other.name} config',
        );
      }
    }
  });

  test('a native flavor never runs with another environment\'s SH_ENV', () {
    for (final env in AppEnvironment.values) {
      for (final flavor in AppEnvironment.values.where((e) => e != env)) {
        expect(
          environmentViolations(_config(env), nativeFlavor: flavor.name),
          isNotEmpty,
          reason: '${flavor.name} flavor with SH_ENV=${env.name}',
        );
      }
    }
  });

  test('staging cannot silently use production resources', () {
    expect(
      environmentViolations(
        _config(AppEnvironment.staging, firebase: _firebase('sirf-hum-prod')),
      ),
      isNotEmpty,
    );
  });

  test('production forbids the App Check debug provider', () {
    expect(
      environmentViolations(
        _config(AppEnvironment.production, appCheck: AppCheckProvider.debug),
      ),
      hasLength(1),
    );
  });

  test('production requires Firebase configuration; development does not', () {
    expect(
      environmentViolations(
        _config(AppEnvironment.production, firebase: _unconfigured),
      ),
      hasLength(1),
    );
    expect(
      environmentViolations(
        _config(AppEnvironment.development, firebase: _unconfigured),
      ),
      isEmpty,
    );
  });

  group('production web App Check (D-139)', () {
    FirebaseConfig web(String projectId) => FirebaseConfig(
      projectId: projectId,
      messagingSenderId: '1',
      platform: FirebasePlatform.web,
      apps: const {
        FirebasePlatform.web: FirebaseAppCredentials(appId: 'w', apiKey: 'k'),
      },
    );
    AppConfig webConfig(AppEnvironment env, {String? siteKey}) => AppConfig(
      environment: env,
      firebase: web(env.firebaseProjectId),
      appCheck: AppCheckConfig(
        provider: env == AppEnvironment.development
            ? AppCheckProvider.debug
            : AppCheckProvider.attestation,
        webRecaptchaSiteKey: siteKey,
      ),
      crashReportingEnabled: false,
    );

    test('refuses to start without a reCAPTCHA site key', () {
      final config = webConfig(AppEnvironment.production);
      expect(environmentViolations(config), hasLength(1));
      expect(
        () => ensureEnvironmentIsConsistent(config),
        throwsA(isA<EnvironmentMismatchError>()),
      );
    });

    test('starts with a site key', () {
      expect(
        environmentViolations(
          webConfig(AppEnvironment.production, siteKey: 'site-key'),
        ),
        isEmpty,
      );
    });

    test('development and staging stay usable without one', () {
      // Never lock development out; staging measures before enforcing.
      expect(
        environmentViolations(webConfig(AppEnvironment.development)),
        isEmpty,
      );
      expect(environmentViolations(webConfig(AppEnvironment.staging)), isEmpty);
    });

    test('Android production needs no web site key', () {
      expect(
        environmentViolations(
          _config(AppEnvironment.production),
          nativeFlavor: 'production',
        ),
        isEmpty,
      );
    });
  });

  test('web builds (no native flavor) are checked by SH_ENV alone', () {
    expect(
      environmentViolations(
        _config(AppEnvironment.staging),
        nativeFlavor: null,
      ),
      isEmpty,
    );
  });
}
