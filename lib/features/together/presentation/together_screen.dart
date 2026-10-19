import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sirf_hum/design_system/design_system.dart';
import 'package:sirf_hum/session/session_controller.dart';

/// Together's entry state. Calls, Watch Together and Listen Together are
/// later prompts; nothing here pretends otherwise.
class TogetherScreen extends ConsumerWidget {
  const TogetherScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final privateHere = ref.watch(privateContentAvailableProvider);
    return AppPage(
      title: 'Together',
      subtitle: 'Spend time together, wherever you are.',
      children: [
        const EmptyState(
          icon: Icons.people_outline,
          title: 'Start something together.',
          message:
              'Calls, watching and listening together will live here. '
              'They’re on their way.',
        ),
        if (!privateHere) ...[
          const SizedBox(height: Spacing.xl),
          const Notice(
            icon: Icons.phone_android_outlined,
            message:
                'Calls and time together open in the Sirf Hum app on '
                'your phone.',
          ),
        ],
      ],
    );
  }
}
