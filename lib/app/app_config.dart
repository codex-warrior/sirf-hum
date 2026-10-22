import 'package:sirf_hum/core/config/app_environment.dart';
import 'package:sirf_hum/infrastructure/firebase/app_check_config.dart';
import 'package:sirf_hum/infrastructure/firebase/firebase_config.dart';

/// Build-time configuration for one environment.
///
/// Values come from compile-time `--dart-define`s. Nothing here may be a
/// secret: anything compiled into a client binary is public. Server secrets
/// (LiveKit API secret, service accounts) live only in Cloud Functions
/// secret storage.
class AppConfig {
  const AppConfig({
    required this.environment,
    required this.firebase,
    required this.appCheck,
    required this.crashReportingEnabled,
    this.googleServerClientId,
  });

  factory AppConfig.fromEnvironment() {
    final environment = AppEnvironment.fromName(
      const String.fromEnvironment('SH_ENV', defaultValue: 'development'),
    );
    const crashReporting = String.fromEnvironment('SH_CRASH_REPORTING');
    const googleClient = String.fromEnvironment('SH_GOOGLE_SERVER_CLIENT_ID');
    return AppConfig(
      environment: environment,
      firebase: FirebaseConfig.fromEnvironment(),
      appCheck: AppCheckConfig.fromEnvironment(environment),
      // Off in development unless explicitly enabled, on elsewhere.
      crashReportingEnabled: crashReporting.isEmpty
          ? environment != AppEnvironment.development
          : crashReporting == 'true',
      googleServerClientId: googleClient.isEmpty ? null : googleClient,
    );
  }

  final AppEnvironment environment;
  final FirebaseConfig firebase;
  final AppCheckConfig appCheck;
  final bool crashReportingEnabled;

  /// The project's Web OAuth client ID, the audience of Google ID tokens
  /// (D-150). A public identifier, not a secret: no client secret exists in
  /// any client. Null: "Continue with Google" is not offered.
  final String? googleServerClientId;
}
