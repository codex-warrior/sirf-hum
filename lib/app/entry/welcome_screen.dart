import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sirf_hum/design_system/design_system.dart';
import 'package:sirf_hum/security/account/email_link_sign_in.dart';
import 'package:sirf_hum/security/account/google_account_sign_in.dart';
import 'package:sirf_hum/session/sign_in_controller.dart';

/// Signed out: "Continue with Google" first, "Continue with Email" (a
/// passwordless link, D-138) as the fallback (D-150). There is no sign-up
/// versus sign-in choice; the provider decides whether the account is new.
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
    final controller = ref.read(signInProvider.notifier);
    return Scaffold(
      body: switch (state) {
        _ when !canSignIn => const _ChooseMethod(signInAvailable: false),
        SignInChooseMethod(:final failure) => _ChooseMethod(failure: failure),
        SignInWithGoogle() => const _ChooseMethod(googleBusy: true),
        SignInEnterEmail(:final failure) => _EmailPage(
          child: _EmailForm(
            key: const ValueKey('enter-email'),
            intro: 'We’ll email you a link to continue. No password needed.',
            actionLabel: 'Send link',
            failure: failure,
            onSubmit: controller.send,
          ),
        ),
        SignInNeedsEmail(:final failure) => _EmailPage(
          child: _EmailForm(
            key: const ValueKey('confirm-email'),
            intro: 'To finish, enter the email you asked for this link with.',
            actionLabel: 'Continue',
            failure: failure,
            onSubmit: controller.confirmEmail,
          ),
        ),
        SignInLinkSent(:final failure) => _EmailPage(
          child: _LinkSent(failure: failure),
        ),
        SignInSending() => const _EmailPage(
          child: _Busy(label: 'Sending your link…'),
        ),
        SignInCompleting() => const _EmailPage(
          child: _Busy(label: 'Signing you in…'),
        ),
      },
    );
  }
}

/// Human copy for each email-link failure; never the address or the link.
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

/// Human copy for each Google failure; never the account. Cancelling is
/// not a failure and has no message.
String googleFailureMessage(GoogleAccountFailure failure) => switch (failure) {
  GoogleAccountFailure.cancelled => '',
  GoogleAccountFailure.emailLinkAccount =>
    'This email already signs in with an email link. Continue with Email '
        'to sign in.',
  GoogleAccountFailure.unverifiedEmail =>
    'Google couldn’t confirm this email address. Continue with Email '
        'instead.',
  GoogleAccountFailure.accountDisabled =>
    'This account can’t sign in right now.',
  GoogleAccountFailure.tooManyRequests =>
    'Too many tries for now. Wait a few minutes, then try again.',
  GoogleAccountFailure.network =>
    'You seem to be offline. Connect, then try again.',
  GoogleAccountFailure.unavailable =>
    'Google sign-in isn’t available right now. Try again, or continue '
        'with Email.',
};

/// The first screen: the name, one line, and two ways in. Brand on top,
/// actions at thumb height; scrolls rather than clips at large text sizes.
class _ChooseMethod extends ConsumerWidget {
  const _ChooseMethod({
    this.failure,
    this.googleBusy = false,
    this.signInAvailable = true,
  });

  final GoogleAccountFailure? failure;
  final bool googleBusy;
  final bool signInAvailable;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final textTheme = Theme.of(context).textTheme;
    final colors = context.colors;
    final hasGoogle = ref.watch(googleSignInProvider) != null;
    final controller = ref.read(signInProvider.notifier);
    final failure = this.failure;
    final gutter = WindowSize.of(context) == WindowSize.compact
        ? Spacing.pageGutterCompact
        : Spacing.pageGutterWide;

