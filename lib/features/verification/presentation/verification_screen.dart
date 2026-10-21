import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sirf_hum/design_system/design_system.dart';
import 'package:sirf_hum/features/verification/application/verification_controller.dart';
import 'package:sirf_hum/features/verification/domain/verification_state.dart';
import 'package:sirf_hum/security/verification/partner_verification.dart';
import 'package:sirf_hum/session/session_controller.dart';

/// Verify your partner (D-128): compare a safety number side by side, or
/// scan each other's code. A pushed page, never a URL. The page says
/// plainly whether this phone has verified them; nothing on it is decided
/// by the server.
class VerificationScreen extends ConsumerWidget {
  const VerificationScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final partner =
        ref.watch(pairedCoupleProvider)?.names.partner ?? 'your partner';
    final state = ref.watch(partnerVerificationProvider);
    final controller = ref.read(partnerVerificationProvider.notifier);
    return Scaffold(
      appBar: AppBar(title: Text('Verify $partner')),
      body: AppPage(
        children: [
          switch (state) {
            VerificationUnavailable(:final reason) => _Unavailable(reason),
            VerificationLoading() => const Skeleton(
              label: 'Loading your safety number',
              child: Column(
                children: [
                  SkeletonBlock(height: Spacing.xl, widthFactor: 0.4),
                  SizedBox(height: Spacing.lg),
                  SkeletonBlock(height: Spacing.xxxl * 2),
                  SizedBox(height: Spacing.lg),
                  SkeletonBlock(height: Spacing.xxxl * 4, widthFactor: 0.6),
                ],
              ),
            ),
            VerificationFailed(:final reason) => ErrorState(
              title: "This can't be checked right now",
              message: switch (reason) {
                VerificationFailedReason.thisPhone =>
                  "This phone isn't trusted on your account yet.",
                VerificationFailedReason.partner =>
                  "$partner's phone isn't set up yet. Try again once it is.",
                VerificationFailedReason.staleServer =>
                  'Sirf Hum got an older answer than this phone has already '
                      "seen, so it won't use it. Try again later.",
                VerificationFailedReason.unknown =>
                  'Check your connection and try again.',
              },
              action: StateAction(
                label: 'Try again',
                onPressed: controller.retry,
              ),
            ),
            VerificationReady() => _Ready(
              state: state,
              partner: partner,
              controller: controller,
              canScan: ref.watch(qrCodeScannerProvider) != null,
            ),
          },
        ],
      ),
    );
  }
}

class _Unavailable extends StatelessWidget {
  const _Unavailable(this.reason);

  final VerificationUnavailableReason reason;

  @override
  Widget build(BuildContext context) => EmptyState(
    icon: Icons.shield_outlined,
    title: switch (reason) {
      VerificationUnavailableReason.needsPhone => 'Verify on your phone',
      VerificationUnavailableReason.notPaired => 'Pair first',
      VerificationUnavailableReason.notYetAvailable =>
        'Verification is on its way',
    },
    message: switch (reason) {
      VerificationUnavailableReason.needsPhone =>
        "Your keys live on your phone, so that's where you compare them.",
      VerificationUnavailableReason.notPaired =>
        "Once you're paired, you can check it's really them.",
      VerificationUnavailableReason.notYetAvailable =>
        'It opens here once your phones are set up for each other.',
    },
  );
}

class _Ready extends StatelessWidget {
  const _Ready({
    required this.state,
    required this.partner,
    required this.controller,
    required this.canScan,
  });

