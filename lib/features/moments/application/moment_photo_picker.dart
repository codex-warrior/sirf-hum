import 'package:flutter/painting.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// A photo the person chose. [path] is a file the picker owns (a temporary
/// copy on Android); the app only reads it, inside the crypto core, and
/// never copies it (D-096, D-117). Private: never log it.
class PickedPhoto {
  const PickedPhoto({
    required this.path,
    required this.sizeBytes,
    required this.preview,
  });

  final String path;
  final int sizeBytes;

  /// For the preview before saving (memory only).
  final ImageProvider preview;

  @override
  String toString() => 'PickedPhoto(<redacted>)';
}

class PhotoPickerException implements Exception {
  const PhotoPickerException();

  @override
  String toString() => 'PhotoPickerException()';
}

/// The device's photo picker (D-117). No library access, no scanning: the
/// person chooses, the app sees only what was chosen.
abstract interface class MomentPhotoPicker {
  /// At most [limit] photos; empty when the person cancels. Failures are
  /// [PhotoPickerException]s.
  Future<List<PickedPhoto>> pick({required int limit});

  /// Deletes the picker's temporary copies (best effort). Called once the
  /// photos are encrypted, or abandoned.
  Future<void> release(List<PickedPhoto> photos);
}

/// Overridden in `main.dart` with `SystemPhotoPicker` on Android. `null`
/// (web, where private media never exists, D-046; tests without one) means
/// no photos can be chosen here.
final momentPhotoPickerProvider = Provider<MomentPhotoPicker?>((ref) => null);
