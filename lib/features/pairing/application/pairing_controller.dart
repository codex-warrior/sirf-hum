import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sirf_hum/core/logging/app_logger.dart';
import 'package:sirf_hum/core/logging/log_value.dart';
import 'package:sirf_hum/features/pairing/application/invite_message.dart';
import 'package:sirf_hum/features/pairing/application/pairing_device.dart';
import 'package:sirf_hum/features/pairing/domain/pairing_view_state.dart';
import 'package:sirf_hum/platform/text_share.dart';
import 'package:sirf_hum/security/couple/pairing.dart';
import 'package:sirf_hum/session/session_controller.dart';
import 'package:sirf_hum/session/session_state.dart';

/// Overridden in `main.dart` for a configured phone build; `null` elsewhere
/// (web, no Firebase), which the screen reports instead of pairing.
final pairingDeviceSetupProvider = Provider<PairingDeviceSetup?>((ref) => null);

/// The system share sheet; `null` falls back to copying the invitation.
final textShareProvider = Provider<TextShare?>((ref) => null);

/// How often an open pairing asks the server whether the other person
/// acted. Short: both people are usually looking at their phones.
final pairingPollIntervalProvider = Provider<Duration>(
  (ref) => const Duration(seconds: 4),
);

final pairingProvider = NotifierProvider<PairingController, PairingViewState>(
  PairingController.new,
);

/// The single producer of [PairingViewState].
///
/// - Runs only while the session is signed in without a couple; any session
///   change rebuilds it from nothing and releases this phone's keys.
///   Answers for an earlier build are dropped (generation).
/// - Every step is signed by this phone's device key through
///   [PairingSession]; the server decides each one. The couple exists only
///   when the server says so: the session is then refreshed, never set here.
/// - The invitation token is shared, never logged.
class PairingController extends Notifier<PairingViewState> {
  int _generation = 0;
  PairingSession? _session;
  Timer? _poll;

  /// The token of the invitation this phone created, while it is open.
  String? _token;

  @override
  PairingViewState build() {
    final generation = ++_generation;
    ref.onDispose(_release);
    // Release this phone's keys the moment the couple exists, not when this
    // provider next rebuilds: the private services open the same identity
    // next, and two open cores must never share one sealed state.
    ref.listen(sessionProvider.select((s) => s is SessionPaired), (_, paired) {
      if (paired) _release();
    });
    final active = ref.watch(
      sessionProvider.select(
        (s) => s is SessionNotPaired || s is SessionPairing,
      ),
    );
    if (!active) return const PairingSettingUp();
    if (!ref.watch(privateContentAvailableProvider)) {
      return const PairingDeviceUnavailable(PairingDeviceProblem.needsPhone);
    }
    unawaited(Future<void>.microtask(() => _setUp(generation)));
    return const PairingSettingUp();
  }

  /// After a failure to set up: start again from nothing.
  void retry() => ref.invalidateSelf();

  Future<void> invite() async {
    final session = _session;
    final current = state;
    if (session == null || current is! PairingChoose || current.busy) return;
    final generation = _generation;
    state = const PairingChoose(busy: true);
    try {
      final invitation = await session.createInvitation();
      if (!_current(generation)) return;
      _token = invitation.token;
      state = PairingInviteOut(
        pairingId: invitation.pairingId,
        expiresAt: invitation.expiresAt,
        token: invitation.token,
      );
      _startPolling(generation);
    } on PairingException catch (e) {
      if (!_current(generation)) return;
      if (e.failure == PairingFailure.pairingInProgress) {
        await _sync(generation);
      } else {
        state = PairingChoose(failure: e.failure);
      }
    }
  }

  /// Opens the share sheet with the invitation, or copies it when there is
  /// none. Returns whether it was copied (so the screen can say so).
  Future<bool> shareInvite() async {
    final token = _token;
    if (token == null) return false;
    final message = inviteMessage(token);
    final share = ref.read(textShareProvider);
    if (share != null) {
      try {
        await share.share(message);
        return false;
      } on PlatformException catch (e) {
        AppLogger.warning('pairing_share_failed', error: e);
      }
    }
    await Clipboard.setData(ClipboardData(text: message));
    return true;
  }

