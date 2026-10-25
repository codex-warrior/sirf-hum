import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sirf_hum/core/logging/app_logger.dart';
import 'package:sirf_hum/core/logging/log_value.dart';
import 'package:sirf_hum/session/phone_setup.dart';
import 'package:sirf_hum/session/session_controller.dart';
import 'package:sirf_hum/session/session_state.dart';
import 'package:sirf_hum_crypto/sirf_hum_crypto.dart';

/// Makes the [PhoneSetup] for the signed-in account. `null` — web, tests,
/// builds without Firebase — means there is nothing to set up here.
final phoneSetupFactoryProvider =
    Provider<PhoneSetup Function(AccountId account)?>((ref) => null);

/// What the "Set up this phone" page shows.
final class PhoneSetupView {
  const PhoneSetupView({this.step, this.busy = false, this.failure});

  /// Null while the first check runs (or where nothing can be set up).
  final PhoneSetupStep? step;

  /// An action is running: buttons wait.
  final bool busy;

  /// The last action's failure, shown once beside what is still possible.
  final PhoneSetupFailure? failure;
}

final phoneSetupProvider =
    NotifierProvider.autoDispose<PhoneSetupController, PhoneSetupView>(
      PhoneSetupController.new,
    );

/// The single producer of [PhoneSetupView] (D-159). It exists only while
/// the page is open; leaving it closes this phone's keys. When the phone is
/// set up, the keys are closed first and the private services reopen.
class PhoneSetupController extends Notifier<PhoneSetupView> {
  PhoneSetup? _setup;
  int _generation = 0;

  @override
  PhoneSetupView build() {
    final generation = ++_generation;
    ref.onDispose(_release);
    final paired = ref.watch(sessionProvider.select((s) => s is SessionPaired));
    final factory = ref.watch(phoneSetupFactoryProvider);
    if (!paired || !ref.watch(privateContentAvailableProvider)) {
      return const PhoneSetupView(failure: PhoneSetupFailure.needsPhone);
    }
    if (factory == null) {
      return const PhoneSetupView(failure: PhoneSetupFailure.unavailable);
    }
    unawaited(Future<void>.microtask(() => _start(factory, generation)));
    return const PhoneSetupView(busy: true);
  }

  Future<void> retry() => _run((s) => s.check());

  Future<void> useRecoveryKey(String key) => _run((s) => s.useRecoveryKey(key));

  Future<void> requestReset() => _run((s) => s.requestReset());

  Future<void> finishReset() => _run((s) => s.finishReset());

  Future<void> _start(
    PhoneSetup Function(AccountId account) factory,
    int generation,
  ) async {
    final account = await ref.read(accountSessionProvider).accountChanges.first;
    if (!_current(generation) || account == null) return;
    _setup = factory(account);
    await _run((s) => s.check());
  }

  Future<void> _run(
    Future<PhoneSetupStep> Function(PhoneSetup s) action,
  ) async {
    final setup = _setup;
    final generation = _generation;
    if (setup == null || state.busy && state.step != null) return;
    state = PhoneSetupView(step: state.step, busy: true);
    try {
      final step = await action(setup);
      if (!_current(generation)) return;
      // Close this copy of the keys: the private services open them again
      // when this page closes (openPhoneSetup).
      if (step is PhoneSetupDone) _release();
      state = PhoneSetupView(step: step);
      _log(step.runtimeType.toString());
    } on PhoneSetupException catch (e) {
      if (!_current(generation)) return;
      state = PhoneSetupView(step: state.step, failure: e.failure);
      _log('failed_${e.failure.name}');
    } on Object catch (e, stackTrace) {
      if (!_current(generation)) return;
      AppLogger.warning('phone_setup_failed', error: e, stackTrace: stackTrace);
      state = PhoneSetupView(
        step: state.step,
        failure: PhoneSetupFailure.unexpected,
      );
    }
  }

  bool _current(int generation) => ref.mounted && generation == _generation;

  void _release() {
    _setup?.close();
    _setup = null;
  }

  static void _log(String outcome) => AppLogger.info(
    'phone_setup_state_changed',
    fields: {'state': SafeLogString(outcome)},
  );
}
