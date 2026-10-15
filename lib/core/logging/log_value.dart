import 'package:flutter/foundation.dart';

/// Wraps a developer-chosen string that is known not to contain user data,
/// such as an environment name or a Firebase error *code*.
///
/// Raw strings are redacted by [AppLogger]; wrapping is a deliberate,
/// reviewable act. Never wrap user input, content, tokens or keys.
@immutable
class SafeLogString {
  const SafeLogString(this.value);

  final String value;

  @override
  String toString() => value;
}

/// An identifier shown only as a short prefix plus its length, enough to
/// correlate log lines without revealing the full value.
@immutable
class RedactedId {
  const RedactedId(this._raw);

  static const _visible = 4;

  final String _raw;

  @override
  String toString() {
    if (_raw.isEmpty) return '<empty>';
    final prefix = _raw.length <= _visible ? '' : _raw.substring(0, _visible);
    return '$prefix…(${_raw.length})';
  }
}

abstract final class LogValue {
  /// Converts an allowed value to its log form; redacts everything else.
  static String sanitize(Object? value) {
    return switch (value) {
      null => 'null',
      num() || bool() => value.toString(),
      Enum() => value.name,
      Duration() => '${value.inMilliseconds}ms',
      SafeLogString() || RedactedId() => value.toString(),
      _ => '<redacted:${value.runtimeType}>',
    };
  }
}
