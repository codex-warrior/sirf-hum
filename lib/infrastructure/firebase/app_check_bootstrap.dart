import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:sirf_hum/core/logging/app_logger.dart';
import 'package:sirf_hum/core/logging/log_value.dart';
import 'package:sirf_hum/infrastructure/firebase/app_check_config.dart';
import 'package:sirf_hum/infrastructure/firebase/firebase_config.dart';

enum AppCheckStatus { active, skipped, failed }

/// The providers App Check will use, chosen purely from configuration.
typedef AppCheckProviders = ({
  AndroidAppCheckProvider android,
  AppleAppCheckProvider apple,
  WebProvider? web,
});

/// App Check proves requests come from a genuine Sirf Hum build. It protects
/// *access to Firebase*; it does not encrypt anything and is not E2EE
/// (docs/architecture/ENVIRONMENTS.md, "App Check").
AppCheckProviders selectAppCheckProviders(AppCheckConfig config) {
  return switch (config.provider) {
    AppCheckProvider.debug => (
      // Tokens come from the SDK's local debug secret, registered per machine
      // in the Firebase console. Never committed.
      android: const AndroidDebugProvider(),
      apple: const AppleDebugProvider(),
      web: WebDebugProvider(),
    ),
    AppCheckProvider.attestation => (
      android: const AndroidPlayIntegrityProvider(),
      apple: const AppleAppAttestWithDeviceCheckFallbackProvider(),
      web: switch (config.webRecaptchaSiteKey) {
        final key? => ReCaptchaEnterpriseProvider(key),
        null => null,
      },
    ),
  };
}

class AppCheckBootstrap {
  const AppCheckBootstrap();

  Future<AppCheckStatus> activate(
    AppCheckConfig config, {
    required FirebasePlatform platform,
  }) async {
    final providers = selectAppCheckProviders(config);
    if (platform == FirebasePlatform.web && providers.web == null) {
      // Not fatal while enforcement is off; becomes a release blocker once
      // App Check is enforced (rollout plan in ENVIRONMENTS.md).
      AppLogger.warning('app_check_web_site_key_missing');
      return AppCheckStatus.skipped;
    }
    try {
      await FirebaseAppCheck.instance.activate(
        providerAndroid: providers.android,
        providerApple: providers.apple,
        providerWeb: providers.web,
      );
      AppLogger.info(
        'app_check_activated',
        fields: {'provider': config.provider},
      );
      return AppCheckStatus.active;
    } on Object catch (error, stackTrace) {
      AppLogger.warning(
        'app_check_activation_failed',
        fields: {'provider': SafeLogString(config.provider.name)},
        error: error,
        stackTrace: stackTrace,
      );
      return AppCheckStatus.failed;
    }
  }
}
