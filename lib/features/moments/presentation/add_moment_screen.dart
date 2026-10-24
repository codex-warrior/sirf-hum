import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sirf_hum/design_system/design_system.dart';
import 'package:sirf_hum/features/moments/application/moment_composer.dart';
import 'package:sirf_hum/features/moments/application/moment_photo_picker.dart';
import 'package:sirf_hum/security/moments/moment_payload.dart';
import 'package:sirf_hum/security/moments/moments_service.dart';

/// Human copy for a failed save. Every failure means nothing was kept or
/// shared (the service discards what it sealed), so the copy says so.
String saveFailureMessage(MomentFailure? failure) => switch (failure) {
  MomentFailure.noPhotos => 'Choose at least one photo.',
  MomentFailure.tooManyPhotos =>
    'A memory can hold up to ${MomentPayload.maxPhotos} photos.',
  MomentFailure.photoTooLarge =>
    'One of the photos is too large to keep (over 64 MB). Nothing was saved.',
  MomentFailure.photoUnreadable =>
    'One of the photos couldn’t be read. Try choosing it again. Nothing was '
        'saved.',
  MomentFailure.captionTooLong => 'That’s a little long. Try a shorter note.',
  MomentFailure.invalidDate => 'That date hasn’t happened yet.',
  MomentFailure.deviceNotTrusted =>
    'This phone can’t save memories any more. Nothing was saved.',
  MomentFailure.notPaired =>
    'Saving needs your couple to be connected. Nothing was saved.',
  MomentFailure.notReady =>
    'Your phones aren’t connected yet: you both compare your safety '
        'number in Us › Safety first. Nothing was saved.',
  MomentFailure.outboxFull =>
    'A lot is still waiting to upload. Try again once you’re online. Nothing '
        'was saved.',
  MomentFailure.unavailable =>
    'You seem to be offline, so this phone couldn’t check it’s still '
        'trusted. Nothing was saved. Try again when you’re online.',
  _ => 'Your memory couldn’t be saved. Nothing was shared. Try again.',
};

/// "New memory": choose photos, preview, an optional note and date, save.
/// The person sees that the memory is being saved; never how.
class AddMomentScreen extends ConsumerStatefulWidget {
  const AddMomentScreen({super.key});

  @override
  ConsumerState<AddMomentScreen> createState() => _AddMomentScreenState();
}

class _AddMomentScreenState extends ConsumerState<AddMomentScreen> {
  final _caption = TextEditingController();

