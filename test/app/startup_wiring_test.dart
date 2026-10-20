import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sirf_hum/features/together/application/together_controller.dart';
import 'package:sirf_hum/infrastructure/firebase/firebase_bootstrap.dart';
import 'package:sirf_hum/main.dart';
import 'package:sirf_hum/security/account/account_session.dart';
import 'package:sirf_hum/session/session_controller.dart';
import 'package:sirf_hum/session/session_state.dart';

/// The start-up wiring in `main.dart` (D-110): a Firebase start failure,
/// including the start-up timeout, must never look like "signed out" or
/// "signed in", and must not wire any backend.
void main() {
  Future<SessionState> sessionFor(FirebaseStatus status) async {
    final container = ProviderContainer(
      overrides: sessionPortOverrides(status),
    );
    addTearDown(container.dispose);
    container.listen(sessionProvider, (_, _) {});
    for (var i = 0; i < 10; i++) {
      await Future<void>.delayed(Duration.zero);
    }
    expect(
      container.read(pairingBackendProvider),
      isNull,
      reason: 'no backend is wired unless Firebase is ready',
    );
    return container.read(sessionProvider);
  }

  test(
    'Firebase failed (or timed out): start failed, never signed out',
    () async {
      expect(
        sessionPortOverrides(FirebaseStatus.failed),
        hasLength(1),
        reason: 'only the account session is replaced',
      );
      expect(
        await sessionFor(FirebaseStatus.failed),
        isA<SessionUnavailable>().having(
          (s) => s.problem,
          'problem',
          SessionProblem.startFailed,
        ),
      );
    },
  );

  test('not configured: signed out (development/CI build)', () async {
    expect(sessionPortOverrides(FirebaseStatus.notConfigured), isEmpty);
    expect(
      await sessionFor(FirebaseStatus.notConfigured),
      isA<SessionSignedOut>(),
    );
  });

  test('production wires no Together backend (D-112)', () {
    for (final status in [
      FirebaseStatus.notConfigured,
      FirebaseStatus.failed,
    ]) {
      final container = ProviderContainer(
        overrides: sessionPortOverrides(status),
      );
      addTearDown(container.dispose);
      expect(container.read(togetherBackendProvider), isNull);
    }
    // The ready branch builds Firebase objects, so it is checked by source:
    // it must not mention Together at all.
    expect(
      File('lib/main.dart').readAsStringSync(),
      isNot(contains('together')),
    );
  });

  test('the unavailable session never emits an account', () async {
    await expectLater(
      const UnavailableAccountSession().accountChanges,
      emitsError(isA<AccountSessionUnavailable>()),
    );
  });
}
