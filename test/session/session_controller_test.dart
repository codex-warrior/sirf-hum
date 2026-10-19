import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sirf_hum/core/logging/app_logger.dart';
import 'package:sirf_hum/security/account/account_session.dart';
import 'package:sirf_hum/security/couple/couple_profiles.dart';
import 'package:sirf_hum/security/couple/pairing.dart';
import 'package:sirf_hum/session/session_controller.dart';
import 'package:sirf_hum/session/session_state.dart';
import 'package:sirf_hum_crypto/sirf_hum_crypto.dart';

import '../support/session_fakes.dart';

class _RecordingSink implements LogSink {
  final records = <LogRecord>[];

  @override
  void write(LogRecord record) => records.add(record);
}

void main() {
  late _RecordingSink sink;

  setUp(() {
    sink = _RecordingSink();
    AppLogger.configure(sinks: [sink], minimumLevel: LogLevel.debug);
  });
  tearDown(() => AppLogger.configure(sinks: const [DeveloperLogSink()]));

  ProviderContainer container({
    required FakeAccountSession session,
    PairingBackend? backend,
    CoupleProfiles? profiles,
    bool privateContent = true,
    bool noBackend = false,
  }) {
    final c = ProviderContainer(
      overrides: sessionOverrides(
        session: session,
        backend: noBackend
            ? null
            : backend ?? FakePairingBackend.returning(paired),
        profiles: profiles,
        privateContent: privateContent,
      ),
    );
    addTearDown(c.dispose);
    // Keep the controller alive for the whole test.
    c.listen(sessionProvider, (_, _) {});
    return c;
  }

  Future<SessionState> settle(ProviderContainer c) async {
    for (var i = 0; i < 10; i++) {
      await Future<void>.delayed(Duration.zero);
    }
    return c.read(sessionProvider);
  }

  group('auth state', () {
    test('starts in SessionStarting before anything is known', () {
      final c = container(session: FakeAccountSession(alice));
      expect(c.read(sessionProvider), isA<SessionStarting>());
    });

    test('signed out when there is no account', () async {
      final backend = FakePairingBackend.returning(paired);
      final c = container(session: FakeAccountSession(), backend: backend);
      expect(await settle(c), isA<SessionSignedOut>());
      expect(backend.stateCalls, 0, reason: 'no server call while signed out');
    });

    test('a restored session is resolved with the server', () async {
      final backend = FakePairingBackend.returning(const PairingNone());
      final c = container(session: FakeAccountSession(alice), backend: backend);
      expect(await settle(c), isA<SessionNotPaired>());
      expect(backend.stateCalls, 1);
    });

    test(
      'signing in later moves from signed out to the server state',
      () async {
        final session = FakeAccountSession();
        final c = container(session: session);
        expect(await settle(c), isA<SessionSignedOut>());
        session.emit(alice);
        expect(await settle(c), isA<SessionPaired>());
      },
    );

    test(
      'a token refresh re-emitting the same account does not re-query',
      () async {
        final session = FakeAccountSession(alice);
        final backend = FakePairingBackend.returning(paired);
        final c = container(session: session, backend: backend);
        await settle(c);
        session.emit(alice);
        await settle(c);
        expect(backend.stateCalls, 1);
      },
    );

    test('signing out drops the couple immediately', () async {
      final session = FakeAccountSession(alice);
      final c = container(session: session);
      expect(await settle(c), isA<SessionPaired>());
      await c.read(sessionProvider.notifier).signOut();
      expect(await settle(c), isA<SessionSignedOut>());
      expect(c.read(pairedCoupleProvider), isNull);
      expect(session.signOuts, 1);
    });

    test('an auth failure is unavailable, never signed out or in', () async {
      final c = ProviderContainer(
        overrides: sessionOverrides(session: _ErrorSession()),
      );
      addTearDown(c.dispose);
      c.listen(sessionProvider, (_, _) {});
      expect(
        await settle(c),
        isA<SessionUnavailable>().having(
          (s) => s.problem,
          'problem',
          SessionProblem.startFailed,
        ),
      );
    });
  });

  group('couple state comes only from the server', () {
    final cases = <String, (PairingState, Matcher)>{
      'none → not paired': (const PairingNone(), isA<SessionNotPaired>()),
      'invited → invitation sent': (
        invited,
        isA<SessionPairing>().having(
          (s) => s.stage,
          'stage',
          PairingStage.invitationSent,
        ),
      ),
      'claimed, inviter → partner accepted': (
        awaiting(isInviter: true),
        isA<SessionPairing>().having(
          (s) => s.stage,
          'stage',
          PairingStage.partnerAccepted,
        ),
      ),
      'claimed, invitee → waiting for partner': (
        awaiting(isInviter: false),
        isA<SessionPairing>().having(
          (s) => s.stage,
          'stage',
          PairingStage.waitingForPartner,
        ),
      ),
      'paired → paired': (paired, isA<SessionPaired>()),
      'paired without couple ID (pre-Prompt 12) → paired': (
        const PairingPaired(coupleId: null, conversationId: null),
        isA<SessionPaired>(),
      ),
    };
    cases.forEach((name, testCase) {
      test(name, () async {
        final c = container(
          session: FakeAccountSession(alice),
          backend: FakePairingBackend.returning(testCase.$1),
        );
        expect(await settle(c), testCase.$2);
      });
    });

    test('paired carries the couple names, read for this account', () async {
      final profiles = FakeCoupleProfiles(names);
      final c = container(
        session: FakeAccountSession(alice),
        profiles: profiles,
      );
      final state = await settle(c);
      expect(state, isA<SessionPaired>());
      expect((state as SessionPaired).names, names);
      expect(profiles.requested, [alice]);
    });

    test('names are not read unless paired', () async {
      final profiles = FakeCoupleProfiles(names);
      final c = container(
        session: FakeAccountSession(alice),
        backend: FakePairingBackend.returning(const PairingNone()),
        profiles: profiles,
      );
      await settle(c);
      expect(profiles.requested, isEmpty);
    });

    test('web cannot pair here (no device key), mobile can', () async {
      for (final privateContent in [true, false]) {
        final c = container(
          session: FakeAccountSession(alice),
          backend: FakePairingBackend.returning(const PairingNone()),
          privateContent: privateContent,
        );
        final state = await settle(c) as SessionNotPaired;
        expect(state.canPairHere, privateContent);
      }
    });

    test('no backend is unavailable, never "not paired"', () async {
      final c = container(session: FakeAccountSession(alice), noBackend: true);
      expect(
        await settle(c),
        isA<SessionUnavailable>().having(
          (s) => s.problem,
          'problem',
          SessionProblem.unreachable,
        ),
      );
    });

    test('a rejected sign-in asks to sign in again', () async {
      final c = container(
        session: FakeAccountSession(alice),
        backend: FakePairingBackend.failing(PairingFailure.unauthenticated),
      );
      expect(
        await settle(c),
        isA<SessionUnavailable>().having(
          (s) => s.problem,
          'problem',
          SessionProblem.signInAgain,
        ),
      );
    });

    test('a malformed server answer is unavailable, not a state', () async {
      final c = container(
        session: FakeAccountSession(alice),
        backend: FakePairingBackend(
          () async => PairingState.parse({'state': 'paired', 'coupleId': 'x'}),
        ),
      );
      expect(await settle(c), isA<SessionUnavailable>());
    });

    test('an unknown server state is unavailable, not paired', () async {
      final c = container(
        session: FakeAccountSession(alice),
        backend: FakePairingBackend(
          () async => PairingState.parse({'state': 'couple_admin'}),
        ),
      );
      expect(await settle(c), isA<SessionUnavailable>());
    });
  });

  group('refresh and recovery', () {
    test('retry after a failure reaches the server state', () async {
      var fail = true;
      final backend = FakePairingBackend(
        () async => fail
            ? throw const PairingException(PairingFailure.unavailable)
            : paired,
      );
      final c = container(session: FakeAccountSession(alice), backend: backend);
      expect(await settle(c), isA<SessionUnavailable>());

      fail = false;
      final retry = c.read(sessionProvider.notifier).refresh();
      expect(c.read(sessionProvider), isA<SessionStarting>());
      await retry;
      expect(c.read(sessionProvider), isA<SessionPaired>());
    });

    test('a failed refresh keeps what is already shown', () async {
      var fail = false;
      final backend = FakePairingBackend(
        () async => fail
            ? throw const PairingException(PairingFailure.unavailable)
            : paired,
      );
      final c = container(session: FakeAccountSession(alice), backend: backend);
      expect(await settle(c), isA<SessionPaired>());

      fail = true;
      await c.read(sessionProvider.notifier).refresh();
      expect(c.read(sessionProvider), isA<SessionPaired>());
    });

    test(
      'a refresh that finds the sign-in rejected leaves the couple',
      () async {
        var reject = false;
        final backend = FakePairingBackend(
          () async => reject
              ? throw const PairingException(PairingFailure.unauthenticated)
              : paired,
        );
        final c = container(
          session: FakeAccountSession(alice),
          backend: backend,
        );
        expect(await settle(c), isA<SessionPaired>());

        reject = true;
        await c.read(sessionProvider.notifier).refresh();
        expect(c.read(sessionProvider), isA<SessionUnavailable>());
        expect(c.read(pairedCoupleProvider), isNull);
      },
    );

    test('a refresh sees a couple formed since the last answer', () async {
      PairingState answer = invited;
      final c = container(
        session: FakeAccountSession(alice),
        backend: FakePairingBackend(() async => answer),
      );
      expect(await settle(c), isA<SessionPairing>());
      answer = paired;
      await c.read(sessionProvider.notifier).refresh();
      expect(c.read(sessionProvider), isA<SessionPaired>());
    });

    test('an answer for a previous account is never applied', () async {
      final pendingForAlice = Completer<PairingState>();
      final bob = AccountId('uidBob');
      final session = FakeAccountSession(alice);
      var calls = 0;
      final backend = FakePairingBackend(() {
        calls++;
        return calls == 1
            ? pendingForAlice.future
            : Future.value(const PairingNone());
      });
      final c = container(session: session, backend: backend);
      await settle(c);

      session.emit(bob);
      expect(await settle(c), isA<SessionNotPaired>());
      pendingForAlice.complete(paired); // Alice's late answer
      expect(await settle(c), isA<SessionNotPaired>());
    });

    test('a refresh in flight across an account switch is dropped', () async {
      final bob = AccountId('uidBob');
      final session = FakeAccountSession(alice);
      Completer<PairingState>? pendingRefresh;
      final backend = FakePairingBackend(() async {
        // Alice's first answer: not paired. Her refresh: held open, then a
        // couple. Bob: not paired.
        if (pendingRefresh case final p?) return p.future;
        return const PairingNone();
      });
      final c = container(session: session, backend: backend);
      expect(await settle(c), isA<SessionNotPaired>());

      pendingRefresh = Completer<PairingState>();
      final refresh = c.read(sessionProvider.notifier).refresh();
      final aliceRefresh = pendingRefresh;
      pendingRefresh = null;

      session.emit(bob);
      expect(await settle(c), isA<SessionNotPaired>());
      aliceRefresh.complete(paired); // Alice's late answer
      await refresh;
      expect(await settle(c), isA<SessionNotPaired>());
      expect(c.read(pairedCoupleProvider), isNull);
    });

    test('signing out while an answer is in flight stays signed out', () async {
      final pending = Completer<PairingState>();
      final session = FakeAccountSession(alice);
      final c = container(
        session: session,
        backend: FakePairingBackend(() => pending.future),
      );
      await settle(c);
      session.emit(null);
      pending.complete(paired);
      expect(await settle(c), isA<SessionSignedOut>());
    });
  });

  test('logs carry the state kind only: no IDs, codes or names', () async {
    for (final answer in [paired, invited, awaiting(isInviter: true)]) {
      final c = container(
        session: FakeAccountSession(alice),
        backend: FakePairingBackend.returning(answer),
        profiles: FakeCoupleProfiles(names),
      );
      await settle(c);
    }
    final logged = sink.records
        .map((r) => '${r.event} ${r.fields} ${r.errorType}')
        .join('\n');
    expect(logged, contains('session_resolved'));
    for (final secret in [...secretValues, 'Asha', 'Ravi']) {
      expect(logged, isNot(contains(secret)));
    }
  });
}

class _ErrorSession extends FakeAccountSession {
  @override
  Stream<AccountId?> get accountChanges =>
      const UnavailableAccountSession().accountChanges;
}
