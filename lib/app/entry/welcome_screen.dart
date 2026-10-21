import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sirf_hum/design_system/design_system.dart';
import 'package:sirf_hum/security/account/email_link_sign_in.dart';
import 'package:sirf_hum/session/sign_in_controller.dart';

/// Signed out: passwordless sign-in by email link (D-138).
///
/// Signing in only names the account. A new phone is still a pending device
/// until a trusted device or the recovery key approves it, so nothing here
/// promises access to the couple's content. Builds that cannot sign in
/// (no Firebase, web for now) say so plainly instead of offering a button
/// that does nothing.
class WelcomeScreen extends ConsumerWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final canSignIn = ref.watch(authLinkDomainProvider) != null;
    final state = ref.watch(signInProvider);
    return Scaffold(
      body: AppPage(
        title: 'Sirf Hum',
        subtitle: 'A private home for the two of you.',
        children: [
          Text(
            'One place to talk, spend time together, keep your memories '
            'and plan what’s next. Just the two of you.',
            style: Theme.of(context).textTheme.bodyLarge,
          ),
          const SizedBox(height: Spacing.xxl),
          if (!canSignIn)
            const Notice(
              icon: Icons.schedule_outlined,
              message: 'Signing in opens in an upcoming version of Sirf Hum.',
            )
          else
            switch (state) {
              SignInEnterEmail(:final failure) => _EmailForm(
                key: const ValueKey('enter-email'),
                intro:
                    'Enter your email. We’ll send you a link to sign in. '
                    'No password needed.',
                actionLabel: 'Send sign-in link',
                failure: failure,
                onSubmit: ref.read(signInProvider.notifier).send,
              ),
              SignInNeedsEmail(:final failure) => _EmailForm(
                key: const ValueKey('confirm-email'),
                intro:
                    'To finish signing in, enter the email you asked '
                    'for this link with.',
                actionLabel: 'Sign in',
                failure: failure,
                onSubmit: ref.read(signInProvider.notifier).confirmEmail,
              ),
              SignInLinkSent(:final failure) => _LinkSent(failure: failure),
              SignInSending() => const _Busy(label: 'Sending your link…'),
              SignInCompleting() => const _Busy(label: 'Signing you in…'),
            },
        ],
      ),
    );
  }
}

/// Human copy for each failure; never the address or the link.
String failureMessage(EmailLinkFailure failure) => switch (failure) {
  EmailLinkFailure.invalidEmail => 'That doesn’t look like an email address.',
  EmailLinkFailure.invalidLink =>
    'That link can’t be used. It may have been used already. Ask for a '
        'new one.',
  EmailLinkFailure.expiredLink => 'That link has expired. Ask for a new one.',
  EmailLinkFailure.emailMismatch =>
    'That link was sent to a different email. Enter the one you used.',
  EmailLinkFailure.tooManyRequests =>
    'Too many tries for now. Wait a few minutes, then try again.',
  EmailLinkFailure.network =>
    'You seem to be offline. Connect, then try again.',
  EmailLinkFailure.unavailable =>
    'Sign-in isn’t available right now. Try again in a little while.',
};

class _EmailForm extends StatefulWidget {
  const _EmailForm({
    required this.intro,
    required this.actionLabel,
    required this.failure,
    required this.onSubmit,
    super.key,
  });

  final String intro;
  final String actionLabel;
  final EmailLinkFailure? failure;
  final Future<void> Function(String email) onSubmit;

  @override
  State<_EmailForm> createState() => _EmailFormState();
}

class _EmailFormState extends State<_EmailForm> {
  final _email = TextEditingController();

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  void _submit() => widget.onSubmit(_email.text);

  @override
  Widget build(BuildContext context) {
    final failure = widget.failure;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(widget.intro, style: Theme.of(context).textTheme.bodyLarge),
        const SizedBox(height: Spacing.lg),
        TextField(
          controller: _email,
          keyboardType: TextInputType.emailAddress,
          autofillHints: const [AutofillHints.email],
          autocorrect: false,
          enableSuggestions: false,
          textInputAction: TextInputAction.send,
          onSubmitted: (_) => _submit(),
          decoration: InputDecoration(
            labelText: 'Email',
            errorText: failure == null ? null : failureMessage(failure),
          ),
        ),
        const SizedBox(height: Spacing.lg),
        FilledButton(onPressed: _submit, child: Text(widget.actionLabel)),
      ],
    );
  }
}

class _LinkSent extends ConsumerStatefulWidget {
  const _LinkSent({required this.failure});

  final EmailLinkFailure? failure;

  @override
  ConsumerState<_LinkSent> createState() => _LinkSentState();
}

class _LinkSentState extends ConsumerState<_LinkSent> {
  final _link = TextEditingController();

  @override
  void dispose() {
    _link.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = ref.read(signInProvider.notifier);
    final failure = widget.failure;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Notice(
          icon: Icons.mark_email_read_outlined,
          message:
              'Check your email and open the link on this phone. It works '
              'once and expires soon.',
        ),
        const SizedBox(height: Spacing.lg),
        Text(
          'If the link opens in your browser instead, copy it and paste it '
          'here.',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: Spacing.sm),
        TextField(
          controller: _link,
          keyboardType: TextInputType.url,
          autocorrect: false,
          enableSuggestions: false,
          textInputAction: TextInputAction.go,
          onSubmitted: controller.receiveLink,
          decoration: InputDecoration(
            labelText: 'Sign-in link',
            errorText: failure == null ? null : failureMessage(failure),
          ),
        ),
        const SizedBox(height: Spacing.lg),
        Wrap(
          spacing: Spacing.sm,
          runSpacing: Spacing.sm,
          children: [
            FilledButton(
              onPressed: () => controller.receiveLink(_link.text),
              child: const Text('Sign in with link'),
            ),
            TextButton(
              onPressed: controller.restart,
              child: const Text('Use a different email'),
            ),
          ],
        ),
      ],
    );
  }
}

class _Busy extends StatelessWidget {
  const _Busy({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      liveRegion: true,
      label: label,
      child: Row(
        children: [
          const SizedBox.square(
            dimension: IconSizes.sm,
            child: CircularProgressIndicator(strokeWidth: Spacing.xxs),
          ),
          const SizedBox(width: Spacing.md),
          ExcludeSemantics(child: Text(label)),
        ],
      ),
    );
  }
}
