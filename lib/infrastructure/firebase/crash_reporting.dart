import 'dart:async';

import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';
import 'package:sirf_hum/core/logging/app_logger.dart';

/// Stands in for the real error when reporting to Crashlytics.
///
/// Exception messages can quote user content (a `FormatException` echoes its
/// input; a failed request may include a payload), so only the type name
/// leaves the device. The original stack trace is kept: it contains code
/// locations, not data.
class RedactedError implements Exception {
  const RedactedError(this.type);

  final String type;

  @override
  String toString() => 'RedactedError($type)';
}

/// Forwards already-sanitized [LogRecord]s to Crashlytics: info and above as
/// breadcrumbs, errors with a stack trace as non-fatal (or fatal) issues.
class CrashlyticsLogSink implements LogSink {
  CrashlyticsLogSink(this._crashlytics);

  final FirebaseCrashlytics _crashlytics;

  @override
  void write(LogRecord record) {
    if (record.level == LogLevel.debug) return;
    unawaited(_crashlytics.log('${record.level.name}: ${record.message}'));
    final stackTrace = record.stackTrace;
    if (record.level == LogLevel.error && stackTrace != null) {
      unawaited(
        _crashlytics.recordError(
          RedactedError(record.errorType ?? 'unknown'),
          stackTrace,
          reason: record.event,
          fatal: record.fields['fatal'] == 'true',
          printDetails: false,
        ),
      );
    }
  }
}

/// Crashlytics wiring. Unsupported on web, where it is a no-op.
///
/// Native collection is disabled by default in AndroidManifest.xml and
/// Info.plist, so nothing is sent before [configure] decides.
abstract final class CrashReporting {
  static Future<LogSink?> configure({required bool enabled}) async {
    if (kIsWeb) return null;
    final crashlytics = FirebaseCrashlytics.instance;
    await crashlytics.setCrashlyticsCollectionEnabled(enabled);
    return enabled ? CrashlyticsLogSink(crashlytics) : null;
  }

  /// Routes uncaught errors through [AppLogger] so they get the same
  /// sanitization as every other log record.
  static void installUncaughtErrorHandlers() {
    FlutterError.onError = (details) {
      if (kDebugMode) FlutterError.presentError(details);
      AppLogger.error(
        'uncaught_flutter_error',
        fields: const {'fatal': true},
        error: details.exception,
        stackTrace: details.stack ?? StackTrace.current,
      );
    };
    PlatformDispatcher.instance.onError = (error, stackTrace) {
      AppLogger.error(
        'uncaught_platform_error',
        fields: const {'fatal': true},
        error: error,
        stackTrace: stackTrace,
      );
      return true;
    };
  }
}
