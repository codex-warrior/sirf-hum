/// The deployment environment this build targets.
///
/// Selected at build time with `--dart-define-from-file=config/env/<env>.json`
/// (docs/architecture/ENVIRONMENTS.md). Defaults to [development] so that a
/// bare `flutter run` can never talk to production.
enum AppEnvironment {
  development(firebaseProjectId: 'sirf-hum-dev'),
  staging(firebaseProjectId: 'sirf-hum-staging'),
  production(firebaseProjectId: 'sirf-hum-prod');

  const AppEnvironment({required this.firebaseProjectId});

  /// The only Firebase project this environment may connect to.
  final String firebaseProjectId;

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
