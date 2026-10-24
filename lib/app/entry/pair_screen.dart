import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sirf_hum/design_system/design_system.dart';
import 'package:sirf_hum/features/pairing/application/pairing_controller.dart';
import 'package:sirf_hum/features/pairing/domain/pairing_view_state.dart';
import 'package:sirf_hum/security/couple/pairing.dart';
import 'package:sirf_hum/session/session_controller.dart';

/// Signed in without a couple: set this phone up, then invite your person
/// or join their invitation, then compare the six-digit code (D-101–D-104,
/// D-131). Every step is decided by the server through [pairingProvider];
/// nothing here can make the session paired.
class PairScreen extends ConsumerWidget {
  const PairScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(pairingProvider);
    final controller = ref.read(pairingProvider.notifier);
    final signOut = ref.read(sessionProvider.notifier).signOut;

    return Scaffold(
      body: AppPage(
        header: const _Brand(),
        children: [
          AnimatedSwitcher(
            duration: Motion.resolve(context, Motion.standard),
            child: KeyedSubtree(
              key: ValueKey(state.runtimeType),
              child: switch (state) {
                PairingSettingUp() => const _Progress(
                  title: 'Setting up this phone…',
                  message: 'This happens once.',
                ),
                PairingDeviceWaiting(:final code) => _DeviceWaiting(code: code),
                PairingDeviceUnavailable(:final problem) => _DeviceProblem(
                  problem: problem,
                  onRetry: controller.retry,
                ),
                PairingChoose() => _Choose(state: state),
                PairingJoin() => _Join(state: state),
                PairingInviteOut() => _InviteOut(state: state),
                PairingShowCode() => _ShowCode(state: state),
                PairingEnterCode() => _EnterCode(state: state),
              },
            ),
          ),
          const SizedBox(height: Spacing.xxl),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton(
              onPressed: signOut,
              child: const Text('Sign out'),
            ),
          ),
        ],
      ),
    );
  }
}

/// Human copy for each pairing failure; never tokens, codes or names.
String pairingFailureMessage(PairingFailure failure) => switch (failure) {
  PairingFailure.invitationInvalid =>
    'That invite can’t be used. It may have expired or been used already. '
        'Ask your person to send a new one.',
  PairingFailure.pairingNotFound ||
  PairingFailure.pairingNotOpen ||
  PairingFailure.pairingExpired =>
    'That invite has ended. Start again with a new one.',
  PairingFailure.pairingInvalidated =>
    'That invite was closed for safety. Start again with a new one.',
  PairingFailure.pairingInProgress =>
    'You already have an invite open. Finish or cancel it first.',
  PairingFailure.confirmationCodeInvalid =>
    'That code doesn’t match. Check the code on your person’s phone and '
        'try again.',
  PairingFailure.alreadyPaired => 'One of you is already paired.',
  PairingFailure.identityResetPending =>
    'This account is being reset, so it can’t pair right now.',
  PairingFailure.coupleUnavailable => 'That couple no longer exists.',
  PairingFailure.deviceNotTrusted =>
    'This phone isn’t set up for this account. Sign out and in again.',
  PairingFailure.challengeRefused ||
  PairingFailure.unavailable => 'Something went wrong. Try again.',
  PairingFailure.rateLimited =>
    'Too many tries for now. Wait a little, then try again.',
  PairingFailure.unauthenticated => 'Please sign in again.',
  PairingFailure.invalidRequest => 'Enter the six digits shown on their phone.',
};

class _Brand extends StatelessWidget {
  const _Brand();

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: Spacing.xl),
    child: Row(
      children: [
        const SirfHumMark(size: IconSizes.lg),
        const SizedBox(width: Spacing.sm),
        Text('Sirf Hum', style: Theme.of(context).textTheme.titleMedium),
      ],
    ),
  );
}

/// A screen's heading and its explanation.
class _Lead extends StatelessWidget {
  const _Lead({required this.title, this.message});

