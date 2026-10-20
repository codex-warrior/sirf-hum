import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/painting.dart';
import 'package:sirf_hum/features/moments/application/moment_photo_picker.dart';
import 'package:sirf_hum/security/moments/moment.dart';
import 'package:sirf_hum/security/moments/moment_payload.dart';
import 'package:sirf_hum/security/moments/moments_service.dart';

/// A valid 1×1 PNG, so photos really decode in widget tests.
final Uint8List tinyPng = Uint8List.fromList(const [
  0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, 0x00, 0x00, 0x00, 0x0d, //
  0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
  0x08, 0x06, 0x00, 0x00, 0x00, 0x1f, 0x15, 0xc4, 0x89, 0x00, 0x00, 0x00,
  0x0d, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9c, 0x63, 0xf8, 0xcf, 0xc0, 0xf0,
  0x1f, 0x00, 0x05, 0x00, 0x01, 0xff, 0x89, 0x99, 0x3d, 0x1d, 0x00, 0x00,
  0x00, 0x00, 0x49, 0x45, 0x4e, 0x44, 0xae, 0x42, 0x60, 0x82,
]);

/// Handle values look like real message IDs, so tests can prove they never
/// reach the screen or the logs.
String fakeId(int n) => 'feed${n.toRadixString(16).padLeft(28, '0')}';

Moment fakeMoment(
  int n, {
  String? caption,
  int photos = 1,
  int? photoCount,
  DateTime? addedAt,
  MomentDate? memoryDate,
  bool addedByYou = true,
  MomentStatus status = MomentStatus.saved,
  MomentProblem problem = MomentProblem.none,
}) => Moment(
  handle: MomentHandle(fakeId(n)),
  addedAt: addedAt ?? DateTime(2026, 10, 20 - (n % 19), 12),
  addedByYou: addedByYou,
  status: status,
  photos: [for (var i = 0; i < photos; i++) MomentPhoto(fakeId(1000 * n + i))],
  photoCount: photoCount ?? photos,
  problem: problem,
  caption: caption,
  memoryDate: memoryDate,
);

/// A deterministic [MomentsBackend] the test drives. Test-only: the app
/// never imports it (D-116).
class FakeMomentsBackend implements MomentsBackend {
  FakeMomentsBackend([List<MomentEntry>? entries]) : entries = entries ?? [];

  List<MomentEntry> entries;

  /// Thrown by [moments] (e.g. local state corruption).
  Object? loadError;

  /// Thrown by [refresh].
  MomentException? refreshError;

  /// When set, [refresh] waits for it.
  Completer<void>? refreshGate;
  int refreshes = 0;
  int retries = 0;

  final photoErrors = <MomentPhoto, MomentException>{};
  final opened = <MomentPhoto>[];
  final handedOut = <Uint8List>[];

  final created = <MomentDraft>[];
  MomentException? createError;
  Completer<void>? createGate;
  MomentSaveOutcome outcome = MomentSaveOutcome.saved;

  /// Added to [entries] when a save succeeds.
  MomentEntry Function(MomentDraft draft)? onCreated;

  @override
  int get maxPhotos => MomentPayload.maxPhotos;

  @override
  List<MomentEntry> moments() {
    final error = loadError;
    if (error != null) throw error;
    return List.of(entries);
  }

  @override
  Future<void> refresh() async {
    refreshes++;
    await refreshGate?.future;
    final error = refreshError;
    if (error != null) throw error;
  }

  @override
  Future<void> retryPending() async => retries++;

  @override
  Future<MomentSaveOutcome> create(MomentDraft draft) async {
    created.add(draft);
    await createGate?.future;
    final error = createError;
    if (error != null) throw error;
    final make = onCreated;
    if (make != null) entries = [make(draft), ...entries];
    return outcome;
  }

  @override
  Future<Uint8List> openPhoto(MomentPhoto photo) async {
    opened.add(photo);
    final error = photoErrors[photo];
    if (error != null) throw error;
    final bytes = Uint8List.fromList(tinyPng);
    handedOut.add(bytes);
    return bytes;
  }
}

class FakePhotoPicker implements MomentPhotoPicker {
  /// What the next [pick] returns (taken in order, up to the limit).
  List<PickedPhoto> next = [];
  bool fail = false;
  final limits = <int>[];
  final released = <PickedPhoto>[];
  var _n = 0;

  PickedPhoto photo({int size = 1000}) => PickedPhoto(
    path: '/cache/picked_${++_n}.jpg',
    sizeBytes: size,
    preview: MemoryImage(Uint8List.fromList(tinyPng)),
  );

  @override
  Future<List<PickedPhoto>> pick({required int limit}) async {
    limits.add(limit);
    if (fail) throw const PhotoPickerException();
    final out = next;
    next = [];
    return out;
  }

  @override
  Future<void> release(List<PickedPhoto> photos) async =>
      released.addAll(photos);
}
