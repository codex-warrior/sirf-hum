import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sirf_hum/core/logging/app_logger.dart';
import 'package:sirf_hum/features/moments/application/moment_photo_picker.dart';
import 'package:sirf_hum/features/moments/application/moments_controller.dart';
import 'package:sirf_hum/security/moments/moment_payload.dart';
import 'package:sirf_hum/security/moments/moments_service.dart';

enum ComposerPhase {
  /// Choosing photos, a caption and a date.
  editing,

  /// The system picker is open.
  picking,

  /// Encrypting and uploading. The screen cannot be left meanwhile: the
  /// picked files must stay until the core has read them.
  saving,

  /// Done; [MomentComposerState.outcome] says how far it got.
  saved,
}

/// The "new memory" screen's state (D-115). [caption] and [memoryDate] are
/// private content.
class MomentComposerState {
  const MomentComposerState({
    this.photos = const [],
    this.caption = '',
    this.memoryDate,
    this.phase = ComposerPhase.editing,
    this.failure,
    this.failed = false,
    this.pickerFailed = false,
    this.outcome,
  });

  final List<PickedPhoto> photos;
  final String caption;
  final MomentDate? memoryDate;
  final ComposerPhase phase;

  /// The last save failed: nothing was kept or sent. [failure] is its
  /// category (null for an unexpected local problem).
  final bool failed;
  final MomentFailure? failure;

  /// The picker could not open.
  final bool pickerFailed;
  final MomentSaveOutcome? outcome;

  bool get canSave => photos.isNotEmpty && phase == ComposerPhase.editing;

  MomentComposerState copyWith({
    List<PickedPhoto>? photos,
    String? caption,
    MomentDate? Function()? memoryDate,
    ComposerPhase? phase,
    bool failed = false,
    MomentFailure? failure,
    bool pickerFailed = false,
    MomentSaveOutcome? outcome,
  }) => MomentComposerState(
    photos: photos ?? this.photos,
    caption: caption ?? this.caption,
    memoryDate: memoryDate == null ? this.memoryDate : memoryDate(),
    phase: phase ?? this.phase,
    failed: failed,
    failure: failure,
    pickerFailed: pickerFailed,
    outcome: outcome ?? this.outcome,
  );

  @override
  String toString() =>
      'MomentComposerState(${phase.name}, ${photos.length} photos)';
}

final momentComposerProvider =
    NotifierProvider.autoDispose<MomentComposer, MomentComposerState>(
      MomentComposer.new,
    );

/// Builds one moment from the person's choices and saves it once.
///
/// - Single flight: a second tap while saving does nothing, and a saved
///   composer cannot save again, so one memory is never created twice.
/// - A failed save kept nothing (the service discards what it sealed), so
///   the photos stay chosen and "Save" may be tried again.
/// - The picker's temporary plaintext copies are deleted when the composer
///   goes away — after any save still reading them.
class MomentComposer extends Notifier<MomentComposerState> {
  List<PickedPhoto> _owned = const [];
  Future<void>? _saving;

  @override
  MomentComposerState build() {
    final picker = ref.read(momentPhotoPickerProvider);
    ref.onDispose(() {
      final owned = _owned;
      _owned = const [];
      if (picker == null || owned.isEmpty) return;
      unawaited(
        (_saving ?? Future<void>.value()).whenComplete(
          () => picker.release(owned),
        ),
      );
    });
    return const MomentComposerState();
  }

  int get maxPhotos =>
      ref.read(momentsBackendProvider)?.maxPhotos ?? MomentPayload.maxPhotos;

  bool get canPick =>
      ref.read(momentPhotoPickerProvider) != null &&
      state.phase == ComposerPhase.editing &&
      state.photos.length < maxPhotos;

  Future<void> pick() async {
    final picker = ref.read(momentPhotoPickerProvider);
    if (picker == null || !canPick) return;
    state = state.copyWith(phase: ComposerPhase.picking);
    List<PickedPhoto> picked;
    var pickerFailed = false;
    try {
      picked = await picker.pick(limit: maxPhotos - state.photos.length);
    } on PhotoPickerException {
      picked = const [];
      pickerFailed = true;
    }
    if (!ref.mounted) {
      await picker.release(picked);
      return;
    }
    final known = {for (final p in state.photos) p.path};
    final fresh = [
      for (final p in picked)
        if (known.add(p.path)) p,
    ];
    final room = maxPhotos - state.photos.length;
    final kept = fresh.take(room).toList();
    unawaited(picker.release(fresh.skip(room).toList()));
    _owned = [..._owned, ...kept];
    state = state.copyWith(
      photos: [...state.photos, ...kept],
      phase: ComposerPhase.editing,
      pickerFailed: pickerFailed,
    );
  }

  void remove(PickedPhoto photo) {
    if (state.phase != ComposerPhase.editing) return;
    state = state.copyWith(
      photos: [
        for (final p in state.photos)
          if (p != photo) p,
      ],
    );
    _owned = [
      for (final p in _owned)
        if (p != photo) p,
    ];
    unawaited(ref.read(momentPhotoPickerProvider)?.release([photo]));
  }

  void setCaption(String caption) {
    if (state.phase != ComposerPhase.editing) return;
    state = state.copyWith(caption: caption);
  }

  void setDate(MomentDate? date) {
    if (state.phase != ComposerPhase.editing) return;
    state = state.copyWith(memoryDate: () => date);
  }

  Future<void> save() async {
    final backend = ref.read(momentsBackendProvider);
    if (!state.canSave) return;
    if (backend == null) {
      state = state.copyWith(failed: true, failure: MomentFailure.unsupported);
      return;
    }
    final draft = MomentDraft(
      photos: [
        for (final p in state.photos)
          MomentInput(path: p.path, sizeBytes: p.sizeBytes),
      ],
      caption: state.caption,
      memoryDate: state.memoryDate,
    );
    state = state.copyWith(phase: ComposerPhase.saving);
    final done = Completer<void>();
    _saving = done.future;
    try {
      final outcome = await backend.create(draft);
      if (!ref.mounted) return;
      state = state.copyWith(phase: ComposerPhase.saved, outcome: outcome);
      unawaited(ref.read(momentsProvider.notifier).saved());
    } on MomentException catch (e) {
      if (!ref.mounted) return;
      state = state.copyWith(
        phase: ComposerPhase.editing,
        failed: true,
        failure: e.failure,
      );
    } on Object catch (error) {
      AppLogger.warning('moment_compose_failed', error: error);
      if (!ref.mounted) return;
      state = state.copyWith(phase: ComposerPhase.editing, failed: true);
    } finally {
      done.complete();
    }
  }
}