  @override
  void dispose() {
    _caption.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(momentComposerProvider);
    final composer = ref.read(momentComposerProvider.notifier);
    ref.listen(momentComposerProvider.select((s) => s.phase), (_, phase) {
      if (phase == ComposerPhase.saved) {
        Navigator.of(context).pop(ref.read(momentComposerProvider).outcome);
      }
    });
    final saving = state.phase == ComposerPhase.saving;
    final textTheme = Theme.of(context).textTheme;
    final localizations = MaterialLocalizations.of(context);
    final date = state.memoryDate;

    return PopScope(
      // The photos must stay until the core has read them.
      canPop: !saving,
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            tooltip: 'Close',
            icon: const Icon(Icons.close),
            onPressed: saving ? null : () => Navigator.of(context).maybePop(),
          ),
          title: const Text('New memory'),
        ),
        body: AppPage(
          title: 'Keep a memory',
          subtitle: 'Choose up to ${composer.maxPhotos} photos.',
          children: [
            if (state.photos.isEmpty)
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: FilledButton.icon(
                  onPressed: composer.canPick ? composer.pick : null,
                  icon: const Icon(Icons.photo_library_outlined),
                  label: const Text('Choose photos'),
                ),
              )
            else ...[
              _Previews(state: state, onRemove: composer.remove),
              if (state.photos.length < composer.maxPhotos) ...[
                const SizedBox(height: Spacing.md),
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: OutlinedButton.icon(
                    onPressed: composer.canPick ? composer.pick : null,
                    icon: const Icon(Icons.add),
                    label: const Text('Add more photos'),
                  ),
                ),
              ],
            ],
            if (state.pickerFailed) ...[
              const SizedBox(height: Spacing.md),
              const Notice(
                icon: Icons.photo_outlined,
                message: 'Your photos couldn’t be opened. Try again.',
              ),
            ],
            const SizedBox(height: Spacing.xl),
            TextField(
              controller: _caption,
              enabled: !saving,
              onChanged: composer.setCaption,
              maxLines: 4,
              minLines: 1,
              maxLength: 500,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Say something about it (optional)',
              ),
            ),
            const SizedBox(height: Spacing.lg),
            MergeSemantics(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('When was this?', style: textTheme.labelLarge),
                  const SizedBox(height: Spacing.xs),
                  Text(
                    date == null
                        ? 'The day you save it'
                        : localizations.formatFullDate(date.toLocal()),
                    style: textTheme.bodyLarge?.copyWith(
                      color: context.colors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            Wrap(
              spacing: Spacing.sm,
              children: [
                TextButton(
                  onPressed: saving ? null : () => _pickDate(date),
                  child: Text(date == null ? 'Choose a date' : 'Change date'),
                ),
                if (date != null)
                  TextButton(
                    onPressed: saving ? null : () => composer.setDate(null),
                    child: const Text('Remove date'),
                  ),
              ],
            ),
            const SizedBox(height: Spacing.xl),
            if (state.failed) ...[
              Semantics(
                liveRegion: true,
                child: Text(
                  saveFailureMessage(state.failure),
                  style: textTheme.bodyLarge?.copyWith(
                    color: context.colors.danger,
                  ),
                ),
              ),
              const SizedBox(height: Spacing.lg),
            ],
            if (saving) ...[
              Semantics(
                liveRegion: true,
                child: Text('Saving your memory…', style: textTheme.bodyLarge),
              ),
              const SizedBox(height: Spacing.sm),
              const LinearProgressIndicator(),
              const SizedBox(height: Spacing.lg),
            ],
            FilledButton(
              onPressed: state.canSave ? composer.save : null,
              child: const Text('Save memory'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickDate(MomentDate? current) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: current?.toLocal() ?? now,
      firstDate: DateTime(MomentDate.minYear),
      lastDate: now,
      helpText: 'When was this?',
    );
    if (picked != null && mounted) {
      ref.read(momentComposerProvider.notifier).setDate(MomentDate.of(picked));
    }
  }
}

class _Previews extends StatelessWidget {
  const _Previews({required this.state, required this.onRemove});

  final MomentComposerState state;
  final void Function(PickedPhoto) onRemove;

  @override
  Widget build(BuildContext context) {
    final editing = state.phase == ComposerPhase.editing;
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = WindowSize.of(context) == WindowSize.compact ? 3 : 4;
        final size =
            (constraints.maxWidth - Spacing.xs * (columns - 1)) / columns;
        final pixels = (size * MediaQuery.devicePixelRatioOf(context)).round();
        return Wrap(
          spacing: Spacing.xs,
          runSpacing: Spacing.xs,
          children: [
            for (final (i, photo) in state.photos.indexed)
              SizedBox.square(
                dimension: size,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(Radii.sm),
                      child: Image(
                        image: ResizeImage(photo.preview, width: pixels),
                        fit: BoxFit.cover,
                        semanticLabel: 'Chosen photo ${i + 1}',
                        errorBuilder: (context, _, _) =>
                            ColoredBox(color: context.colors.surfaceMuted),
                      ),
                    ),
                    if (editing)
                      PositionedDirectional(
                        top: 0,
                        end: 0,
                        child: IconButton.filledTonal(
                          tooltip: 'Remove photo ${i + 1}',
                          icon: const Icon(Icons.close),
                          onPressed: () => onRemove(photo),
                        ),
                      ),
                  ],
                ),
              ),
          ],
        );
      },
    );
  }
}
