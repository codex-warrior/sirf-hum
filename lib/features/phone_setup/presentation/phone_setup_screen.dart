import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sirf_hum/design_system/design_system.dart';
import 'package:sirf_hum/features/phone_setup/application/phone_setup_controller.dart';
import 'package:sirf_hum/session/phone_setup.dart';
import 'package:sirf_hum/session/private_services.dart';
import 'package:sirf_hum/session/session_controller.dart';

/// Opens "Set up this phone" as a pushed page. When it closes, the private
/// services open again (outside any build): if the phone is set up they
/// open, otherwise they say so again.
Future<void> openPhoneSetup(BuildContext context) async {
  final container = ProviderScope.containerOf(context);
  await Navigator.of(
    context,
  ).push(MaterialPageRoute<void>(builder: (_) => const PhoneSetupScreen()));
  // The page underneath resumes its paused providers while the next frame
  // builds; changing them before that frame ends is a build-time change.
  await WidgetsBinding.instance.endOfFrame;
  container.invalidate(privateServicesProvider);
}

/// Sets this phone up again after Sirf Hum was reinstalled or its data was
/// cleared (D-159): with the backup key, or by starting fresh after a short,
/// public wait. Says plainly what each path means; nothing here trusts the
/// phone by itself — the server decides every step.
class PhoneSetupScreen extends ConsumerWidget {
  const PhoneSetupScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final view = ref.watch(phoneSetupProvider);
    final controller = ref.read(phoneSetupProvider.notifier);
    final partner =
        ref.watch(pairedCoupleProvider)?.names.partner ?? 'your person';
    final failure = view.failure;
    return Scaffold(
      appBar: AppBar(),
      body: AppPage(
        title: 'Set up this phone',
        subtitle:
            'Sirf Hum was reinstalled here, so this phone has new keys. Your '
            'account is fine.',
        children: [
          if (failure != null) ...[
            Semantics(
              liveRegion: true,
              child: Notice(
                icon: Icons.error_outline,
                message: _failureText(failure),
              ),
            ),
            const SizedBox(height: Spacing.xl),
          ],
          switch (view.step) {
            null when failure == null || view.busy => const _Checking(),
            null => ErrorState(
              title: 'We couldn’t check this phone.',
              message: 'Check your connection, then try again.',
              action: StateAction(
                label: 'Try again',
                onPressed: controller.retry,
              ),
            ),
            // Keyed: a failure notice appearing above must not reset what
            // was typed into the backup-key field.
            PhoneSetupNeedsApproval() => _Choices(
              key: const ValueKey('choices'),
              busy: view.busy,
              partner: partner,
              onKey: controller.useRecoveryKey,
              onReset: () => _confirmReset(context, controller, partner),
            ),
            PhoneSetupResetPending(:final effectiveAt) => _Waiting(
              effectiveAt: effectiveAt,
              busy: view.busy,
              onCheck: controller.retry,
            ),
            PhoneSetupResetReady() => _Ready(
              busy: view.busy,
              onFinish: controller.finishReset,
            ),
            PhoneSetupDone(:final newIdentity) => _Done(
              partner: partner,
              newIdentity: newIdentity,
            ),
          },
        ],
      ),
    );
  }

  static String _failureText(PhoneSetupFailure failure) => switch (failure) {
    PhoneSetupFailure.unavailable =>
      'We couldn’t reach Sirf Hum. Check your connection and try again.',
    PhoneSetupFailure.wrongKey =>
      'That backup key didn’t work. Check it and try again.',
    PhoneSetupFailure.noBackupKey =>
      'This account doesn’t have a backup key yet. Start fresh instead.',
    PhoneSetupFailure.tooManyResets =>
      'You’ve started fresh a few times recently. Try again later.',
    PhoneSetupFailure.needsPhone => 'Set up Sirf Hum in the app on your phone.',
    PhoneSetupFailure.unexpected =>
      'Something didn’t look right. Nothing changed. Try again.',
  };

  Future<void> _confirmReset(
    BuildContext context,
    PhoneSetupController controller,
    String partner,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Start fresh on this phone?'),
        content: Text(
          'This phone becomes your Sirf Hum again. Memories and plans that '
          'were only on the old install don’t come back here, and $partner '
          'sees that your security code changed. If another phone of yours '
          'still works, it can stop this.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Not now'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Start fresh'),
          ),
        ],
      ),
    );
    if (confirmed ?? false) await controller.requestReset();
  }
}

class _Checking extends StatelessWidget {
  const _Checking();

  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Checking this phone',
    child: const LinearProgressIndicator(),
  );
}

/// The two ways back: the backup key (instant) or starting fresh.
class _Choices extends StatefulWidget {
  const _Choices({
    required this.busy,
    super.key,
    required this.partner,
    required this.onKey,
    required this.onReset,
  });

  final bool busy;
  final String partner;
  final Future<void> Function(String key) onKey;
  final VoidCallback onReset;

