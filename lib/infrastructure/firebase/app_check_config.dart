import 'package:sirf_hum/core/config/app_environment.dart';

/// How this build proves to Firebase that it is a genuine Sirf Hum client.
enum AppCheckProvider {
  /// Debug tokens registered per developer machine in the Firebase console.
  /// Never allowed in production.
  debug,

  /// Real platform attestation: Play Integrity (Android), App Attest with
  /// DeviceCheck fallback (iOS), reCAPTCHA Enterprise (Web).
  attestation,
}

class AppCheckConfig {
  const AppCheckConfig({required this.provider, this.webRecaptchaSiteKey});

  factory AppCheckConfig.fromEnvironment(AppEnvironment environment) {
    const provider = String.fromEnvironment('SH_APPCHECK_PROVIDER');
    const siteKey = String.fromEnvironment(
      'SH_APPCHECK_WEB_RECAPTCHA_SITE_KEY',
    );
    return AppCheckConfig(
      provider: provider.isEmpty
          ? (environment == AppEnvironment.development
                ? AppCheckProvider.debug
                : AppCheckProvider.attestation)
          : AppCheckProvider.values.byName(provider),
      webRecaptchaSiteKey: siteKey.isEmpty ? null : siteKey,
    );
  }

  final AppCheckProvider provider;

  /// reCAPTCHA Enterprise *site* key (public by design). Required for
  /// attestation on web.
  final String? webRecaptchaSiteKey;
}
