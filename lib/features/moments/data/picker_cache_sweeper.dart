import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:sirf_hum/core/logging/app_logger.dart';

/// Removes plaintext photo copies that `image_picker_android` left in the
/// app cache when the process died before `SystemPhotoPicker.release` ran
/// (P2-3, E81, D-141).
///
/// The plugin copies each chosen photo to `cacheDir/<random UUID>/<name>`
/// (`FileUtils.getPathFromUri`, image_picker_android 0.8.13). The sweep only
/// deletes directories with exactly that shape: a lowercase version-4 UUID
/// name holding nothing but regular files. Anything else in the cache (other
/// libraries, the engine) is left alone. It runs once at start-up, before
/// any composer can hold a photo, so it never deletes a copy still in use.
///
/// What it does not do: wipe the bytes (flash storage cannot be reliably
/// overwritten) or reach copies the OS already moved elsewhere. The photo
/// is still in the person's gallery; the copy only lived in app-private
/// storage excluded from backup (D-123).
class PickerCacheSweeper {
  const PickerCacheSweeper({
    MethodChannel channel = const MethodChannel(channelName),
    bool? supported,
  }) : _channel = channel,
       _supportedOverride = supported;

  static const channelName = 'com.sirfhum.app/app_cache';

  final MethodChannel _channel;
  final bool? _supportedOverride;

  /// Android only: the picker's cache layout is Android's. Web never picks
  /// photos (D-046).
  bool get isSupported =>
      _supportedOverride ??
      (!kIsWeb && defaultTargetPlatform == TargetPlatform.android);

  /// Best effort and never throws: a failed sweep must not stop start-up.
  /// Returns how many directories were removed.
  Future<int> sweepAtStartup() async {
    if (!isSupported) return 0;
    try {
      final path = await _channel.invokeMethod<String>('cacheDirectory');
      if (path == null || path.isEmpty) return 0;
      final removed = sweepDirectory(Directory(path));
      AppLogger.info('picker_cache_swept', fields: {'removed': removed});
      return removed;
    } on Object catch (error, stackTrace) {
      AppLogger.warning(
        'picker_cache_sweep_failed',
        error: error,
        stackTrace: stackTrace,
      );
      return 0;
    }
  }

  static final _pickerDirectory = RegExp(
    r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
  );

  /// Deletes every picker-shaped directory directly under [cache]. Never
  /// follows links, never descends into nested directories.
  @visibleForTesting
  static int sweepDirectory(Directory cache) {
    if (!cache.existsSync()) return 0;
    var removed = 0;
    for (final entry in cache.listSync(followLinks: false)) {
      if (entry is! Directory) continue;
      final name = entry.uri.pathSegments.lastWhere(
        (s) => s.isNotEmpty,
        orElse: () => '',
      );
      if (!_pickerDirectory.hasMatch(name)) continue;
      try {
        final contents = entry.listSync(followLinks: false);
        if (contents.any((e) => e is! File)) continue;
        for (final file in contents) {
          file.deleteSync();
        }
        entry.deleteSync();
        removed += 1;
      } on FileSystemException {
        // Best effort: whatever stays, the OS may clear with the cache.
      }
    }
    return removed;
  }
}