  final String title;
  final String? message;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final message = this.message;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(
          header: true,
          child: Text(title, style: textTheme.headlineMedium),
        ),
        if (message != null) ...[
          const SizedBox(height: Spacing.sm),
          Text(
            message,
            style: textTheme.bodyLarge?.copyWith(
              color: context.colors.textSecondary,
            ),
          ),
        ],
      ],
    );
  }
}

class _Failure extends StatelessWidget {
  const _Failure(this.failure);

  final PairingFailure? failure;

  @override
  Widget build(BuildContext context) {
    final failure = this.failure;
    if (failure == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: Spacing.md),
      child: Semantics(
        liveRegion: true,
        child: Text(
          pairingFailureMessage(failure),
          style: Theme.of(
            context,
          ).textTheme.bodyMedium?.copyWith(color: context.colors.danger),
        ),
      ),
    );
  }
}

/// A wide button at thumb size; shows progress while [busy].
class _WideButton extends StatelessWidget {
  const _WideButton({
    required this.label,
    required this.onPressed,
    this.icon,
    this.busy = false,
    this.primary = true,
  });

  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final bool busy;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    final icon = this.icon;
    final child = busy
        ? const SizedBox.square(
            dimension: IconSizes.md,
            child: CircularProgressIndicator(strokeWidth: Spacing.xxs),
          )
        : Text(label);
    const style = ButtonStyle(
      minimumSize: WidgetStatePropertyAll(
        Size.fromHeight(TouchTargets.comfortable),
      ),
      textStyle: WidgetStatePropertyAll(TypeScale.bodyStrong),
    );
    final pressed = busy ? null : onPressed;
    return Semantics(
      button: true,
      label: busy ? '$label, in progress' : null,
      child: primary
          ? (icon == null || busy
                ? FilledButton(onPressed: pressed, style: style, child: child)
                : FilledButton.icon(
                    onPressed: pressed,
                    style: style,
                    icon: Icon(icon),
                    label: child,
                  ))
          : (icon == null || busy
                ? OutlinedButton(onPressed: pressed, style: style, child: child)
                : OutlinedButton.icon(
                    onPressed: pressed,
                    style: style,
                    icon: Icon(icon),
                    label: child,
                  )),
    );
  }
}

class _Progress extends StatelessWidget {
  const _Progress({required this.title, required this.message});

  final String title;
  final String message;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _Lead(title: title, message: message),
      const SizedBox(height: Spacing.xl),
      const LinearProgressIndicator(),
    ],
  );
}

class _Waiting extends StatelessWidget {
  const _Waiting(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Semantics(
    liveRegion: true,
    child: Row(
      children: [
        // An endless spinner is motion; with reduced motion, a still icon.
        SizedBox.square(
          dimension: IconSizes.sm,
          child: MediaQuery.disableAnimationsOf(context)
              ? Icon(
                  Icons.hourglass_empty,
                  size: IconSizes.sm,
                  color: context.colors.textSecondary,
                )
              : const CircularProgressIndicator(strokeWidth: Spacing.xxs),
        ),
        const SizedBox(width: Spacing.md),
        Expanded(
          child: Text(
            text,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: context.colors.textSecondary,
            ),
          ),
        ),
      ],
    ),
  );
}

/// A soft panel that sets one important thing apart.
class _Panel extends StatelessWidget {
  const _Panel({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: context.colors.surfaceMuted,
      borderRadius: BorderRadius.circular(Radii.lg),
      border: Border.all(color: context.colors.border),
    ),
    child: Padding(padding: const EdgeInsets.all(Spacing.xl), child: child),
  );
}

class _DeviceWaiting extends StatelessWidget {
  const _DeviceWaiting({required this.code});

  final int code;

