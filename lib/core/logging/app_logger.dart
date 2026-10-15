import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';
import 'package:sirf_hum/core/logging/log_value.dart';

enum LogLevel { debug, info, warning, error }

/// A privacy-checked log record. By the time a record exists, its fields have
/// been sanitized and its error reduced to a type name, so sinks can forward
/// it anywhere (console, Crashlytics) without further review.
@immutable
class LogRecord {
  const LogRecord({
    required this.level,
    required this.event,
    required this.fields,
    this.errorType,
    this.stackTrace,
  });

  final LogLevel level;

  /// A developer-written `snake_case` constant, e.g. `firebase_init_failed`.
  final String event;
  final Map<String, String> fields;

  /// `runtimeType` of the error. Error *messages* are never kept: they can
  /// embed user content (e.g. a FormatException quoting its input).
  final String? errorType;
  final StackTrace? stackTrace;

  String get message {
    final parts = [
      event,
      for (final MapEntry(:key, :value) in fields.entries) '$key=$value',
      if (errorType != null) 'error=$errorType',
    ];
    return parts.join(' ');
  }
}

abstract interface class LogSink {
  void write(LogRecord record);
}

/// Writes to the Dart developer log (IDE / DevTools / `flutter logs`).
class DeveloperLogSink implements LogSink {
  const DeveloperLogSink();

  static const _levels = {
    LogLevel.debug: 500,
    LogLevel.info: 800,
    LogLevel.warning: 900,
    LogLevel.error: 1000,
  };

  @override
  void write(LogRecord record) {
    developer.log(
      record.message,
      name: 'sirf_hum',
      level: _levels[record.level]!,
      stackTrace: record.stackTrace,
    );
  }
}

/// The only sanctioned logging entry point.
///
/// Privacy rules (docs/security/PRIVACY-CONSTITUTION.md) are enforced here,
/// not left to call sites:
/// - events must be `snake_case` constants, never interpolated text;
/// - field values must be [LogValue]-safe types (see `log_value.dart`);
///   anything else, including raw strings, is replaced by `<redacted:Type>`;
/// - errors are reduced to their type name.
///
/// Never log passwords, tokens, keys, plaintext or decrypted content, or
/// media. Identifiers go through [RedactedId].
abstract final class AppLogger {
  static final RegExp _eventPattern = RegExp(r'^[a-z][a-z0-9_]*$');

  static List<LogSink> _sinks = const [DeveloperLogSink()];
  static LogLevel _minimumLevel = kReleaseMode ? LogLevel.info : LogLevel.debug;

  /// Called once at startup (and in tests). Not thread-safe by design: Dart
  /// isolates do not share this state.
  static void configure({
    required List<LogSink> sinks,
    LogLevel? minimumLevel,
  }) {
    _sinks = List.unmodifiable(sinks);
    if (minimumLevel != null) _minimumLevel = minimumLevel;
  }

  static void debug(String event, {Map<String, Object?> fields = const {}}) =>
      _log(LogLevel.debug, event, fields);

  static void info(String event, {Map<String, Object?> fields = const {}}) =>
      _log(LogLevel.info, event, fields);

  static void warning(
    String event, {
    Map<String, Object?> fields = const {},
    Object? error,
    StackTrace? stackTrace,
  }) => _log(LogLevel.warning, event, fields, error, stackTrace);

  static void error(
    String event, {
    Map<String, Object?> fields = const {},
    Object? error,
    StackTrace? stackTrace,
  }) => _log(LogLevel.error, event, fields, error, stackTrace);

  static void _log(
    LogLevel level,
    String event,
    Map<String, Object?> fields, [
    Object? error,
    StackTrace? stackTrace,
  ]) {
    if (level.index < _minimumLevel.index) return;
    assert(
      _eventPattern.hasMatch(event),
      'Log events must be snake_case constants, got "$event".',
    );
    final record = LogRecord(
      level: level,
      event: _eventPattern.hasMatch(event) ? event : 'invalid_event_name',
      fields: {
        for (final MapEntry(:key, :value) in fields.entries)
          key: LogValue.sanitize(value),
      },
      errorType: error?.runtimeType.toString(),
      stackTrace: stackTrace,
    );
    for (final sink in _sinks) {
      try {
        sink.write(record);
      } on Object {
        // A failing sink must never take the app down or recurse into logging.
      }
    }
  }
}
