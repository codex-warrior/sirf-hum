import 'dart:io';

import 'package:flutter/painting.dart';
import 'package:image_picker/image_picker.dart';
import 'package:sirf_hum/features/moments/application/moment_photo_picker.dart';

/// [MomentPhotoPicker] over `image_picker` (D-117). On Android 13+ this is
/// the system Photo Picker, which needs no storage permission and shows the
/// app only the chosen photos; older versions use the document picker.
///
/// The plugin hands back temporary copies in the app's private cache.
/// They are plaintext, so [release] deletes them as soon as the core has
/// encrypted them (or the person abandons the memory). No resizing or
/// re-encoding happens here: that would write more plaintext files.
class SystemPhotoPicker implements MomentPhotoPicker {
  const SystemPhotoPicker();

  @override
  Future<List<PickedPhoto>> pick({required int limit}) async {
    if (limit < 1) return const [];
    final picker = ImagePicker();
    final List<XFile> files;
    try {
      files = limit == 1
          ? [?await picker.pickImage(source: ImageSource.gallery)]
          : await picker.pickMultiImage(limit: limit);
    } on Exception {
      throw const PhotoPickerException();
    }
    final out = <PickedPhoto>[];
    for (final f in files.take(limit)) {
      final file = File(f.path);
      out.add(
        PickedPhoto(
          path: f.path,
          sizeBytes: file.existsSync() ? file.lengthSync() : 0,
          preview: FileImage(file),
        ),
      );
    }
    return out;
  }

  @override
  Future<void> release(List<PickedPhoto> photos) async {
    for (final p in photos) {
      try {
        final file = File(p.path);
        if (file.existsSync()) file.deleteSync();
      } on FileSystemException {
        // Best effort: the OS clears the cache directory eventually.
      }
      await p.preview.evict();
    }
  }
}
