/// The deployment environment this build targets.
///
/// Selected at build time with `--dart-define-from-file=config/env/<env>.json`
/// (docs/architecture/ENVIRONMENTS.md). Defaults to [development] so that a
/// bare `flutter run` can never talk to production.
enum AppEnvironment {
  development(
    firebaseProjectId: 'sirf-hum-dev',
    firebaseProjectNumber: '627383930881',
    androidApplicationId: 'com.sirfhum.app.dev',
  ),
  staging(
    firebaseProjectId: 'sirf-hum-staging',
    firebaseProjectNumber: '203770631547',
    androidApplicationId: 'com.sirfhum.app.staging',
  ),
  production(
    firebaseProjectId: 'sirf-hum-prod',
    firebaseProjectNumber: '244475624083',
    androidApplicationId: 'com.sirfhum.app',
  );

  const AppEnvironment({
    required this.firebaseProjectId,
    required this.firebaseProjectNumber,
    required this.androidApplicationId,
  });

  /// The only Firebase project this environment may connect to.
  final String firebaseProjectId;

  /// That project's number (public; same table as
  /// `tool/check_env_config.mjs`). It prefixes the project's Firebase app
  /// IDs, its messaging sender ID and its OAuth client IDs, so it catches a
  /// config that mixes two projects.
  final String firebaseProjectNumber;

  /// The Android identity of this environment (D-022; `applicationId` plus
  /// the flavor suffix in `android/app/build.gradle.kts`). Sign-in links
  /// return only to this app.
  final String androidApplicationId;

  static AppEnvironment fromName(String name) {
    return AppEnvironment.values.firstWhere(
      (env) => env.name == name,
      orElse: () => throw ArgumentError.value(
        name,
        'SH_ENV',
        'Unknown environment. Expected one of: '
            '${AppEnvironment.values.map((e) => e.name).join(', ')}',
      ),
    );
  }

  bool get isProduction => this == AppEnvironment.production;
}
