import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sirf_hum/core/logging/app_logger.dart';
import 'package:sirf_hum/features/notebook/application/notebook_controller.dart';
import 'package:sirf_hum/features/notebook/domain/notebook_state.dart';
import 'package:sirf_hum/security/couple/pairing.dart';
import 'package:sirf_hum/security/notebook/notebook_service.dart';
import 'package:sirf_hum/session/session_controller.dart';
import 'package:sirf_hum_crypto/sirf_hum_crypto.dart';

import '../../support/notebook_fakes.dart';
import '../../support/session_fakes.dart';

class _Sink implements LogSink {
  final lines = <String>[];

  @override
  void write(LogRecord record) =>
      lines.add('${record.message} ${record.fields}');
}

Matcher fails(NotebookFailure f) =>
    throwsA(isA<NotebookException>().having((e) => e.failure, 'failure', f));

void main() {
  late FakeAccountSession session;
  final bob = AccountId('uidBob0123456789abcdefXYZ');

  ProviderContainer container({
    NotebookBackend? backend,
    bool noBackend = false,
    bool privateContent = true,
    PairingBackend? pairing,

    /// Per-account backends, as production wires them (one per account).
    Map<String, NotebookBackend>? perAccount,
  }) {
    session = FakeAccountSession(alice);
    var current = alice.value;
    final c = ProviderContainer(
      overrides: sessionOverrides(
        session: session,
        backend: pairing ?? FakePairingBackend.returning(paired),
        profiles: FakeCoupleProfiles(names),
        privateContent: privateContent,
        extra: [
          if (perAccount != null)
            notebookBackendProvider.overrideWith((ref) {
              ref.watch(sessionProvider);
              return perAccount[current];
            })
          else
            notebookBackendProvider.overrideWithValue(
              noBackend ? null : backend ?? FakeNotebookBackend(),
            ),
        ],
      ),
    );
    // Lets tests switch which account the "production" provider builds for.
    _switchTo = (AccountId? a) {
      current = a?.value ?? '';
      session.emit(a);
    };
    addTearDown(c.dispose);
    return c;
  }

  Future<NotebookState> settle(ProviderContainer c) async {
    c.listen(notebookProvider, (_, _) {}, fireImmediately: true);
    for (var i = 0; i < 10; i++) {
      await Future<void>.delayed(Duration.zero);
    }
    return c.read(notebookProvider);
  }

  group('gating', () {
    test('production today: no backend → not yet available', () async {
      expect(
        await settle(container(noBackend: true)),
        isA<NotebookUnavailable>().having(
          (s) => s.reason,
          'reason',
          NotebookUnavailableReason.notYetAvailable,
        ),
      );
    });

    test('web never loads the notebook, whatever backend exists', () async {
      final backend = FakeNotebookBackend([fakeEntry(1, plan('secret'))]);
      final c = container(backend: backend, privateContent: false);
      expect(
        await settle(c),
        isA<NotebookUnavailable>().having(
          (s) => s.reason,
          'reason',
          NotebookUnavailableReason.needsPhone,
        ),
      );
      expect(backend.refreshes, 0);
      await expectLater(
        c.read(notebookProvider.notifier).create(plan('x')),
        fails(NotebookFailure.unsupported),
      );
      expect(backend.created, isEmpty);
    });

    test('not paired: nothing loads and nothing can be written', () async {
      final backend = FakeNotebookBackend([fakeEntry(1, plan('ours'))]);
      final c = container(
        backend: backend,
        pairing: FakePairingBackend.returning(const PairingNone()),
      );
      expect(await settle(c), isA<NotebookUnavailable>());
      expect(backend.refreshes, 0);
      await expectLater(
        c.read(notebookProvider.notifier).create(plan('x')),
        fails(NotebookFailure.unsupported),
      );
    });

    test('signed out: nothing from before stays, and a late answer for '
        'the old session changes nothing', () async {
      final backend = FakeNotebookBackend([fakeEntry(1, plan('ours'))]);
      final c = container(backend: backend);
      expect(await settle(c), isA<NotebookReady>());

      session.emit(null);
      expect(await settle(c), isA<NotebookUnavailable>());

      backend.refreshGate = Completer();
      session.emit(alice);
      await settle(c);
      session.emit(null);
      backend.refreshGate!.complete();
      expect(await settle(c), isA<NotebookUnavailable>());
    });

    test('account A → sign out → account B: B sees only B’s notebook, '
        'never A’s', () async {
      final a = FakeNotebookBackend([fakeEntry(1, plan('A-SECRET'))]);
      final b = FakeNotebookBackend([fakeEntry(2, plan('B-plan'))]);
      final c = container(perAccount: {alice.value: a, bob.value: b});
      final first = await settle(c);
      expect((first as NotebookReady).entries.map((e) => e.title), [
        'A-SECRET',
      ]);

      // A's refresh is slow and answers after the switch.
      a.refreshGate = Completer();
      c.read(notebookProvider.notifier).refresh().ignore();
      _switchTo(null);
      expect(await settle(c), isA<NotebookUnavailable>());
      _switchTo(bob);
      final second = await settle(c);
      a.refreshGate!.complete();
      final after = await settle(c);
      for (final s in [second, after]) {
        expect(s, isA<NotebookReady>());
        expect((s as NotebookReady).entries.map((e) => e.title), ['B-plan']);
      }
    });

    test('a write that finishes after the account changed never shows in '
        'the new session', () async {
      final a = FakeNotebookBackend()..writeGate = Completer();
      final b = FakeNotebookBackend();
      final c = container(perAccount: {alice.value: a, bob.value: b});
      await settle(c);
      final write = c.read(notebookProvider.notifier).create(plan('A-late'));
      _switchTo(bob);
      await settle(c);
      a.writeGate!.complete();
      await write;
      final s = await settle(c) as NotebookReady;
      expect(s.entries, isEmpty);
      expect(b.created, isEmpty);
    });
  });

  group('reading', () {
    test('local first, then refreshed; empty is honest', () async {
      final empty = FakeNotebookBackend();
      final state = await settle(container(backend: empty));
      expect(state, isA<NotebookReady>());
      expect((state as NotebookReady).entries, isEmpty);
      expect(empty.refreshes, 1);
    });

    test('offline keeps what is here and says so', () async {
      final backend = FakeNotebookBackend([fakeEntry(1, plan('ours'))])
        ..refreshError = const NotebookException(NotebookFailure.unavailable);
      final s = await settle(container(backend: backend)) as NotebookReady;
      expect(s.entries, hasLength(1));
      expect(s.notice, NotebookNotice.offline);
    });

    test('phones still connecting is a notice, not an error', () async {
      final backend = FakeNotebookBackend()
        ..refreshError = const NotebookException(NotebookFailure.notReady);
      final s = await settle(container(backend: backend)) as NotebookReady;
      expect(s.notice, NotebookNotice.connecting);
    });

    test('a revoked or stale device is blocked: nothing private stays, '
        'nothing can be written', () async {
      final backend = FakeNotebookBackend([fakeEntry(1, plan('ours'))])
        ..refreshError = const NotebookException(
          NotebookFailure.deviceNotTrusted,
        );
      final c = container(backend: backend);
      expect(await settle(c), isA<NotebookBlocked>());
      await expectLater(
        c.read(notebookProvider.notifier).create(plan('x')),
        fails(NotebookFailure.unsupported),
      );
      expect(backend.created, isEmpty);
    });

    test('an account no longer in the couple fails, without content', () async {
      final backend = FakeNotebookBackend([fakeEntry(1, plan('ours'))])
        ..refreshError = const NotebookException(NotebookFailure.notPaired);
      expect(
        await settle(container(backend: backend)),
        isA<NotebookFailed>().having(
          (s) => s.failure,
          'failure',
          NotebookFailure.notPaired,
        ),
      );
    });

    test('corrupted local state fails, and retry starts over', () async {
      final backend = FakeNotebookBackend()..loadError = StateError('x');
      final c = container(backend: backend);
      expect(await settle(c), isA<NotebookFailed>());
      backend.loadError = null;
      c.read(notebookProvider.notifier).retry();
      expect(await settle(c), isA<NotebookReady>());
    });
  });

  group('writing', () {
    test('create, update, done and remove reach the backend and the '
        'state', () async {
      final backend = FakeNotebookBackend();
      final c = container(backend: backend);
      await settle(c);
      final notifier = c.read(notebookProvider.notifier);

      expect(await notifier.create(plan('Goa')), NotebookSaveOutcome.saved);
      var s = c.read(notebookProvider) as NotebookReady;
      final goa = s.entries.single;
      expect(goa.title, 'Goa');

      await notifier.setDone(goa, done: true);
      s = c.read(notebookProvider) as NotebookReady;
      expect(s.entries.single.done, isTrue);
      expect(s.entries.single.title, 'Goa', reason: 'nothing else changes');

      await notifier.update(goa.handle, plan('Goa in March'));
      s = c.read(notebookProvider) as NotebookReady;
      expect(s.entries.single.title, 'Goa in March');

      await notifier.remove(goa.handle);
      s = c.read(notebookProvider) as NotebookReady;
      expect(s.entries, isEmpty);
    });

    test('losing trust during a write blocks the notebook', () async {
      final backend = FakeNotebookBackend([fakeEntry(1, plan('ours'))]);
      final c = container(backend: backend);
      await settle(c);
      backend.writeError = const NotebookException(
        NotebookFailure.deviceNotTrusted,
      );
      await expectLater(
        c.read(notebookProvider.notifier).create(plan('x')),
        fails(NotebookFailure.deviceNotTrusted),
      );
      expect(c.read(notebookProvider), isA<NotebookBlocked>());
    });

    test('a record removed on the other phone: notFound, and the state '
        'catches up', () async {
      final backend = FakeNotebookBackend([fakeEntry(1, plan('ours'))]);
      final c = container(backend: backend);
      await settle(c);
      final entry = (c.read(notebookProvider) as NotebookReady).entries.single;
      backend.entries = [];
      await expectLater(
        c.read(notebookProvider.notifier).update(entry.handle, plan('x')),
        fails(NotebookFailure.notFound),
      );
      expect((c.read(notebookProvider) as NotebookReady).entries, isEmpty);
    });
  });

  test('logs carry state kinds and counts only', () async {
    final sink = _Sink();
    AppLogger.configure(sinks: [sink], minimumLevel: LogLevel.debug);
    addTearDown(() => AppLogger.configure(sinks: const [DeveloperLogSink()]));
    final backend = FakeNotebookBackend([
      fakeEntry(1, plan('SECRET-PLAN', note: 'SECRET-NOTE')),
    ]);
    final c = container(backend: backend);
    await settle(c);
    await c.read(notebookProvider.notifier).create(plan('SECRET-NEW'));
    final all = sink.lines.join('\n');
    expect(all, contains('notebook_state_changed'));
    expect(all, isNot(contains('SECRET')));
    expect(all, isNot(contains('beef')));
    expect(all, isNot(contains(testUid)));
  });
}

late void Function(AccountId?) _switchTo;
