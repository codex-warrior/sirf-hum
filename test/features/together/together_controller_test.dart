import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sirf_hum/core/logging/app_logger.dart';
import 'package:sirf_hum/features/together/application/together_controller.dart';
import 'package:sirf_hum/features/together/domain/together_activity.dart';
import 'package:sirf_hum/features/together/domain/together_backend.dart';
import 'package:sirf_hum/features/together/domain/together_state.dart';
import 'package:sirf_hum/security/couple/pairing.dart';
import 'package:sirf_hum_crypto/sirf_hum_crypto.dart';

import '../../support/session_fakes.dart';
import '../../support/together_fakes.dart';

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
    FakeAccountSession? session,
    PairingBackend? pairing,
    FakeTogetherBackend? together,
    bool noTogetherBackend = false,
    bool privateContent = true,
  }) {
    final c = ProviderContainer(
      overrides: sessionOverrides(
        session: session ?? FakeAccountSession(alice),
        backend: pairing ?? FakePairingBackend.returning(paired),
        profiles: FakeCoupleProfiles(names),
        privateContent: privateContent,
        extra: [
          togetherBackendProvider.overrideWithValue(
            noTogetherBackend ? null : together ?? FakeTogetherBackend(),
          ),
        ],
      ),
    );
    addTearDown(c.dispose);
    c.listen(togetherProvider, (_, _) {});
    return c;
  }

  Future<TogetherState> settle(ProviderContainer c) async {
    for (var i = 0; i < 20; i++) {
      await Future<void>.delayed(Duration.zero);
    }
    return c.read(togetherProvider);
  }

  TogetherController ctl(ProviderContainer c) =>
      c.read(togetherProvider.notifier);

  group('availability', () {
    test('not paired: unavailable, the backend is never asked', () async {
      final together = FakeTogetherBackend();
      final c = container(
        pairing: FakePairingBackend.returning(const PairingNone()),
        together: together,
      );
      expect(
        await settle(c),
        isA<TogetherUnavailable>().having(
          (s) => s.reason,
          'reason',
          TogetherUnavailableReason.notPaired,
        ),
      );
      expect(together.watches, 0);
    });

    test(
      'signed in is not paired: authentication alone opens nothing',
      () async {
        final together = FakeTogetherBackend();
        final c = container(
          pairing: FakePairingBackend.failing(PairingFailure.unavailable),
          together: together,
        );
        expect(await settle(c), isA<TogetherUnavailable>());
        expect(together.watches, 0);
      },
    );

    test('web: needs the phone, the backend is never asked', () async {
      final together = FakeTogetherBackend();
      final c = container(privateContent: false, together: together);
      expect(
        await settle(c),
        isA<TogetherUnavailable>().having(
          (s) => s.reason,
          'reason',
          TogetherUnavailableReason.needsPhone,
        ),
      );
      expect(together.watches, 0);
    });

    test('no backend (production today): not yet available', () async {
      final c = container(noTogetherBackend: true);
      expect(
        await settle(c),
        isA<TogetherUnavailable>().having(
          (s) => s.reason,
          'reason',
          TogetherUnavailableReason.notYetAvailable,
        ),
      );
    });

    test('paired with a backend: idle with presence and supported', () async {
      final c = container();
      final state = await settle(c);
      expect(state, isA<TogetherIdle>());
      state as TogetherIdle;
      expect(state.presence, PartnerPresence.online);
      expect(state.supported, {TogetherActivity.timeTogether});
    });

    test('an unsupported activity can never start', () async {
      final together = FakeTogetherBackend();
      final c = container(together: together);
      await settle(c);
      for (final activity in [
        TogetherActivity.call,
        TogetherActivity.watch,
        TogetherActivity.listen,
      ]) {
        await ctl(c).start(activity);
      }
      expect(together.starts, isEmpty);
      expect(c.read(togetherProvider), isA<TogetherIdle>());
    });
  });

  group('start → wait → together → end', () {
    test('every step is explicit', () async {
      final together = FakeTogetherBackend()..hold = Completer<void>();
      final c = container(together: together);
      await settle(c);

      final starting = ctl(c).start(TogetherActivity.timeTogether);
      expect(c.read(togetherProvider), isA<TogetherStarting>());
      together.hold!.complete();
      together.hold = null;
      await starting;
      expect(await settle(c), isA<TogetherWaiting>());

      final at = DateTime.utc(2026, 10, 20, 12);
      together.partnerJoins(at: at);
      final active = await settle(c);
      expect(active, isA<TogetherActive>());
      expect((active as TogetherActive).since, at);

      final leaving = ctl(c).leave();
      expect(c.read(togetherProvider), isA<TogetherEnding>());
      await leaving;
      final ended = await settle(c);
      expect(
        ended,
        isA<TogetherEnded>().having(
          (s) => s.reason,
          'reason',
          TogetherEndReason.left,
        ),
      );

      ctl(c).dismiss();
      expect(await settle(c), isA<TogetherIdle>());
    });

    test('cancelling while waiting returns to the choices', () async {
      final c = container();
      await settle(c);
      await ctl(c).start(TogetherActivity.timeTogether);
      await settle(c);
      await ctl(c).leave();
      expect(await settle(c), isA<TogetherIdle>());
    });

    test('the partner starts; joining makes you together', () async {
      final together = FakeTogetherBackend();
      final c = container(together: together);
      await settle(c);
      together.partnerStarts();
      expect(await settle(c), isA<TogetherInvited>());
      await ctl(c).join();
      expect(await settle(c), isA<TogetherActive>());
      expect(together.joins, 1);
    });

    test('declining an invitation returns to the choices', () async {
      final together = FakeTogetherBackend();
      final c = container(together: together);
      await settle(c);
      together.partnerStarts();
      await settle(c);
      await ctl(c).leave();
      expect(await settle(c), isA<TogetherIdle>());
    });

    test('the partner leaving ends it, and says so', () async {
      final together = FakeTogetherBackend();
      final c = container(together: together);
      await settle(c);
      await ctl(c).start(TogetherActivity.timeTogether);
      together.partnerJoins();
      await settle(c);
      together.partnerLeaves();
      expect(
        await settle(c),
        isA<TogetherEnded>().having(
          (s) => s.reason,
          'reason',
          TogetherEndReason.partnerLeft,
        ),
      );
    });

    test('nobody joining in time expires', () async {
      final together = FakeTogetherBackend();
      final c = container(together: together);
      await settle(c);
      await ctl(c).start(TogetherActivity.timeTogether);
      await settle(c);
      together.expires();
      expect(
        await settle(c),
        isA<TogetherEnded>().having(
          (s) => s.reason,
          'reason',
          TogetherEndReason.expired,
        ),
      );
    });

    test('a later event cannot resurrect an ended session', () async {
      final together = FakeTogetherBackend();
      final c = container(together: together);
      await settle(c);
      await ctl(c).start(TogetherActivity.timeTogether);
      together.partnerJoins();
      await settle(c);
      together.partnerLeaves();
      expect(await settle(c), isA<TogetherEnded>());

      // A late "active" for the session that just ended.
      together.partnerJoins();
      expect(await settle(c), isA<TogetherEnded>());
      together.partnerStarts();
      expect(await settle(c), isA<TogetherEnded>());
    });

    test('dismissing an end shows what the server says now', () async {
      final together = FakeTogetherBackend();
      final c = container(together: together);
      await settle(c);
      await ctl(c).start(TogetherActivity.timeTogether);
      together.partnerJoins();
      await settle(c);
      together.partnerLeaves();
      await settle(c);
      // Meanwhile the partner starts a new one; the end stays on screen.
      together.partnerStarts();
      await settle(c);
      ctl(c).dismiss();
      expect(await settle(c), isA<TogetherInvited>());
    });

    test(
      'a session that vanishes is ended, never still on, never idle',
      () async {
        final together = FakeTogetherBackend();
        final c = container(together: together);
        await settle(c);
        await ctl(c).start(TogetherActivity.timeTogether);
        together.partnerJoins();
        await settle(c);
        together.vanishes();
        expect(await settle(c), isA<TogetherEnded>());
      },
    );
  });

  group('failures fail closed', () {
    test('a refused start is a failure, not waiting', () async {
      final together = FakeTogetherBackend()
        ..failStart = TogetherFailure.startRefused;
      final c = container(together: together);
      await settle(c);
      await ctl(c).start(TogetherActivity.timeTogether);
      expect(
        c.read(togetherProvider),
        isA<TogetherFailed>().having(
          (s) => s.failure,
          'failure',
          TogetherFailure.startRefused,
        ),
      );
    });

    test('unreachable while together is a failure, not "not active"', () async {
      final together = FakeTogetherBackend();
      final c = container(together: together);
      await settle(c);
      await ctl(c).start(TogetherActivity.timeTogether);
      together.partnerJoins();
      await settle(c);
      together.emitError(TogetherFailure.unavailable);
      expect(
        await settle(c),
        isA<TogetherFailed>().having(
          (s) => s.failure,
          'failure',
          TogetherFailure.unavailable,
        ),
      );
    });

    test('a revoked device is never shown as together', () async {
      final together = FakeTogetherBackend()
        ..failJoin = TogetherFailure.deviceNotTrusted;
      final c = container(together: together);
      await settle(c);
      together.partnerStarts();
      await settle(c);
      await ctl(c).join();
      expect(
        await settle(c),
        isA<TogetherFailed>().having(
          (s) => s.failure,
          'failure',
          TogetherFailure.deviceNotTrusted,
        ),
      );
    });

    test('a revocation reported mid-session ends "together"', () async {
      final together = FakeTogetherBackend();
      final c = container(together: together);
      await settle(c);
      await ctl(c).start(TogetherActivity.timeTogether);
      together.partnerJoins();
      await settle(c);
      together.emitError(TogetherFailure.deviceNotTrusted);
      expect(await settle(c), isA<TogetherFailed>());
    });

    test('after a revocation, later snapshots cannot make it active', () async {
      final together = FakeTogetherBackend();
      final c = container(together: together);
      await settle(c);
      together.emitError(TogetherFailure.deviceNotTrusted);
      await settle(c);
      // A misbehaving backend keeps talking on the same stream.
      together.partnerStarts();
      await settle(c);
      together.partnerJoins();
      expect(
        await settle(c),
        isA<TogetherFailed>().having(
          (s) => s.failure,
          'failure',
          TogetherFailure.deviceNotTrusted,
        ),
      );
    });

    test('an unknown error is unexpected, never idle', () async {
      final together = FakeTogetherBackend();
      final c = container(together: together);
      await settle(c);
      together.emitError(TogetherFailure.unexpected);
      expect(await settle(c), isA<TogetherFailed>());
    });

    test('a session with an activity this client cannot run fails', () async {
      final together = FakeTogetherBackend();
      final c = container(together: together);
      await settle(c);
      together.partnerStarts(TogetherActivity.call);
      expect(
        await settle(c),
        isA<TogetherFailed>().having(
          (s) => s.failure,
          'failure',
          TogetherFailure.unexpected,
        ),
      );
    });

    test('retry starts over from the backend', () async {
      final together = FakeTogetherBackend();
      final c = container(together: together);
      await settle(c);
      together.emitError(TogetherFailure.unavailable);
      await settle(c);
      ctl(c).retry();
      expect(await settle(c), isA<TogetherIdle>());
      expect(together.watches, 2);
    });
  });

  group('account switch and sign-out', () {
    test('signing out drops the session at once', () async {
      final session = FakeAccountSession(alice);
      final together = FakeTogetherBackend();
      final c = container(session: session, together: together);
      await settle(c);
      await ctl(c).start(TogetherActivity.timeTogether);
      together.partnerJoins();
      expect(await settle(c), isA<TogetherActive>());

      session.emit(null);
      expect(await settle(c), isA<TogetherUnavailable>());
      // The old subscription is gone: the backend cannot bring it back.
      together.partnerJoins();
      expect(await settle(c), isA<TogetherUnavailable>());
    });

    test('an account switch never carries the old session over', () async {
      final session = FakeAccountSession(alice);
      final hold = Completer<PairingState>();
      var calls = 0;
      final pairing = FakePairingBackend(() {
        calls++;
        return calls == 1 ? Future.value(paired) : hold.future;
      });
      final together = FakeTogetherBackend();
      final c = container(
        session: session,
        pairing: pairing,
        together: together,
      );
      await settle(c);
      await ctl(c).start(TogetherActivity.timeTogether);
      together.partnerJoins();
      expect(await settle(c), isA<TogetherActive>());

      session.emit(AccountId('uidBob'));
      expect(await settle(c), isA<TogetherUnavailable>());
      // Bob's own server state: no session.
      together.emit(const TogetherNoSession(presence: PartnerPresence.away));
      hold.complete(paired);
      final bob = await settle(c);
      expect(bob, isA<TogetherIdle>());
      expect((bob as TogetherIdle).presence, PartnerPresence.away);
    });

    test('a start in flight across sign-out cannot resurrect it', () async {
      final session = FakeAccountSession(alice);
      final together = FakeTogetherBackend()..hold = Completer<void>();
      final c = container(session: session, together: together);
      await settle(c);
      final starting = ctl(c).start(TogetherActivity.timeTogether);
      expect(c.read(togetherProvider), isA<TogetherStarting>());

      session.emit(null);
      await settle(c);
      together.hold!.complete();
      await starting;
      expect(await settle(c), isA<TogetherUnavailable>());
    });

    test('a join in flight across an account switch is dropped', () async {
      final session = FakeAccountSession(alice);
      final together = FakeTogetherBackend();
      final c = container(session: session, together: together);
      await settle(c);
      together.partnerStarts();
      await settle(c);
      together.hold = Completer<void>();
      final joining = ctl(c).join();
      session.emit(AccountId('uidBob'));
      await settle(c);
      together.hold!.complete();
      await joining;
      expect(c.read(togetherProvider), isNot(isA<TogetherActive>()));
    });
  });

  test('logs carry state kinds only: no IDs, names or content', () async {
    final together = FakeTogetherBackend()
      ..failJoin = TogetherFailure.deviceNotTrusted;
    final c = container(together: together);
    await settle(c);
    await ctl(c).start(TogetherActivity.timeTogether);
    together.partnerJoins(at: DateTime.utc(2026));
    await settle(c);
    await ctl(c).leave();
    await settle(c);
    ctl(c).dismiss();
    await settle(c);
    together.partnerStarts();
    await settle(c);
    await ctl(c).join();
    await settle(c);

    final logged = sink.records
        .map((r) => '${r.event} ${r.fields} ${r.errorType}')
        .join('\n');
    expect(logged, contains('together_state_changed'));
    expect(logged, contains('activity_join_failed'));
    for (final secret in [...secretValues, 'Asha', 'Ravi', 'uidBob']) {
      expect(logged, isNot(contains(secret)));
    }
  });
}
