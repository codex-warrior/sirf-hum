import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sirf_hum/design_system/design_system.dart';
import 'package:sirf_hum/session/session_controller.dart';

/// Moments' entry state. The encrypted media core exists (Prompt 11), but
/// saving and browsing moments is a later prompt: no fake timeline here.
class MomentsScreen extends ConsumerWidget {
  const MomentsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final privateHere = ref.watch(privateContentAvailableProvider);
    return AppPage(
      title: 'Moments',
      subtitle: 'Your story, just for the two of you.',
      children: [
        const EmptyState(
          icon: Icons.photo_outlined,
          title: 'Your first memory is waiting.',
          message:
              'Photos, voice notes and letters, kept only between the two '
              'of you. Saving moments is on its way.',
        ),
        if (!privateHere) ...[
          const SizedBox(height: Spacing.xl),
          const Notice(
            icon: Icons.phone_android_outlined,
            message:
                'Moments stay private to your phones. Open them in the '
                'Sirf Hum app.',
          ),
        ],
      ],
    );
  }
}