  @override
  Widget build(BuildContext context) {
    final digits = code.toString().padLeft(6, '0');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _Lead(
          title: 'This account is set up on another phone.',
          message:
              'A new phone must be approved from the phone this account '
              'already uses. Approving phones arrives in an upcoming version '
              'of Sirf Hum; until then, use your first phone.',
        ),
        const SizedBox(height: Spacing.xl),
        _Panel(
          child: Semantics(
            label: 'Approval code ${digits.split('').join(' ')}',
            child: ExcludeSemantics(
              child: Text(
                '${digits.substring(0, 3)} ${digits.substring(3)}',
                style: Theme.of(context).textTheme.displaySmall,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _DeviceProblem extends StatelessWidget {
  const _DeviceProblem({required this.problem, required this.onRetry});

  final PairingDeviceProblem problem;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => switch (problem) {
    PairingDeviceProblem.needsPhone => const Notice(
      icon: Icons.phone_android_outlined,
      message:
          'Pairing happens in the Sirf Hum app on your phone, where your '
          'keys live.',
    ),
    PairingDeviceProblem.removed => const ErrorState(
      title: 'This phone was removed from your account.',
      message:
          'It can’t be used for this account again. Removing and setting '
          'it up again arrives in an upcoming version.',
    ),
    PairingDeviceProblem.unreadable => const ErrorState(
      title: 'This phone’s keys can’t be opened.',
      message:
          'Nothing was deleted. Restarting the phone may help; if it '
          'doesn’t, this phone needs to be set up again.',
    ),
    PairingDeviceProblem.failed => ErrorState(
      title: 'We couldn’t set up this phone.',
      message: 'Check your connection, then try again.',
      action: StateAction(label: 'Try again', onPressed: onRetry),
    ),
  };
}

class _Choose extends ConsumerWidget {
  const _Choose({required this.state});

  final PairingChoose state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(pairingProvider.notifier);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _Lead(
          title: 'Bring your person in.',
          message:
              'Sirf Hum is for exactly two people. One of you sends an '
              'invite; the other joins with it.',
        ),
        const SizedBox(height: Spacing.xxl),
        _WideButton(
          label: 'Invite your person',
          icon: Icons.send_outlined,
          busy: state.busy,
          onPressed: controller.invite,
        ),
        const SizedBox(height: Spacing.md),
        _WideButton(
          label: 'I have an invite',
          icon: Icons.mark_email_unread_outlined,
          primary: false,
          onPressed: state.busy ? null : controller.startJoin,
        ),
        _Failure(state.failure),
        const SizedBox(height: Spacing.xxl),
        const _Step(number: 1, text: 'One of you sends an invite.'),
        const _Step(number: 2, text: 'The other pastes it in Sirf Hum.'),
        const _Step(
          number: 3,
          text: 'The inviter types the code shown on the other phone.',
        ),
      ],
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
            Expanded(
              child: Text(
                text,
                style: textTheme.bodyLarge?.copyWith(
                  color: context.colors.textSecondary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Join extends ConsumerStatefulWidget {
  const _Join({required this.state});

  final PairingJoin state;

  @override
  ConsumerState<_Join> createState() => _JoinState();
}

class _JoinState extends ConsumerState<_Join> {
  final _text = TextEditingController();

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text;
    if (text != null && mounted) _text.text = text;
  }

  @override
  Widget build(BuildContext context) {
    final controller = ref.read(pairingProvider.notifier);
    final busy = widget.state.busy;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: IconButton(
            tooltip: 'Back',
            onPressed: busy ? null : controller.back,
            icon: const Icon(Icons.arrow_back),
          ),
        ),
        const SizedBox(height: Spacing.sm),
        const _Lead(
          title: 'Join your person.',
          message: 'Paste the invite message they sent you.',
        ),
        const SizedBox(height: Spacing.xl),
        TextField(
          controller: _text,
          enabled: !busy,
          minLines: 3,
          maxLines: 6,
          autocorrect: false,
          enableSuggestions: false,
          decoration: InputDecoration(
            labelText: 'Invite message',
            alignLabelWithHint: true,
            suffixIcon: IconButton(
              tooltip: 'Paste',
              onPressed: busy ? null : _paste,
              icon: const Icon(Icons.content_paste),
            ),
          ),
        ),
        _Failure(widget.state.failure),
        const SizedBox(height: Spacing.xl),
        _WideButton(
          label: 'Join',
          busy: busy,
          onPressed: () => controller.join(_text.text),
        ),
      ],
    );
  }
}

class _InviteOut extends ConsumerWidget {
  const _InviteOut({required this.state});

  final PairingInviteOut state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(pairingProvider.notifier);
    final canShare = state.token != null;

    Future<void> share() async {
      final copied = await controller.shareInvite();
      if (copied && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Invite copied. Paste it to your person.'),
          ),
        );
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Lead(
          title: canShare ? 'Your invite is ready.' : 'Your invite is out.',
          message: canShare
              ? 'Send it to your person on WhatsApp or any app. When they '
                    'join, you’ll type the code their phone shows.'
              : 'This phone can’t show that invite again. If your person '
                    'didn’t get it, cancel it and send a new one.',
        ),
        const SizedBox(height: Spacing.xl),
        if (canShare) ...[
          _WideButton(
            label: 'Share invite',
            icon: Icons.ios_share,
            onPressed: state.busy ? null : share,
          ),
          const SizedBox(height: Spacing.xl),
        ],
        const _Waiting('Waiting for your person to join…'),
        const SizedBox(height: Spacing.sm),
        Text(
          'The invite works once and ends in 24 hours.',
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(color: context.colors.textSecondary),
        ),
        _Failure(state.failure),
        const SizedBox(height: Spacing.lg),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: TextButton(
            onPressed: state.busy ? null : controller.cancel,
            child: const Text('Cancel invite'),
          ),
        ),
      ],
    );
  }
}

class _ShowCode extends ConsumerWidget {
  const _ShowCode({required this.state});

