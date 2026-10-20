import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sirf_hum/core/logging/app_logger.dart';
import 'package:sirf_hum/features/moments/application/moment_composer.dart';
import 'package:sirf_hum/features/moments/application/moment_photo_picker.dart';
import 'package:sirf_hum/features/moments/application/moments_controller.dart';
import 'package:sirf_hum/features/moments/domain/moments_state.dart';
import 'package:sirf_hum/security/moments/moment.dart';
import 'package:sirf_hum/security/moments/moment_payload.dart';
import 'package:sirf_hum/security/moments/moments_service.dart';

import '../../support/moments_fakes.dart';
import '../../support/session_fakes.dart';

class _Sink implements LogSink {
  final lines = <String>[];

  @override
  void write(LogRecord record) =>
      lines.add('${record.message} ${record.fields}');
}

void main() {
  // The controller evicts decoded photos from the painting image cache.
  TestWidgetsFlutterBinding.ensureInitialized();
  late FakeAccountSession session;

  ProviderContainer container({
    MomentsBackend? backend,
    bool noBackend = false,
    bool privateContent = true,
    MomentPhotoPicker? picker,
  }) {
    session = FakeAccountSession(alice);
    final c = ProviderContainer(
      overrides: sessionOverrides(
        session: session,
        backend: FakePairingBackend.returning(paired),
        profiles: FakeCoupleProfiles(names),
        privateContent: privateContent,
        extra: [
          momentsBackendProvider.overrideWithValue(
            noBackend ? null : backend ?? FakeMomentsBackend(),
          ),
          momentPhotoPickerProvider.overrideWithValue(picker),
        ],
      ),
    );
    addTearDown(c.dispose);
    return c;
  }

  /// Keeps the provider alive and lets the session and first load settle.
  Future<MomentsState> settle(ProviderContainer c) async {
    c.listen(momentsProvider, (_, _) {}, fireImmediately: true);
    for (var i = 0; i < 10; i++) {
      await Future<void>.delayed(Duration.zero);
    }
    return c.read(momentsProvider);
  }

  group('gating', () {
    test('production today: no backend → not yet available', () async {
      expect(
        await settle(container(noBackend: true)),
        isA<MomentsUnavailable>().having(
          (s) => s.reason,
          'reason',
          MomentsUnavailableReason.notYetAvailable,
        ),
      );
    });

    test('web never loads moments, whatever backend exists', () async {
      final backend = FakeMomentsBackend([fakeMoment(1)]);
      final state = await settle(
        container(backend: backend, privateContent: false),
      );
      expect(
        state,
        isA<MomentsUnavailable>().having(
          (s) => s.reason,
          'reason',
          MomentsUnavailableReason.needsPhone,
        ),
      );
      expect(backend.refreshes, 0);
    });

    test(
      'signed out or switching accounts: nothing from before stays',
      () async {
        final backend = FakeMomentsBackend([fakeMoment(1, caption: 'ours')]);
        final c = container(backend: backend);
        expect(await settle(c), isA<MomentsReady>());

        session.emit(null);
        expect(await settle(c), isA<MomentsUnavailable>());

        // A refresh answer for the old session arriving late changes nothing.
        backend.refreshGate = Completer();
        session.emit(alice);
        await settle(c);
        session.emit(null);
        backend.refreshGate!.complete();
        expect(await settle(c), isA<MomentsUnavailable>());
      },
    );
  });

  group('timeline', () {
    test('local first, then refreshed; empty is honest', () async {
      final empty = FakeMomentsBackend();
      final state = await settle(container(backend: empty));
      expect(
        state,
        isA<MomentsReady>().having((s) => s.isEmpty, 'empty', true),
      );
      expect(empty.refreshes, 1);
    });

    test('bounded pages: 24, then the next page on request', () async {
      final backend = FakeMomentsBackend([
        for (var i = 0; i < 30; i++) fakeMoment(i),
      ]);
      final c = container(backend: backend);
      var ready = await settle(c) as MomentsReady;
      expect(ready.entries, hasLength(MomentsController.pageSize));
      expect(ready.total, 30);
      expect(ready.hasEarlier, isTrue);
      c.read(momentsProvider.notifier).showEarlier();
      ready = c.read(momentsProvider) as MomentsReady;
      expect(ready.entries, hasLength(30));
      expect(ready.hasEarlier, isFalse);
    });

    test(
      'offline or still connecting: what is shown stays, with a notice',
      () async {
        final backend = FakeMomentsBackend([fakeMoment(1)])
          ..refreshError = const MomentException(MomentFailure.unavailable);
        final c = container(backend: backend);
        var ready = await settle(c) as MomentsReady;
        expect(ready.entries, hasLength(1));
        expect(ready.notice, MomentsNotice.offline);

        backend.refreshError = const MomentException(MomentFailure.notReady);
        await c.read(momentsProvider.notifier).refresh();
        ready = c.read(momentsProvider) as MomentsReady;
        expect(ready.notice, MomentsNotice.connecting);

        backend.refreshError = null;
        await c.read(momentsProvider.notifier).refresh();
        expect((c.read(momentsProvider) as MomentsReady).notice, isNull);
      },
    );

    test(
      'a device that lost trust is blocked: the timeline is dropped',
      () async {
        final backend = FakeMomentsBackend(
          [fakeMoment(1)],
        )..refreshError = const MomentException(MomentFailure.deviceNotTrusted);
        final c = container(backend: backend);
        expect(await settle(c), isA<MomentsBlocked>());
        // Nothing more can be refreshed or shown from here.
        await c.read(momentsProvider.notifier).refresh();
        c.read(momentsProvider.notifier).showEarlier();
        expect(c.read(momentsProvider), isA<MomentsBlocked>());
      },
    );

    test(
      'photos fail closed once blocked, and are wiped when dropped',
      () async {
        final moment = fakeMoment(1);
        final backend = FakeMomentsBackend([moment]);
        final c = container(backend: backend);
        await settle(c);
        final photo = moment.photos.single;
        final sub = c.listen(momentPhotoProvider(photo), (_, _) {});
        final bytes = await c.read(momentPhotoProvider(photo).future);
        expect(bytes, tinyPng);

        backend.refreshError = const MomentException(
          MomentFailure.deviceNotTrusted,
        );
        await c.read(momentsProvider.notifier).refresh();
        await Future<void>.delayed(Duration.zero);
        expect(backend.handedOut.single, everyElement(0), reason: 'wiped');
        await expectLater(
          c.read(momentPhotoProvider(photo).future),
          throwsA(isA<MomentException>()),
        );
        sub.close();
      },
    );

    test('a broken local timeline fails, and can be retried', () async {
      final backend = FakeMomentsBackend([fakeMoment(1)])
        ..loadError = StateError('state corruption');
      final c = container(backend: backend);
      expect(await settle(c), isA<MomentsFailed>());
      backend.loadError = null;
      c.read(momentsProvider.notifier).retry();
      expect(await settle(c), isA<MomentsReady>());
    });

    test('an account no longer in the couple fails, showing nothing', () async {
      final backend = FakeMomentsBackend([fakeMoment(1)])
        ..refreshError = const MomentException(MomentFailure.notPaired);
      expect(
        await settle(container(backend: backend)),
        isA<MomentsFailed>().having(
          (s) => s.failure,
          'failure',
          MomentFailure.notPaired,
        ),
      );
    });

    test('logs carry state kinds only', () async {
      final sink = _Sink();
      AppLogger.configure(sinks: [sink], minimumLevel: LogLevel.debug);
      addTearDown(() => AppLogger.configure(sinks: const [DeveloperLogSink()]));
      await settle(
        container(
          backend: FakeMomentsBackend([
            fakeMoment(7, caption: 'CAPTION-SECRET'),
          ]),
        ),
      );
      final all = sink.lines.join('\n');
      expect(all, contains('moments_state_changed'));
      expect(all, isNot(contains('CAPTION-SECRET')));
      expect(all, isNot(contains(fakeId(7))));
      expect(all, isNot(contains(testUid)));
    });
  });

  group('composer', () {
    test('pick within the limit, no duplicates, remove releases', () async {
      final picker = FakePhotoPicker();
      final c = container(picker: picker);
      await settle(c);
      c.listen(momentComposerProvider, (_, _) {});
      final composer = c.read(momentComposerProvider.notifier);
      final a = picker.photo();
      picker.next = [a, a, for (var i = 0; i < 9; i++) picker.photo()];
      await composer.pick();
      expect(picker.limits.single, MomentPayload.maxPhotos);
      final photos = c.read(momentComposerProvider).photos;
      expect(photos, hasLength(MomentPayload.maxPhotos));
      expect(photos.toSet(), hasLength(photos.length));
      expect(picker.released, hasLength(2), reason: 'the extras');
      expect(composer.canPick, isFalse);

      composer.remove(a);
      expect(c.read(momentComposerProvider).photos, isNot(contains(a)));
      expect(picker.released, contains(a));
    });

    test('a picker that fails says so and keeps what was chosen', () async {
      final picker = FakePhotoPicker();
      final c = container(picker: picker);
      await settle(c);
      c.listen(momentComposerProvider, (_, _) {});
      picker.next = [picker.photo()];
      await c.read(momentComposerProvider.notifier).pick();
      picker.fail = true;
      await c.read(momentComposerProvider.notifier).pick();
      final s = c.read(momentComposerProvider);
      expect(s.pickerFailed, isTrue);
      expect(s.photos, hasLength(1));
      expect(s.phase, ComposerPhase.editing);
    });

    test('saves exactly once, even when tapped twice', () async {
      final picker = FakePhotoPicker();
      final backend = FakeMomentsBackend()..createGate = Completer();
      final c = container(backend: backend, picker: picker);
      await settle(c);
      c.listen(momentComposerProvider, (_, _) {});
      final composer = c.read(momentComposerProvider.notifier);
      picker.next = [picker.photo(size: 4242)];
      await composer.pick();
      composer
        ..setCaption('  by the sea  ')
        ..setDate(MomentDate(2026, 10, 18));
      final first = composer.save();
      final second = composer.save();
      expect(c.read(momentComposerProvider).phase, ComposerPhase.saving);
      backend.createGate!.complete();
      await Future.wait([first, second]);
      expect(backend.created, hasLength(1));
      final draft = backend.created.single;
      expect(draft.photos.single.sizeBytes, 4242);
      expect(draft.caption, '  by the sea  ');
      expect(draft.memoryDate, MomentDate(2026, 10, 18));
      final s = c.read(momentComposerProvider);
      expect(s.phase, ComposerPhase.saved);
      expect(s.outcome, MomentSaveOutcome.saved);
      await composer.save();
      expect(backend.created, hasLength(1), reason: 'no second moment');
    });

    test(
      'a failed save kept nothing: photos stay, it can be retried',
      () async {
        final picker = FakePhotoPicker();
        final backend = FakeMomentsBackend()
          ..createError = const MomentException(MomentFailure.notReady);
        final c = container(backend: backend, picker: picker);
        await settle(c);
        c.listen(momentComposerProvider, (_, _) {});
        final composer = c.read(momentComposerProvider.notifier);
        picker.next = [picker.photo()];
        await composer.pick();
        await composer.save();
        var s = c.read(momentComposerProvider);
        expect(s.failed, isTrue);
        expect(s.failure, MomentFailure.notReady);
        expect(s.photos, hasLength(1));
        expect(s.canSave, isTrue);
        backend.createError = null;
        await composer.save();
        s = c.read(momentComposerProvider);
        expect(s.phase, ComposerPhase.saved);
        expect(backend.created, hasLength(2));
      },
    );

    test(
      'picked copies are released only after the save has read them',
      () async {
        final picker = FakePhotoPicker();
        final backend = FakeMomentsBackend()..createGate = Completer();
        final c = container(backend: backend, picker: picker);
        await settle(c);
        final sub = c.listen(momentComposerProvider, (_, _) {});
        final composer = c.read(momentComposerProvider.notifier);
        final p = picker.photo();
        picker.next = [p];
        await composer.pick();
        final saving = composer.save();
        sub.close(); // the screen goes away mid-save
        await Future<void>.delayed(Duration.zero);
        expect(picker.released, isEmpty);
        backend.createGate!.complete();
        await saving;
        await Future<void>.delayed(Duration.zero);
        expect(picker.released, [p]);
      },
    );

    test('without a backend nothing is saved', () async {
      final picker = FakePhotoPicker();
      final c = container(noBackend: true, picker: picker);
      await settle(c);
      c.listen(momentComposerProvider, (_, _) {});
      picker.next = [picker.photo()];
      await c.read(momentComposerProvider.notifier).pick();
      await c.read(momentComposerProvider.notifier).save();
      expect(c.read(momentComposerProvider).failure, MomentFailure.unsupported);
    });
  });

  test('handles never print their value', () {
    expect('${MomentHandle(fakeId(1))}', isNot(contains(fakeId(1))));
    expect(
      '${const MomentInput(path: '/x/secret.jpg', sizeBytes: 1)}',
      isNot(contains('secret')),
    );
  });
}
