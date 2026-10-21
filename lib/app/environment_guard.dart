import 'package:sirf_hum/app/app_config.dart';
import 'package:sirf_hum/core/config/app_environment.dart';
import 'package:sirf_hum/infrastructure/firebase/app_check_config.dart';
import 'package:sirf_hum/infrastructure/firebase/firebase_config.dart';

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
    if (config.firebase.isComplete &&
        config.firebase.messagingSenderId != env.firebaseProjectNumber)
      'Firebase messaging sender ID is not the ${env.name} project number.',
    // Google ID tokens are minted for this client; another project's client
    // would sign users in to the wrong project, or fail (D-150).
    if (config.googleServerClientId case final client?
        when !isGoogleClientOf(env, client))
      'The Google OAuth client ID is not a ${env.name} client.',
    if (env.isProduction && config.appCheck.provider == AppCheckProvider.debug)
      'The App Check debug provider is never allowed in production.',
    if (env.isProduction && !config.firebase.isComplete)
      'Production builds require a complete Firebase configuration.',
    // Without a site key App Check is skipped on web (AppCheckBootstrap);
    // production must never start unattested (Prompt 18, D-139).
    if (env.isProduction &&
        config.firebase.platform == FirebasePlatform.web &&
        config.appCheck.webRecaptchaSiteKey == null)
      'Production web builds require a reCAPTCHA Enterprise site key '
          '(SH_APPCHECK_WEB_RECAPTCHA_SITE_KEY) for App Check.',
  ];
}

/// Whether [clientId] is an OAuth client of [env]'s project: Google prefixes
/// client IDs with the project number.
bool isGoogleClientOf(AppEnvironment env, String clientId) =>
    clientId.startsWith('${env.firebaseProjectNumber}-') &&
    clientId.endsWith('.apps.googleusercontent.com');

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