  void startJoin() {
    if (state is PairingChoose) state = const PairingJoin();
  }

  void back() {
    if (state case PairingJoin(busy: false)) state = const PairingChoose();
  }

  /// Uses the invitation in [pasted] (the whole message or just the code).
  Future<void> join(String pasted) async {
    final session = _session;
    final current = state;
    if (session == null || current is! PairingJoin || current.busy) return;
    final token = inviteTokenIn(pasted);
    if (token == null) {
      state = const PairingJoin(failure: PairingFailure.invitationInvalid);
      return;
    }
    final generation = _generation;
    state = const PairingJoin(busy: true);
    try {
      final accepted = await session.acceptInvitation(token);
      if (!_current(generation)) return;
      state = PairingShowCode(
        pairingId: accepted.pairingId,
        code: accepted.code,
        partnerName: accepted.partnerDisplayName,
      );
      _startPolling(generation);
    } on PairingException catch (e) {
      if (_current(generation)) state = PairingJoin(failure: e.failure);
    }
  }

  /// The inviter confirms with the code the other phone shows (D-131).
  Future<void> confirm(String code) async {
    final session = _session;
    final current = state;
    if (session == null || current is! PairingEnterCode || current.busy) {
      return;
    }
    final generation = _generation;
    state = PairingEnterCode(
      pairingId: current.pairingId,
      partnerName: current.partnerName,
      busy: true,
    );
    try {
      await session.confirm(current.pairingId, code.trim());
      if (!_current(generation)) return;
      _stopPolling();
      await ref.read(sessionProvider.notifier).refresh();
    } on PairingException catch (e) {
      if (!_current(generation)) return;
      if (e.failure == PairingFailure.confirmationCodeInvalid ||
          e.failure == PairingFailure.invalidRequest ||
          e.failure == PairingFailure.unavailable) {
        state = PairingEnterCode(
          pairingId: current.pairingId,
          partnerName: current.partnerName,
          failure: e.failure,
        );
      } else {
        _token = null;
        state = PairingChoose(failure: e.failure);
      }
    }
  }

  /// The inviter refuses the account that accepted.
  Future<void> reject() => _end((s, id) => s.reject(id));

  /// Either person withdraws the open pairing.
  Future<void> cancel() => _end((s, id) => s.cancel(id));

  Future<void> _end(
    Future<void> Function(PairingSession session, String pairingId) step,
  ) async {
    final session = _session;
    final pairingId = switch (state) {
      PairingInviteOut(:final pairingId, busy: false) => pairingId,
      PairingShowCode(:final pairingId, busy: false) => pairingId,
      PairingEnterCode(:final pairingId, busy: false) => pairingId,
      _ => null,
    };
    if (session == null || pairingId == null) return;
    final generation = _generation;
    final before = state;
    state = _busy(before);
    _stopPolling();
    try {
      await step(session, pairingId);
      if (!_current(generation)) return;
      _token = null;
      state = const PairingChoose();
      unawaited(ref.read(sessionProvider.notifier).refresh());
    } on PairingException catch (e) {
      if (!_current(generation)) return;
      // Whatever happened, the server's view decides what is shown next.
      AppLogger.info(
        'pairing_end_failed',
        fields: {'outcome': SafeLogString(e.failure.name)},
      );
      await _sync(generation);
    }
  }

