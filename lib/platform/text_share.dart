import 'package:flutter/services.dart';

/// Hands plain text to the system share sheet (WhatsApp, Messages, …).
/// Android only, over the app-owned channel in `MainActivity.kt`.
abstract interface class TextShare {
  Future<void> share(String text);
}

class PlatformTextShare implements TextShare {
  const PlatformTextShare({
    MethodChannel channel = const MethodChannel(channelName),
  }) : _channel = channel;

  static const channelName = 'com.sirfhum.app/share';

  final MethodChannel _channel;

  @override
  Future<void> share(String text) =>
      _channel.invokeMethod<void>('shareText', {'text': text});
}