  final VerificationReady state;
  final String partner;
  final PartnerVerificationController controller;
  final bool canScan;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final colors = context.colors;
    final verified = state.verified;
    final notice = _noticeText(state, partner);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(
          liveRegion: true,
          child: Row(
            children: [
              Icon(
                verified ? Icons.verified_user : Icons.shield_outlined,
                color: verified ? colors.success : colors.textSecondary,
              ),
              const SizedBox(width: Spacing.sm),
              Text(
                verified ? 'Verified' : 'Not verified',
                style: textTheme.titleLarge,
              ),
            ],
          ),
        ),
        const SizedBox(height: Spacing.md),
        Text(switch (state.status) {
          VerificationStatus.verified =>
            'You compared this number with $partner. Phones they add '
                'later are approved by a phone you verified, so they stay '
                "verified. If $partner's number ever changes, this page "
                'will say Not verified again.',
          VerificationStatus.notVerified =>
            "Compare this number with the one on $partner's phone — side "
                'by side, or on a call you started. If every digit matches, '
                "you know this phone is talking to $partner's phones and "
                'nobody in between.',
          VerificationStatus.changed =>
            "Something about $partner's identity doesn't match what you "
                "verified. Don't share anything private until you compare "
                'again.',
        }, style: textTheme.bodyLarge?.copyWith(color: colors.textSecondary)),
        if (!verified && state.partnerResetCount > 0) ...[
          const SizedBox(height: Spacing.md),
          Notice(
            icon: Icons.restart_alt,
            message:
                '$partner set Sirf Hum up again, so their number changed. '
                'Compare it again.',
          ),
        ],
        const SizedBox(height: Spacing.xl),
        _Number(groups: state.groups),
        const SizedBox(height: Spacing.xl),
        Center(
          child: ScannableCode(
            text: state.qrText,
            semanticLabel: 'Your safety number as a code $partner can scan',
          ),
        ),
        if (notice != null) ...[
          const SizedBox(height: Spacing.lg),
          Semantics(
            liveRegion: true,
            child: Notice(icon: notice.$1, message: notice.$2),
          ),
        ],
        if (!verified) ...[
          const SizedBox(height: Spacing.xl),
          FilledButton(
            onPressed: state.busy ? null : () => _confirm(context),
            child: const Text('The numbers match'),
          ),
          if (canScan) ...[
            const SizedBox(height: Spacing.sm),
            OutlinedButton.icon(
              onPressed: state.busy ? null : () => _scan(context),
              icon: const Icon(Icons.qr_code_scanner),
              label: Text("Scan $partner's code"),
            ),
          ],
          const SizedBox(height: Spacing.sm),
          TextButton(
            onPressed: state.busy ? null : controller.reportMismatch,
            child: const Text("They don't match"),
          ),
        ],
      ],
    );
  }

  Future<void> _confirm(BuildContext context) async {
    final sure = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Do all 60 digits match?'),
        content: Text(
          'Only confirm if every group matches what $partner sees on their '
          'own phone, right now.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Go back'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('They match'),
          ),
        ],
      ),
    );
    if (sure ?? false) await controller.confirmCompared();
  }

  Future<void> _scan(BuildContext context) async {
    final scanner = ProviderScope.containerOf(
      context,
    ).read(qrCodeScannerProvider);
    final text = await scanner?.scan(context);
    if (text != null) await controller.confirmScanned(text);
  }

  static (IconData, String)? _noticeText(VerificationReady s, String partner) =>
      switch (s.notice) {
        null => null,
        VerificationNotice.verified => (
          Icons.check_circle_outline,
          '$partner is verified on this phone.',
        ),
        VerificationNotice.scanMismatch => (
          Icons.error_outline,
          "That code isn't your safety number with $partner. Nothing was "
              'trusted. Make sure you scanned their phone, here, now.',
        ),
        VerificationNotice.reportedMismatch => (
          Icons.error_outline,
          "Nothing was trusted. Don't share anything private on Sirf Hum "
              'until the numbers match — someone may be between you.',
        ),
        VerificationNotice.changedWhileShown => (
          Icons.info_outline,
          'The number changed while you were looking at it. Compare the new '
              'one.',
        ),
        VerificationNotice.revoked => (
          Icons.block,
          'This identity was removed and can never be verified again.',
        ),
      };
}

/// The 60 digits as 12 groups, three rows of four, in tabular figures so
/// both phones line up digit for digit. Read aloud group by group.
class _Number extends StatelessWidget {
  const _Number({required this.groups});

  final List<String> groups;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.titleMedium?.copyWith(
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    return Semantics(
      label: 'Safety number: ${groups.join(', ')}',
      child: ExcludeSemantics(
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(Spacing.lg),
          decoration: BoxDecoration(
            color: context.colors.surfaceMuted,
            borderRadius: BorderRadius.circular(Radii.md),
          ),
          child: Column(
            children: [
              for (var row = 0; row < 3; row++)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: Spacing.xs),
                  // Equal columns that scale down rather than overflow, at
                  // any width or text size: the groups must line up.
                  child: Row(
                    children: [
                      for (var i = row * 4; i < row * 4 + 4; i++)
                        Expanded(
                          child: Center(
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text(groups[i], style: style),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