  final PairingShowCode state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(pairingProvider.notifier);
    final code = state.code;
    final name = state.partnerName;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Lead(
          title: 'Read this code to ${name ?? 'your person'}.',
          message:
              'They’ll type it on their phone to finish pairing. Share it '
              'only with them.',
        ),
        const SizedBox(height: Spacing.xl),
        _Panel(
          child: Semantics(
            label: 'Code ${code.split('').join(' ')}',
            child: ExcludeSemantics(
              child: Text(
                '${code.substring(0, 3)} ${code.substring(3)}',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.displayMedium?.copyWith(
                  color: context.colors.accent,
                  fontWeight: FontWeights.semibold,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: Spacing.xl),
        const _Waiting('Waiting for them to confirm…'),
        _Failure(state.failure),
        const SizedBox(height: Spacing.lg),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: TextButton(
            onPressed: state.busy ? null : controller.cancel,
            child: const Text('Cancel'),
          ),
        ),
      ],
    );
  }
}

class _EnterCode extends ConsumerStatefulWidget {
  const _EnterCode({required this.state});

  final PairingEnterCode state;

  @override
  ConsumerState<_EnterCode> createState() => _EnterCodeState();
}

class _EnterCodeState extends ConsumerState<_EnterCode> {
  final _code = TextEditingController();

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = ref.read(pairingProvider.notifier);
    final state = widget.state;
    final name = state.partnerName;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Lead(
          title: name == null ? 'Someone joined your invite.' : '$name joined.',
          message:
              'Ask them for the six-digit code on their phone and type it '
              'here. Confirm only if it’s really your person.',
        ),
        const SizedBox(height: Spacing.xl),
        TextField(
          controller: _code,
          enabled: !state.busy,
          autofocus: true,
          keyboardType: TextInputType.number,
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(6),
          ],
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.headlineMedium,
          decoration: const InputDecoration(labelText: 'Six-digit code'),
          onSubmitted: controller.confirm,
        ),
        _Failure(state.failure),
        const SizedBox(height: Spacing.xl),
        _WideButton(
          label: 'Confirm',
          busy: state.busy,
          onPressed: () => controller.confirm(_code.text),
        ),
        const SizedBox(height: Spacing.sm),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: TextButton(
            onPressed: state.busy ? null : controller.reject,
            child: const Text('That’s not my person'),
          ),
        ),
      ],
    );
  }
}
