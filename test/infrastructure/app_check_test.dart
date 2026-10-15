import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sirf_hum/core/config/app_environment.dart';
import 'package:sirf_hum/infrastructure/firebase/app_check_bootstrap.dart';
import 'package:sirf_hum/infrastructure/firebase/app_check_config.dart';
import 'package:sirf_hum/infrastructure/firebase/crash_reporting.dart';

void main() {
  test('development defaults to debug; staging and production attest', () {
    // Without SH_APPCHECK_PROVIDER, the environment decides.
    expect(
      AppCheckConfig.fromEnvironment(AppEnvironment.development).provider,
      AppCheckProvider.debug,
    );
    expect(
      AppCheckConfig.fromEnvironment(AppEnvironment.staging).provider,
      AppCheckProvider.attestation,
    );
    expect(
      AppCheckConfig.fromEnvironment(AppEnvironment.production).provider,
      AppCheckProvider.attestation,
    );
  });

  test('debug provider uses debug providers on every platform', () {
    final p = selectAppCheckProviders(
      const AppCheckConfig(provider: AppCheckProvider.debug),
    );
    expect(p.android, isA<AndroidDebugProvider>());
    expect(p.apple, isA<AppleDebugProvider>());
    expect(p.web, isA<WebDebugProvider>());
  });

  test('attestation uses real platform attestation', () {
    final p = selectAppCheckProviders(
      const AppCheckConfig(
        provider: AppCheckProvider.attestation,
        webRecaptchaSiteKey: 'site-key',
      ),
    );
    expect(p.android, isA<AndroidPlayIntegrityProvider>());
    expect(p.apple, isA<AppleAppAttestWithDeviceCheckFallbackProvider>());
    expect(p.web, isA<ReCaptchaEnterpriseProvider>());
    expect(p.web!.siteKey, 'site-key');
  });

  test('attestation on web without a site key has no web provider', () {
    final p = selectAppCheckProviders(
      const AppCheckConfig(provider: AppCheckProvider.attestation),
    );
    expect(p.web, isNull);
  });

  test('crash reports carry only the error type', () {
    expect(
      const RedactedError('FormatException').toString(),
      'RedactedError(FormatException)',
    );
  });
}
