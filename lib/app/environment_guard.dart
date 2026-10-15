import 'package:sirf_hum/app/app_config.dart';
import 'package:sirf_hum/infrastructure/firebase/app_check_config.dart';

/// Refuses to start a build whose pieces disagree about which environment it
/// is. This is the runtime half of environment isolation; the build-time half
/// is flavors + per-environment config files (docs/architecture/ENVIRONMENTS.md).
///
/// [nativeFlavor] is Flutter's `appFlavor` (`--flavor`), null on web.
List<String> environmentViolations(AppConfig config, {String? nativeFlavor}) {
  final env = config.environment;
  return [
    if (nativeFlavor != null && nativeFlavor != env.name)
      'Native flavor "$nativeFlavor" does not match SH_ENV "${env.name}".',
    if (config.firebase.isComplete &&
        config.firebase.projectId != env.firebaseProjectId)
      'Firebase project "${config.firebase.projectId}" is not allowed for '
          '${env.name}; expected "${env.firebaseProjectId}".',
    if (env.isProduction && config.appCheck.provider == AppCheckProvider.debug)
      'The App Check debug provider is never allowed in production.',
    if (env.isProduction && !config.firebase.isComplete)
      'Production builds require a complete Firebase configuration.',
  ];
}

class EnvironmentMismatchError extends Error {
  EnvironmentMismatchError(this.violations);

  final List<String> violations;

  @override
  String toString() =>
      'EnvironmentMismatchError:\n- ${violations.join('\n- ')}';
}

void ensureEnvironmentIsConsistent(AppConfig config, {String? nativeFlavor}) {
  final violations = environmentViolations(config, nativeFlavor: nativeFlavor);
  if (violations.isNotEmpty) throw EnvironmentMismatchError(violations);
}
