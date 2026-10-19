import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sirf_hum/design_system/design_system.dart';
import 'package:sirf_hum/session/session_controller.dart';

/// The couple and this account. Shows the two display names (D-100) and
/// offers sign-out. Profile editing, devices and privacy settings are later
/// prompts and are named as such, not mocked.
class UsScreen extends ConsumerWidget {
  const UsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final couple = ref.watch(pairedCoupleProvider);
    final names = couple?.names;
    final textTheme = Theme.of(context).textTheme;

    return AppPage(
      title: 'Us',
      subtitle: 'The two of you.',
      children: [
        AppSection(
          title: 'Your couple',
          divider: false,
          child: Row(
            children: [
              CoupleMark(
                yours: CoupleMark.initialOf(names?.yours),
                partner: CoupleMark.initialOf(names?.partner),
              ),
              const SizedBox(width: Spacing.lg),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(names?.yours ?? 'You', style: textTheme.titleMedium),
                    Text(
                      names?.partner ?? 'Your person',
                      style: textTheme.titleMedium,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const AppSection(
          title: 'Coming to Us',
          child: Notice(
            icon: Icons.schedule_outlined,
            message:
                'Your profile, rituals, letters, devices and privacy '
                'settings will live here.',
          ),
        ),
        AppSection(
          title: 'Account',
          child: Align(
            alignment: AlignmentDirectional.centerStart,
            child: OutlinedButton.icon(
              onPressed: () => _confirmSignOut(context, ref),
              icon: const Icon(Icons.logout),
              label: const Text('Sign out'),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _confirmSignOut(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Sign out of Sirf Hum?'),
        content: const Text('Your couple stays as it is. Nothing is deleted.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Stay'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Sign out'),
          ),
        ],
      ),
    );
    if (confirmed ?? false) {
      await ref.read(sessionProvider.notifier).signOut();
    }
  }
}