  Future<void> _setUp(int generation) async {
    final account = ref.read(sessionProvider.notifier).account;
    final setup = ref.read(pairingDeviceSetupProvider);
    if (account == null || setup == null) {
      if (_current(generation)) {
        state = PairingDeviceUnavailable(
          setup == null
              ? PairingDeviceProblem.needsPhone
              : PairingDeviceProblem.failed,
        );
      }
      return;
    }
    try {
      final result = await setup.setUp(account);
      if (!_current(generation)) {
        if (result is DeviceSetupReady) result.session.close();
        return;
      }
      switch (result) {
        case DeviceSetupReady(:final session):
          _session = session;
          await _sync(generation, first: true);
        case DeviceSetupAwaitingApproval(:final code):
          state = PairingDeviceWaiting(code: code);
        case DeviceSetupUnavailable(:final problem):
          state = PairingDeviceUnavailable(switch (problem) {
            DeviceSetupProblem.needsPhone => PairingDeviceProblem.needsPhone,
            DeviceSetupProblem.removed => PairingDeviceProblem.removed,
            DeviceSetupProblem.unreadable => PairingDeviceProblem.unreadable,
          });
      }
    } on Exception catch (e) {
      AppLogger.warning('pairing_setup_failed', error: e);
      if (_current(generation)) {
        state = const PairingDeviceUnavailable(PairingDeviceProblem.failed);
      }
    }
  }

  /// Shows what the server says about this account's pairing.
  Future<void> _sync(int generation, {bool first = false}) async {
    final session = _session;
    if (session == null) return;
    final PairingState server;
    try {
      server = await session.state();
    } on PairingException catch (e) {
      if (first && _current(generation)) {
        AppLogger.info(
          'pairing_state_failed',
          fields: {'outcome': SafeLogString(e.failure.name)},
        );
        state = const PairingDeviceUnavailable(PairingDeviceProblem.failed);
      }
      return; // A failed poll keeps what is on screen.
    }
    if (!_current(generation)) return;
    switch (server) {
      case PairingNone():
        _stopPolling();
        _token = null;
        if (state is! PairingChoose && state is! PairingJoin) {
          state = const PairingChoose();
        }
      case PairingInvited(:final pairingId, :final expiresAt):
        if (state case PairingInviteOut(busy: true)) return;
        state = PairingInviteOut(
          pairingId: pairingId,
          expiresAt: expiresAt,
          token: _token,
        );
        _startPolling(generation);
      case PairingAwaitingConfirmation(
        isInviter: true,
        :final pairingId,
        :final partnerDisplayName,
      ):
        _stopPolling();
        if (state is PairingEnterCode) return; // Keep what is being typed.
        state = PairingEnterCode(
          pairingId: pairingId,
          partnerName: partnerDisplayName,
        );
        unawaited(ref.read(sessionProvider.notifier).refresh());
      case PairingAwaitingConfirmation(
        :final pairingId,
        :final code?,
        :final partnerDisplayName,
      ):
        if (state case PairingShowCode(busy: true)) return;
        state = PairingShowCode(
          pairingId: pairingId,
          code: code,
          partnerName: partnerDisplayName,
        );
        _startPolling(generation);
      case PairingAwaitingConfirmation():
        // An invitee view without its code is malformed (parse refuses it).
        return;
      case PairingPaired():
        _stopPolling();
        await ref.read(sessionProvider.notifier).refresh();
    }
  }

  void _startPolling(int generation) {
    if (_poll != null) return;
    _poll = Timer.periodic(ref.read(pairingPollIntervalProvider), (_) {
      if (_current(generation)) unawaited(_sync(generation));
    });
  }

  void _stopPolling() {
    _poll?.cancel();
    _poll = null;
  }

  bool _current(int generation) => ref.mounted && generation == _generation;

  static PairingViewState _busy(PairingViewState s) => switch (s) {
    PairingInviteOut() => PairingInviteOut(
      pairingId: s.pairingId,
      expiresAt: s.expiresAt,
      token: s.token,
      busy: true,
    ),
    PairingShowCode() => PairingShowCode(
      pairingId: s.pairingId,
      code: s.code,
      partnerName: s.partnerName,
      busy: true,
    ),
    PairingEnterCode() => PairingEnterCode(
      pairingId: s.pairingId,
      partnerName: s.partnerName,
      busy: true,
    ),
    _ => s,
  };

  void _release() {
    _stopPolling();
    _session?.close();
    _session = null;
    _token = null;
  }
}
