import 'package:flutter_test/flutter_test.dart';
import 'package:sirf_hum/core/logging/app_logger.dart';
import 'package:sirf_hum/core/logging/log_value.dart';

class _RecordingSink implements LogSink {
  final records = <LogRecord>[];

  @override
  void write(LogRecord record) => records.add(record);
}

class _ThrowingSink implements LogSink {
  @override
  void write(LogRecord record) => throw StateError('sink down');
}

enum _Mode { quick }

void main() {
  late _RecordingSink sink;

  setUp(() {
    sink = _RecordingSink();
    AppLogger.configure(sinks: [sink], minimumLevel: LogLevel.debug);
  });

  tearDown(
    () => AppLogger.configure(
      sinks: const [DeveloperLogSink()],
      minimumLevel: LogLevel.debug,
    ),
  );

  test('allowed field types pass through', () {
    AppLogger.info(
      'call_started',
      fields: {
        'count': 3,
        'ok': true,
        'mode': _Mode.quick,
        'took': const Duration(milliseconds: 42),
        'code': const SafeLogString('permission-denied'),
        'none': null,
      },
    );

    expect(sink.records.single.fields, {
      'count': '3',
      'ok': 'true',
      'mode': 'quick',
      'took': '42ms',
      'code': 'permission-denied',
      'none': 'null',
    });
  });

  test('raw strings and other objects are redacted', () {
    AppLogger.info(
      'message_sent',
      fields: {
        'text': 'I miss you',
        'payload': [1, 2, 3],
        'map': {'k': 'v'},
      },
    );

    final fields = sink.records.single.fields;
    expect(fields['text'], '<redacted:String>');
    expect(fields.values.join(), isNot(contains('miss')));
    expect(fields['payload'], startsWith('<redacted:'));
    expect(fields['map'], startsWith('<redacted:'));
  });

  test('identifiers are shortened, not printed in full', () {
    AppLogger.info(
      'device_seen',
      fields: {'device': const RedactedId('abcdef123456')},
    );
    expect(sink.records.single.fields['device'], 'abcd…(12)');
    expect(const RedactedId('abc').toString(), '…(3)');
  });

  test('errors keep only their type, never their message', () {
    AppLogger.error(
      'parse_failed',
      error: const FormatException('secret letter text'),
      stackTrace: StackTrace.current,
    );

    final record = sink.records.single;
    expect(record.errorType, 'FormatException');
    expect(record.message, isNot(contains('secret')));
    expect(record.stackTrace, isNotNull);
  });

  test('event names must be snake_case constants', () {
    expect(
      () => AppLogger.info('User said hello'),
      throwsA(isA<AssertionError>()),
    );
  });

  test('records below the minimum level are dropped', () {
    AppLogger.configure(sinks: [sink], minimumLevel: LogLevel.warning);
    AppLogger.debug('noise');
    AppLogger.info('noise');
    AppLogger.warning('kept');
    expect(sink.records.map((r) => r.event), ['kept']);
  });

  test('a failing sink does not break logging to other sinks', () {
    AppLogger.configure(sinks: [_ThrowingSink(), sink]);
    AppLogger.info('still_logged');
    expect(sink.records.single.event, 'still_logged');
  });
}
