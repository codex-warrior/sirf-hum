import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sirf_hum/design_system/design_system.dart';
import 'package:sirf_hum/session/session_controller.dart';
import 'package:sirf_hum/session/session_state.dart';

/// Signed in without a couple. Explains pairing and reflects where an open
/// pairing stands, as the server reports it.
///
/// It performs no pairing step: invitations, acceptance and confirmation are
/// signed by the device key through `PairingService` (D-101, D-102), and
/// their screens belong to the pairing UI prompt. Nothing here can make the
/// session paired; "Check again" only asks the server.
class PairScreen extends ConsumerWidget {
  const PairScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionProvider);
    final controller = ref.read(sessionProvider.notifier);
    final textTheme = Theme.of(context).textTheme;
    final canPairHere = switch (session) {
      SessionNotPaired(:final canPairHere) => canPairHere,
      SessionPairing(:final canPairHere) => canPairHere,
      _ => ref.watch(privateContentAvailableProvider),
    };
    final (title, message) = switch (session) {
      SessionPairing(stage: PairingStage.invitationSent) => (
        'Your invitation is out.',
        'When your person accepts, you’ll both see a six-digit code. '
            'Compare it together before you confirm.',
      ),
      SessionPairing(stage: PairingStage.partnerAccepted) => (
        'Your person accepted.',
        'Compare your six-digit codes together. Confirm only if they match.',
      ),
      SessionPairing(stage: PairingStage.waitingForPartner) => (
        'Almost there.',
        'Your person will confirm once you’ve compared your six-digit '
            'codes together.',
      ),
      _ => (
        'Invite your person.',
        'Sirf Hum is for exactly two people. Pairing connects your two '
            'accounts, never your passwords or your phones.',
      ),
    };

    return Scaffold(
      body: AppPage(
        title: 'Sirf Hum',
        children: [
          Semantics(
            header: true,
            child: Text(title, style: textTheme.titleLarge),
          ),
          const SizedBox(height: Spacing.sm),
          Text(
            message,
            style: textTheme.bodyLarge?.copyWith(
              color: context.colors.textSecondary,
            ),
          ),
          if (session is! SessionPairing) ...[
            const SizedBox(height: Spacing.xl),
            const _Step(number: 1, text: 'Send your person an invitation.'),
            const _Step(number: 2, text: 'They accept on their phone.'),
            const _Step(
              number: 3,
              text: 'You compare a six-digit code, then confirm.',
            ),
          ],
          const SizedBox(height: Spacing.xl),
          Notice(
            icon: canPairHere
                ? Icons.schedule_outlined
                : Icons.phone_android_outlined,
            message: canPairHere
                ? 'Pairing opens in an upcoming version of Sirf Hum.'
                : 'Pairing happens in the Sirf Hum app on your phone, where '
                      'your keys live.',
          ),
          const SizedBox(height: Spacing.xl),
          Wrap(
            spacing: Spacing.sm,
            runSpacing: Spacing.sm,
            children: [
              OutlinedButton(
                onPressed: controller.refresh,
                child: const Text('Check again'),
              ),
              TextButton(
                onPressed: controller.signOut,
                child: const Text('Sign out'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Step extends StatelessWidget {
  const _Step({required this.number, required this.text});

  final int number;
  final String text;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return MergeSemantics(
      child: Padding(
        padding: const EdgeInsets.only(bottom: Spacing.md),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: Spacing.xl,
              child: Text(
                '$number',
                style: textTheme.bodyLarge?.copyWith(
                  color: context.colors.accent,
                  fontWeight: FontWeights.semibold,
                ),
              ),
            ),
            Expanded(child: Text(text, style: textTheme.bodyLarge)),
          ],
        ),
      ),
    );
  }
}
