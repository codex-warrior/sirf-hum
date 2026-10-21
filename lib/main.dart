import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:sirf_hum/app/app.dart';
import 'package:sirf_hum/app/app_config.dart';
import 'package:sirf_hum/app/app_providers.dart';
import 'package:sirf_hum/app/environment_guard.dart';
import 'package:sirf_hum/core/logging/app_logger.dart';
import 'package:sirf_hum/features/moments/application/moment_photo_picker.dart';
import 'package:sirf_hum/features/moments/data/picker_cache_sweeper.dart';
import 'package:sirf_hum/features/moments/data/system_photo_picker.dart';
import 'package:sirf_hum/features/verification/application/verification_controller.dart';
import 'package:sirf_hum/features/verification/data/camera_qr_code_scanner.dart';
import 'package:sirf_hum/infrastructure/firebase/app_check_bootstrap.dart';
import 'package:sirf_hum/infrastructure/firebase/callable_pairing_backend.dart';
import 'package:sirf_hum/infrastructure/firebase/crash_reporting.dart';
import 'package:sirf_hum/infrastructure/firebase/firebase_account_session.dart';
import 'package:sirf_hum/infrastructure/firebase/firebase_bootstrap.dart';
import 'package:sirf_hum/infrastructure/firebase/firestore_couple_profiles.dart';
import 'package:sirf_hum/security/account/account_session.dart';
import 'package:sirf_hum/session/session_controller.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final config = AppConfig.fromEnvironment();
  // A build whose flavor, SH_ENV and Firebase project disagree must not run.
  ensureEnvironmentIsConsistent(config, nativeFlavor: appFlavor);

  final firebaseStatus = await const FirebaseBootstrap().initialize(
    config.firebase,
  );
  final platform = config.firebase.platform;
  if (firebaseStatus == FirebaseStatus.ready && platform != null) {
    final crashSink = await CrashReporting.configure(
      enabled: config.crashReportingEnabled,
    );
    AppLogger.configure(sinks: [const DeveloperLogSink(), ?crashSink]);
    await const AppCheckBootstrap().activate(
      config.appCheck,
      platform: platform,
    );
  }
  CrashReporting.installUncaughtErrorHandlers();

  // Plaintext picker copies a killed process left behind (P2-3, D-141).
  // Before runApp, so no composer can be holding one yet. Never throws.
  await const PickerCacheSweeper().sweepAtStartup();

  AppLogger.info(
    'app_start',
    fields: {
      'env': config.environment,
      'firebase': firebaseStatus,
      'app_check': config.appCheck.provider,
    },
  );

  runApp(
    ProviderScope(
      overrides: [
        appConfigProvider.overrideWithValue(config),
        firebaseStatusProvider.overrideWithValue(firebaseStatus),
        ...sessionPortOverrides(firebaseStatus),
        // Web never handles private media (D-046): no picker there.
        if (!kIsWeb)
          momentPhotoPickerProvider.overrideWithValue(
            const SystemPhotoPicker(),
          ),
        // Nor private keys, so no safety-number scanning there (D-128).
        if (!kIsWeb)
          qrCodeScannerProvider.overrideWithValue(const CameraQrCodeScanner()),
      ],
      child: const SirfHumApp(),
    ),
  );
}

/// The session ports for this start-up (D-106, D-110). Fails closed:
/// - not configured: the defaults (signed out, no backend);
/// - failed (error or start-up timeout): the account cannot be known, so the
///   session is unavailable, never signed out and never signed in;
/// - ready: the Firebase implementations.
@visibleForTesting
List<Override> sessionPortOverrides(FirebaseStatus status) => switch (status) {
  FirebaseStatus.notConfigured => const [],
  FirebaseStatus.failed => [
    accountSessionProvider.overrideWithValue(const UnavailableAccountSession()),
  ],
  FirebaseStatus.ready => [
    accountSessionProvider.overrideWithValue(FirebaseAccountSession()),
    pairingBackendProvider.overrideWithValue(CallablePairingBackend()),
    coupleProfilesProvider.overrideWithValue(FirestoreCoupleProfiles()),
  ],
};
