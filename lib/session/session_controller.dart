import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sirf_hum/core/logging/app_logger.dart';
import 'package:sirf_hum/core/logging/log_value.dart';
import 'package:sirf_hum/security/account/account_session.dart';
import 'package:sirf_hum/security/couple/couple_profiles.dart';
import 'package:sirf_hum/security/couple/pairing.dart';
import 'package:sirf_hum/session/session_state.dart';
import 'package:sirf_hum/session/sign_in_controller.dart';
import 'package:sirf_hum_crypto/sirf_hum_crypto.dart';

/// Ports, overridden in `main.dart` with the Firebase implementations. The
/// defaults are those of a build without Firebase: signed out, no backend.
final accountSessionProvider = Provider<AccountSession>(
  (ref) => const SignedOutAccountSession(),
);

/// The pairing callables, read-only here (`getPairingState`). `null` when
/// there is no backend, which is reported as unreachable, never as unpaired.
final pairingBackendProvider = Provider<PairingBackend?>((ref) => null);

final coupleProfilesProvider = Provider<CoupleProfiles>(
  (ref) => const NoCoupleProfiles(),
);

/// Whether this platform may hold private (E2EE) content. Web never does
/// (WEB-SECURITY Option C, D-046); this mirrors
/// `LocalDeviceIdentityService`, which refuses web the same way.
final privateContentAvailableProvider = Provider<bool>((ref) => !kIsWeb);

final sessionProvider = NotifierProvider<SessionController, SessionState>(
  SessionController.new,
);

/// The paired couple, or null in any other state.
final pairedCoupleProvider = Provider<SessionPaired?>((ref) {
  final session = ref.watch(sessionProvider);
  return session is SessionPaired ? session : null;
});

/// The single source of [SessionState] (D-106).
///
/// - The account comes from [AccountSession] (restored session first).
/// - The couple comes only from the server (`getPairingState`). Nothing the
///   client holds — cached flags, route, deep link — can make it "paired".
/// - Answers for an account that is no longer current are dropped, so a
///   sign-out or account switch never shows the previous account's couple.
/// - A failed *refresh* keeps the state already on screen (UX-PRINCIPLES:
///   content already shown stays visible); only a first answer can fail into
///   [SessionUnavailable].
/// - Nothing is persisted locally.
class SessionController extends Notifier<SessionState> {
  AccountId? _account;
  int _generation = 0;

  /// The signed-in account, for features that open its device identity
  /// (pairing). Null while signed out or unknown.
  AccountId? get account => _account;

  @override
  SessionState build() {
    final subscription = ref
        .watch(accountSessionProvider)
        .accountChanges
        .listen(
          _onAccount,
          onError: (Object error) {
            AppLogger.warning('session_auth_error', error: error);
            _account = null;
            _generation++;
            state = const SessionUnavailable(SessionProblem.startFailed);
          },
        );
    ref.onDispose(subscription.cancel);
    return const SessionStarting();
  }

  /// Asks the server again (retry, app resumed, "check again").
  Future<void> refresh() async {
    final account = _account;
    if (account == null) return;
    final generation = ++_generation;
    if (state is SessionUnavailable) state = const SessionStarting();
    await _resolve(account, generation);
  }

  /// Saves the name the signed-in person chose (their own profile only)
  /// and re-reads the couple, so both names show at once. The account never
  /// leaves this controller. Throws [CoupleProfileException].
  Future<void> setYourName(String name) async {
    final account = _account;
    if (account == null || state is! SessionPaired) {
      throw const CoupleProfileException(CoupleProfileFailure.unavailable);
    }
    await ref.read(coupleProfilesProvider).setYourName(account, name);
    await refresh();
  }

  /// Ends the account session, then forgets the Google account choice so
  /// the next "Continue with Google" asks again (D-150). Device keys and
  /// trust are untouched: signing out is not revocation.
  Future<void> signOut() async {
    await ref.read(accountSessionProvider).signOut();
    await ref.read(googleSignInProvider)?.forget();
  }

  void _onAccount(AccountId? account) {
    if (account != null && account == _account && state is! SessionSignedOut) {
      return; // Token refreshes re-emit the same account.
    }
    _account = account;
    final generation = ++_generation;
    if (account == null) {
      state = const SessionSignedOut();
      return;
    }
    state = const SessionStarting();
    unawaited(_resolve(account, generation));
  }

  Future<void> _resolve(AccountId account, int generation) async {
    final canPairHere = ref.read(privateContentAvailableProvider);
    SessionState next;
    try {
      final backend = ref.read(pairingBackendProvider);
      if (backend == null) {
        throw const PairingException(PairingFailure.unavailable);
      }
      next = switch (await backend.state()) {
        PairingNone() => SessionNotPaired(canPairHere: canPairHere),
        PairingInvited() => SessionPairing(
          stage: PairingStage.invitationSent,
          canPairHere: canPairHere,
        ),
        PairingAwaitingConfirmation(isInviter: true) => SessionPairing(
          stage: PairingStage.partnerAccepted,
          canPairHere: canPairHere,
        ),
        PairingAwaitingConfirmation() => SessionPairing(
          stage: PairingStage.waitingForPartner,
          canPairHere: canPairHere,
        ),
        PairingPaired() => SessionPaired(
          names: await ref.read(coupleProfilesProvider).names(account),
        ),
      };
    } on PairingException catch (e) {
      next = SessionUnavailable(
        e.failure == PairingFailure.unauthenticated
            ? SessionProblem.signInAgain
            : SessionProblem.unreachable,
      );
    } on Exception catch (e) {
      AppLogger.warning('session_resolve_error', error: e);
      next = const SessionUnavailable(SessionProblem.unreachable);
    }

    if (!ref.mounted || generation != _generation) return;
    final current = state;
    final keepShown =
        next is SessionUnavailable &&
        next.problem == SessionProblem.unreachable &&
        current is! SessionStarting &&
        current is! SessionUnavailable;
    _log(next, kept: keepShown);
    if (!keepShown) state = next;
  }

  // The state's kind only: never names, IDs or stages that reveal more.
  static void _log(SessionState next, {required bool kept}) => AppLogger.info(
    'session_resolved',
    fields: {
      'state': SafeLogString(switch (next) {
        SessionStarting() => 'starting',
        SessionSignedOut() => 'signed_out',
        SessionNotPaired() => 'not_paired',
        SessionPairing() => 'pairing',
        SessionPaired() => 'paired',
        SessionUnavailable(:final problem) => 'unavailable_${problem.name}',
      }),
      'kept_previous': kept,
    },
  );
}
