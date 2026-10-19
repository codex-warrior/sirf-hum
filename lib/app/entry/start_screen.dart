import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sirf_hum/design_system/design_system.dart';
import 'package:sirf_hum/features/home/presentation/home_screen.dart';
import 'package:sirf_hum/session/session_controller.dart';
import 'package:sirf_hum/session/session_state.dart';

/// Shown while the session is being established, and when it cannot be.
/// Loading looks like Home (that is usually where the user lands); failure
/// is human copy with one way forward. Backend errors never reach here as
/// text: [SessionUnavailable] carries a category only.
class StartScreen extends ConsumerWidget {
  const StartScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionProvider);
    final controller = ref.read(sessionProvider.notifier);

    return Scaffold(
      body: switch (session) {
        SessionUnavailable(problem: SessionProblem.unreachable) => AppPage(
          title: 'Sirf Hum',
          children: [
            ErrorState(
              title: 'We couldn’t reach Sirf Hum.',
              message:
                  'Check your connection, then try again. Nothing on your '
                  'phone has changed.',
              action: StateAction(
                label: 'Try again',
                onPressed: controller.refresh,
              ),
            ),
          ],
        ),
        SessionUnavailable(problem: SessionProblem.signInAgain) => AppPage(
          title: 'Sirf Hum',
          children: [
            ErrorState(
              title: 'Please sign in again.',
              message:
                  'Your sign-in has ended. Your couple and your phone’s '
                  'keys are unchanged.',
              action: StateAction(
                label: 'Sign out',
                onPressed: controller.signOut,
              ),
            ),
          ],
        ),
        SessionUnavailable(problem: SessionProblem.startFailed) =>
          const AppPage(
            title: 'Sirf Hum',
            children: [
              ErrorState(
                title: 'Sirf Hum couldn’t start.',
                message:
                    'Close Sirf Hum and open it again. If you’re offline, '
                    'connect first. Nothing on your phone has changed.',
              ),
            ],
          ),
        _ => const HomeSkeleton(),
      },
    );
  }
}
