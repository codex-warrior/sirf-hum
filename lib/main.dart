import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sirf_hum/app/app.dart';
import 'package:sirf_hum/app/app_config.dart';
import 'package:sirf_hum/app/app_providers.dart';
import 'package:sirf_hum/app/environment_guard.dart';
import 'package:sirf_hum/core/logging/app_logger.dart';
import 'package:sirf_hum/infrastructure/firebase/app_check_bootstrap.dart';
import 'package:sirf_hum/infrastructure/firebase/crash_reporting.dart';
import 'package:sirf_hum/infrastructure/firebase/firebase_bootstrap.dart';

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
      ],
      child: const SirfHumApp(),
    ),
  );
}