    final email = hasGoogle
        ? OutlinedButton.icon(
            onPressed: googleBusy ? null : controller.continueWithEmail,
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(TouchTargets.comfortable),
              textStyle: TypeScale.bodyStrong,
            ),
            icon: const Icon(Icons.mail_outline),
            label: const Text('Continue with Email'),
          )
        : FilledButton.icon(
            onPressed: controller.continueWithEmail,
            icon: const Icon(Icons.mail_outline),
            label: const Text('Continue with Email'),
          );

    return SafeArea(
      child: LayoutBuilder(
        builder: (context, box) => SingleChildScrollView(
          // One centred column, at most the form width.
          padding: EdgeInsets.symmetric(
            horizontal: math.max(
              gutter,
              (box.maxWidth - WindowSize.maxFormWidth) / 2,
            ),
            vertical: Spacing.xl,
          ),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minHeight: math.max(0, box.maxHeight - Spacing.xl * 2),
            ),
            child: IntrinsicHeight(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Spacer(flex: 2),
                  Semantics(
                    header: true,
                    child: Text(
                      'Sirf Hum',
                      textAlign: TextAlign.center,
                      style: textTheme.displaySmall,
                    ),
                  ),
                  const SizedBox(height: Spacing.sm),
                  Text(
                    'Your private space for two.',
                    textAlign: TextAlign.center,
                    style: textTheme.bodyLarge?.copyWith(
                      color: colors.textSecondary,
                    ),
                  ),
                  const Spacer(flex: 3),
                  const SizedBox(height: Spacing.xxxl),
                  if (!signInAvailable)
                    const Notice(
                      icon: Icons.schedule_outlined,
                      message:
                          'Signing in opens in an upcoming version of '
                          'Sirf Hum.',
                    )
                  else ...[
                    if (hasGoogle) ...[
                      _GoogleButton(
                        busy: googleBusy,
                        onPressed: controller.continueWithGoogle,
                      ),
                      if (failure != null &&
                          failure != GoogleAccountFailure.cancelled) ...[
                        const SizedBox(height: Spacing.sm),
                        Semantics(
                          liveRegion: true,
                          child: Text(
                            googleFailureMessage(failure),
                            textAlign: TextAlign.center,
                            style: textTheme.bodyMedium?.copyWith(
                              color: colors.danger,
                            ),
                          ),
                        ),
                      ],
                      const _Or(),
                    ],
                    email,
                    const SizedBox(height: Spacing.xl),
                    Text(
                      'By continuing, you agree to our Terms and '
                      'Privacy Policy.',
                      textAlign: TextAlign.center,
                      style: textTheme.bodySmall?.copyWith(
                        color: colors.textSecondary,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _GoogleButton extends StatelessWidget {
  const _GoogleButton({required this.busy, required this.onPressed});

  final bool busy;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Semantics(
      liveRegion: busy,
      child: FilledButton(
        onPressed: busy ? null : onPressed,
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(TouchTargets.comfortable),
          disabledBackgroundColor: colors.accent,
          disabledForegroundColor: colors.onAccent,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (busy)
              SizedBox.square(
                dimension: IconSizes.sm,
                child: CircularProgressIndicator(
                  strokeWidth: Spacing.xxs,
                  color: colors.onAccent,
                ),
              )
            else
              const GoogleMark(),
            const SizedBox(width: Spacing.md),
            Flexible(
              child: Text(busy ? 'Signing you in…' : 'Continue with Google'),
            ),
          ],
        ),
      ),
    );
  }
}

class _Or extends StatelessWidget {
  const _Or();

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: Spacing.lg),
    child: Row(
      children: [
        const Expanded(child: Divider()),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: Spacing.md),
          child: Text(
            'or',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: context.colors.textSecondary,
            ),
          ),
        ),
        const Expanded(child: Divider()),
      ],
    ),
  );
}

/// The email steps: a back arrow to the choice of method, then the step.
class _EmailPage extends ConsumerWidget {
  const _EmailPage({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(signInProvider);
    final busy = state is SignInSending || state is SignInCompleting;
    return AppPage(
      header: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: IconButton(
              tooltip: 'Back',
              onPressed: busy ? null : ref.read(signInProvider.notifier).back,
              icon: const BackButtonIcon(),
            ),
          ),
          const SizedBox(height: Spacing.sm),
          Semantics(
            header: true,
            child: Text(
              'Continue with Email',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
          ),
        ],
      ),
      children: [
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: WindowSize.maxFormWidth),
          child: child,
        ),
      ],
    );
  }
}

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
          autofocus: true,
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
          'If the link opens in your browser instead, go back to the email, '
          'press and hold the link, copy it, and paste it here.',
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
