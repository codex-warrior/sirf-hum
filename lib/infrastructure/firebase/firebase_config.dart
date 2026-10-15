import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

/// Platforms with their own registered Firebase app (and therefore their own
/// app ID and API key).
enum FirebasePlatform {
  android,
  ios,
  web;

  /// The platform of the running build, or null where Sirf Hum has no
  /// Firebase app (desktop, tests on unsupported hosts).
  static FirebasePlatform? current() {
    if (kIsWeb) return FirebasePlatform.web;
    return switch (defaultTargetPlatform) {
      TargetPlatform.android => FirebasePlatform.android,
      TargetPlatform.iOS => FirebasePlatform.ios,
      _ => null,
    };
  }
}

@immutable
class FirebaseAppCredentials {
  const FirebaseAppCredentials({required this.appId, required this.apiKey});

  final String appId;
  final String apiKey;

  bool get isComplete => appId.isNotEmpty && apiKey.isNotEmpty;
}

/// Firebase client configuration supplied at build time.
///
/// These identifiers are not secrets (they ship in every client), but they
/// are still kept out of git so development builds can never be pointed at
/// production by accident. Access control is enforced by Security Rules and
/// App Check, never by keeping these values hidden.
///
/// Generate with `node tool/generate_env_config.mjs <environment>`.
class FirebaseConfig {
  const FirebaseConfig({
    required this.projectId,
    required this.messagingSenderId,
    required this.apps,
    this.storageBucket,
    this.authDomain,
    this.iosBundleId,
    FirebasePlatform? platform,
  }) : _platform = platform;

  factory FirebaseConfig.fromEnvironment() {
    // String.fromEnvironment is only reliable in const contexts.
    const storageBucket = String.fromEnvironment('SH_FIREBASE_STORAGE_BUCKET');
    const authDomain = String.fromEnvironment('SH_FIREBASE_AUTH_DOMAIN');
    const iosBundleId = String.fromEnvironment('SH_FIREBASE_IOS_BUNDLE_ID');
    return FirebaseConfig(
      projectId: const String.fromEnvironment('SH_FIREBASE_PROJECT_ID'),
      messagingSenderId: const String.fromEnvironment(
        'SH_FIREBASE_MESSAGING_SENDER_ID',
      ),
      apps: const {
        FirebasePlatform.android: FirebaseAppCredentials(
          appId: String.fromEnvironment('SH_FIREBASE_ANDROID_APP_ID'),
          apiKey: String.fromEnvironment('SH_FIREBASE_ANDROID_API_KEY'),
        ),
        FirebasePlatform.ios: FirebaseAppCredentials(
          appId: String.fromEnvironment('SH_FIREBASE_IOS_APP_ID'),
          apiKey: String.fromEnvironment('SH_FIREBASE_IOS_API_KEY'),
        ),
        FirebasePlatform.web: FirebaseAppCredentials(
          appId: String.fromEnvironment('SH_FIREBASE_WEB_APP_ID'),
          apiKey: String.fromEnvironment('SH_FIREBASE_WEB_API_KEY'),
        ),
      },
      storageBucket: _optional(storageBucket),
      authDomain: _optional(authDomain),
      iosBundleId: _optional(iosBundleId),
    );
  }

  final String projectId;
  final String messagingSenderId;
  final Map<FirebasePlatform, FirebaseAppCredentials> apps;
  final String? storageBucket;
  final String? authDomain;
  final String? iosBundleId;
  final FirebasePlatform? _platform;

  FirebasePlatform? get platform => _platform ?? FirebasePlatform.current();

  FirebaseAppCredentials? get _credentials =>
      platform == null ? null : apps[platform];

  /// Whether this build has everything needed to connect on its platform.
  bool get isComplete =>
      projectId.isNotEmpty &&
      messagingSenderId.isNotEmpty &&
      (_credentials?.isComplete ?? false);

  FirebaseOptions toOptions() {
    final credentials = _credentials;
    if (!isComplete || credentials == null) {
      throw StateError('Firebase configuration is incomplete.');
    }
    return FirebaseOptions(
      apiKey: credentials.apiKey,
      appId: credentials.appId,
      messagingSenderId: messagingSenderId,
      projectId: projectId,
      storageBucket: storageBucket,
      authDomain: authDomain,
      iosBundleId: platform == FirebasePlatform.ios ? iosBundleId : null,
    );
  }

  static String? _optional(String value) => value.isEmpty ? null : value;
}
