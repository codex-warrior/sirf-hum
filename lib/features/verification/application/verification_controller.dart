import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sirf_hum/core/logging/app_logger.dart';
import 'package:sirf_hum/core/logging/log_value.dart';
import 'package:sirf_hum/features/verification/domain/verification_state.dart';
import 'package:sirf_hum/security/verification/partner_verification.dart';
import 'package:sirf_hum/security/verification/safety_number.dart';
import 'package:sirf_hum/session/private_services.dart';
import 'package:sirf_hum/session/session_controller.dart';
import 'package:sirf_hum/session/session_state.dart';

/// The verification port for the signed-in account's couple (D-128): a
/// `PartnerVerificationService` over this account's core and the server's
/// device registry, from this phone's private services. `null` while they
/// open, when they failed, or where nothing private is wired.
final partnerVerificationBackendProvider =
    Provider<PartnerVerificationBackend?>(
      (ref) => ref.watch(currentPrivateServicesProvider)?.verification,
    );

/// Reads one QR code with the camera and returns its text, or null when
/// the person backs out. `null` provider: no camera here (web, tests).
abstract interface class QrCodeScanner {
  Future<String?> scan(BuildContext context);
}

final qrCodeScannerProvider = Provider<QrCodeScanner?>((ref) => null);

final partnerVerificationProvider =
    NotifierProvider<PartnerVerificationController, VerificationViewState>(
      PartnerVerificationController.new,
    );

/// The single producer of [VerificationViewState] (D-128).
///
/// - Runs only for a paired session, on a platform that may hold private
///   keys, with a backend. Any session change (sign-out, another account)
///   rebuilds it from nothing; answers for an earlier session are dropped
///   (generation), so a late "verified" can never land on another account.
/// - Trust changes only through [confirmCompared] and [confirmScanned];
///   [reportMismatch] trusts nothing.
class PartnerVerificationController extends Notifier<VerificationViewState> {
  int _generation = 0;
  PartnerVerification? _shown;

  @override
  VerificationViewState build() {
    final generation = ++_generation;
    _shown = null;
    final paired = ref.watch(sessionProvider.select((s) => s is SessionPaired));
    if (!paired) {
      return const VerificationUnavailable(
        VerificationUnavailableReason.notPaired,
      );
    }
    if (!ref.watch(privateContentAvailableProvider)) {
      return const VerificationUnavailable(
        VerificationUnavailableReason.needsPhone,
      );
    }
    final backend = ref.watch(partnerVerificationBackendProvider);
    if (backend == null) {
      return switch (ref.watch(privateServicesStatusProvider)) {
        PrivateServicesStatus.starting => const VerificationLoading(),
        PrivateServicesStatus.needsSetup => const VerificationUnavailable(
          VerificationUnavailableReason.needsSetup,
        ),
        PrivateServicesStatus.failed => const VerificationFailed(
          VerificationFailedReason.unknown,
        ),
        _ => const VerificationUnavailable(
          VerificationUnavailableReason.notYetAvailable,
        ),
      };
    }
    unawaited(Future<void>.microtask(() => _load(backend, generation)));
    return const VerificationLoading();
  }

  void retry() {
    if (state is! VerificationFailed) return;
    ref.read(partnerVerificationBackendProvider) == null
        ? retryPrivateServices(ref)
        : ref.invalidateSelf();
  }

  /// The person compared the number with their partner and says it matches.
  Future<void> confirmCompared() =>
      _confirm((backend, shown) => backend.confirmCompared(shown));

  /// The person scanned their partner's code; [text] is what it contained.
  Future<void> confirmScanned(String text) => _confirm(
    (backend, shown) => backend.confirmScanned(
      shown,
      SafetyNumber.payloadFromQrText(text) ?? Uint8List(0),
    ),
  );

  /// The numbers do not match. Nothing is trusted; the page says why.
  void reportMismatch() {
    final s = state;
    if (s is VerificationReady) {
      state = _ready(_shown!, VerificationNotice.reportedMismatch);
      _log('mismatch_reported');
    }
  }

  Future<void> _load(PartnerVerificationBackend backend, int generation) async {
    try {
      final shown = await backend.load();
      if (!_current(generation)) return;
      _shown = shown;
      state = _ready(shown, null);
      _log(shown.status.name);
    } on VerificationException catch (e) {
      if (!_current(generation)) return;
      state = VerificationFailed(_failedReason(e.failure));
      _log('failed_${e.failure.name}');
    } on Object catch (e, stackTrace) {
      if (!_current(generation)) return;
      state = const VerificationFailed(VerificationFailedReason.unknown);
      AppLogger.warning(
        'partner_verification_failed',
        error: e,
        stackTrace: stackTrace,
      );
    }
  }

  Future<void> _confirm(
    Future<PartnerVerification> Function(
      PartnerVerificationBackend backend,
      PartnerVerification shown,
    )
    action,
  ) async {
    final backend = ref.read(partnerVerificationBackendProvider);
    final shown = _shown;
    final s = state;
    if (backend == null || shown == null || s is! VerificationReady || s.busy) {
      return;
    }
    final generation = _generation;
    state = _ready(shown, null, busy: true);
    try {
      final after = await action(backend, shown);
      if (!_current(generation)) return;
      _shown = after;
      state = _ready(
        after,
        after.status == VerificationStatus.verified
            ? VerificationNotice.verified
            : null,
      );
      _log('confirmed_${after.status.name}');
    } on VerificationException catch (e) {
      if (!_current(generation)) return;
      switch (e.failure) {
        case VerificationFailure.mismatch:
          state = _ready(shown, VerificationNotice.scanMismatch);
        case VerificationFailure.revoked:
          state = _ready(shown, VerificationNotice.revoked);
        case VerificationFailure.changedWhileShown:
          // Show the new number; the old one is never trusted.
          state = _ready(shown, VerificationNotice.changedWhileShown);
          unawaited(_load(backend, generation));
        default:
          state = VerificationFailed(_failedReason(e.failure));
      }
      _log('confirm_${e.failure.name}');
    } on Object catch (e, stackTrace) {
      if (!_current(generation)) return;
      state = const VerificationFailed(VerificationFailedReason.unknown);
      AppLogger.warning(
        'partner_verification_failed',
        error: e,
        stackTrace: stackTrace,
      );
    }
  }

  bool _current(int generation) => generation == _generation;

  static VerificationReady _ready(
    PartnerVerification v,
    VerificationNotice? notice, {
    bool busy = false,
  }) => VerificationReady(
    status: v.status,
    groups: v.number.groups,
    qrText: v.number.qrText,
    partnerResetCount: v.partnerResetCount,
    partnerDeviceCount: v.partnerDeviceCount,
    notice: notice,
    busy: busy,
  );

  static VerificationFailedReason _failedReason(
    VerificationFailure f,
  ) => switch (f) {
    VerificationFailure.ownIdentityUnproven =>
      VerificationFailedReason.thisPhone,
    VerificationFailure.partnerUnavailable => VerificationFailedReason.partner,
    VerificationFailure.staleServerView => VerificationFailedReason.staleServer,
    _ => VerificationFailedReason.unknown,
  };

  static void _log(String outcome) => AppLogger.info(
    'partner_verification_state',
    fields: {'outcome': SafeLogString(outcome)},
  );
}
