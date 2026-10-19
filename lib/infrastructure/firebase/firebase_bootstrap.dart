import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:sirf_hum/core/logging/app_logger.dart';
import 'package:sirf_hum/infrastructure/firebase/firebase_config.dart';

enum FirebaseStatus { ready, notConfigured, failed }

/// Initializes Firebase for the current environment.
///
/// This is the single place the app touches `Firebase.initializeApp`. A build
/// without configuration still boots (status [FirebaseStatus.notConfigured])
/// so UI and design-system work never requires live backend credentials.
class FirebaseBootstrap {
  const FirebaseBootstrap({
    FirebaseInitializer? initializer,
    this.timeout = defaultTimeout,
  }) : _initializer = initializer ?? _defaultInitializer;

  /// On web, `initializeApp` also waits for Firebase Auth to restore its
  /// session from IndexedDB; where IndexedDB never settles (blocked storage,
  /// some private modes, headless browsers) it never returns. Boot must not
  /// hang on that: past this bound the app starts with [FirebaseStatus.failed].
  static const defaultTimeout = Duration(seconds: 10);

  final FirebaseInitializer _initializer;
  final Duration timeout;

  Future<FirebaseStatus> initialize(FirebaseConfig config) async {
    if (!config.isComplete) {
      AppLogger.info('firebase_not_configured');
      return FirebaseStatus.notConfigured;
    }
    try {
      await _initializer(config.toOptions()).timeout(timeout);
      return FirebaseStatus.ready;
    } on Object catch (error, stackTrace) {
      // Boot must not crash or hang on a backend outage; features check the
      // status. A timeout lands here as a TimeoutException.
      AppLogger.warning(
        'firebase_init_failed',
        error: error,
        stackTrace: stackTrace,
      );
      return FirebaseStatus.failed;
    }
  }

  static Future<void> _defaultInitializer(FirebaseOptions options) =>
      Firebase.initializeApp(options: options);
}

typedef FirebaseInitializer = Future<void> Function(FirebaseOptions options);
