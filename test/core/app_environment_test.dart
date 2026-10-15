import 'package:flutter_test/flutter_test.dart';
import 'package:sirf_hum/app/app_config.dart';
import 'package:sirf_hum/core/config/app_environment.dart';

void main() {
  test('parses every known environment', () {
    for (final env in AppEnvironment.values) {
      expect(AppEnvironment.fromName(env.name), env);
    }
  });

  test('rejects unknown environments instead of guessing', () {
    expect(() => AppEnvironment.fromName('prod'), throwsArgumentError);
    expect(() => AppEnvironment.fromName(''), throwsArgumentError);
  });

  test('each environment maps to its own Firebase project', () {
    expect(AppEnvironment.development.firebaseProjectId, 'sirf-hum-dev');
    expect(AppEnvironment.staging.firebaseProjectId, 'sirf-hum-staging');
    expect(AppEnvironment.production.firebaseProjectId, 'sirf-hum-prod');
    expect(
      AppEnvironment.values.map((e) => e.firebaseProjectId).toSet(),
      hasLength(AppEnvironment.values.length),
    );
  });

  test('a build without defines is development, crash reporting off', () {
    final config = AppConfig.fromEnvironment();
    expect(config.environment, AppEnvironment.development);
    expect(config.environment.isProduction, isFalse);
    expect(config.firebase.isComplete, isFalse);
    expect(config.crashReportingEnabled, isFalse);
  });
}