  @override
  State<_Choices> createState() => _ChoicesState();
}

class _ChoicesState extends State<_Choices> {
  final _key = TextEditingController();

  @override
  void initState() {
    super.initState();
    _key.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _key.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final secondary = textTheme.bodyMedium?.copyWith(
      color: context.colors.textSecondary,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Have your backup key?', style: textTheme.titleMedium),
        const SizedBox(height: Spacing.xs),
        Text(
          'Enter it to make this phone yours again right away.',
          style: secondary,
        ),
        const SizedBox(height: Spacing.md),
        TextField(
          controller: _key,
          enabled: !widget.busy,
          autocorrect: false,
          enableSuggestions: false,
          keyboardType: TextInputType.visiblePassword,
          decoration: const InputDecoration(labelText: 'Backup key'),
        ),
        const SizedBox(height: Spacing.md),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: OutlinedButton(
            onPressed: widget.busy || _key.text.trim().isEmpty
                ? null
                : () => widget.onKey(_key.text),
            child: const Text('Use backup key'),
          ),
        ),
        const SizedBox(height: Spacing.xxl),
        const Divider(height: 1),
        const SizedBox(height: Spacing.xxl),
        Text('No backup key?', style: textTheme.titleMedium),
        const SizedBox(height: Spacing.xs),
        Text(
          'Start fresh. This phone becomes your Sirf Hum again, and '
          '${widget.partner} sees that your security code changed.',
          style: secondary,
        ),
        const SizedBox(height: Spacing.lg),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: FilledButton(
            onPressed: widget.busy ? null : widget.onReset,
            child: const Text('Start fresh'),
          ),
        ),
        if (widget.busy) ...[
          const SizedBox(height: Spacing.xl),
          const LinearProgressIndicator(),
        ],
      ],
    );
  }
}

/// The public wait (D-082). Re-checks by itself every minute.
class _Waiting extends StatefulWidget {
  const _Waiting({
    required this.effectiveAt,
    required this.busy,
    required this.onCheck,
  });

  final DateTime effectiveAt;
  final bool busy;
  final Future<void> Function() onCheck;

  @override
  State<_Waiting> createState() => _WaitingState();
}

class _WaitingState extends State<_Waiting> {
  late final Timer _tick;

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(minutes: 1), (_) {
      if (!widget.busy) widget.onCheck();
    });
  }

  @override
  void dispose() {
    _tick.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final at = widget.effectiveAt.toLocal();
    final localizations = MaterialLocalizations.of(context);
    final time = localizations.formatTimeOfDay(TimeOfDay.fromDateTime(at));
    final now = DateTime.now();
    final sameDay =
        at.year == now.year && at.month == now.month && at.day == now.day;
    final when = sameDay
        ? time
        : '${localizations.formatMediumDate(at)}, $time';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Almost there.', style: textTheme.titleLarge),
        const SizedBox(height: Spacing.sm),
        Text(
          'You can finish setting up after $when. This short wait keeps '
          'anyone else from taking over your account. You can close the app; '
          'come back here then.',
          style: textTheme.bodyLarge?.copyWith(
            color: context.colors.textSecondary,
          ),
        ),
        const SizedBox(height: Spacing.xl),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: OutlinedButton(
            onPressed: widget.busy ? null : widget.onCheck,
            child: const Text('Check again'),
          ),
        ),
      ],
    );
  }
}

class _Ready extends StatelessWidget {
  const _Ready({required this.busy, required this.onFinish});

  final bool busy;
  final Future<void> Function() onFinish;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Ready when you are.', style: textTheme.titleLarge),
        const SizedBox(height: Spacing.sm),
        Text(
          'The wait is over. Finish, and this phone is your Sirf Hum again.',
          style: textTheme.bodyLarge?.copyWith(
            color: context.colors.textSecondary,
          ),
        ),
        const SizedBox(height: Spacing.xl),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: FilledButton(
            onPressed: busy ? null : onFinish,
            child: const Text('Finish setting up'),
          ),
        ),
        if (busy) ...[
          const SizedBox(height: Spacing.xl),
          const LinearProgressIndicator(),
        ],
      ],
    );
  }
}

class _Done extends StatelessWidget {
  const _Done({required this.partner, required this.newIdentity});

  final String partner;
  final bool newIdentity;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('This phone is set up.', style: textTheme.titleLarge),
        const SizedBox(height: Spacing.sm),
        Text(
          newIdentity
              ? '$partner will see that your security code changed. New '
                    'memories and plans are shared again as soon as their '
                    'phone opens Sirf Hum.'
              : 'Everything you share from now on reaches $partner as before.',
          style: textTheme.bodyLarge?.copyWith(
            color: context.colors.textSecondary,
          ),
        ),
        const SizedBox(height: Spacing.xl),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: FilledButton(
            onPressed: () => Navigator.of(context).maybePop(),
            child: const Text('Done'),
          ),
        ),
      ],
    );
  }
}
