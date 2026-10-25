import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sirf_hum/app/product_area.dart';
import 'package:sirf_hum/features/moments/application/moment_photo_picker.dart';
import 'package:sirf_hum/features/moments/application/moments_controller.dart';
import 'package:sirf_hum/features/moments/presentation/moment_photo_view.dart';
import 'package:sirf_hum/features/moments/presentation/moment_tile.dart';
import 'package:sirf_hum/features/moments/presentation/moments_screen.dart';
import 'package:sirf_hum/security/moments/moment.dart';
import 'package:sirf_hum/security/moments/moment_payload.dart';
import 'package:sirf_hum/security/moments/moments_service.dart';

import '../../support/moments_fakes.dart';
import '../../support/session_fakes.dart';

void main() {
  setUpAll(() => WidgetController.hitTestWarningShouldBeFatal = true);
  tearDownAll(() => WidgetController.hitTestWarningShouldBeFatal = false);

  Future<void> pumpMoments(
    WidgetTester tester, {
    FakeMomentsBackend? backend,
    bool noBackend = false,
    bool privateContent = true,
    MomentPhotoPicker? picker,
    FakeAccountSession? session,
    String? location,
    Size size = const Size(390, 844),
  }) async {
    setPhoneWindow(tester, size);
    await pumpSirfHum(
      tester,
      session: session,
      privateContent: privateContent,
      initialLocation: location ?? ProductArea.moments.path,
      extra: [
        momentsBackendProvider.overrideWithValue(
          noBackend ? null : backend ?? FakeMomentsBackend(),
        ),
        momentPhotoPickerProvider.overrideWithValue(
          picker ?? (noBackend ? null : FakePhotoPicker()),
        ),
      ],
    );
  }

  /// Handles must never be rendered or announced.
  void expectNoHandles(WidgetTester tester) {
    expectNoSecretsOnScreen(tester);
    final strings = visibleStrings(tester).join('\n');
    expect(strings, isNot(contains('feed')), reason: 'a handle leaked');
    expect(strings, isNot(contains('Exception')));
    expect(strings, isNot(contains('MomentFailure')));
  }

  Finder text(String s) => find.text(s);

  Future<void> tapVisible(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  group('entry states', () {
    testWidgets('production today: honest, nothing to add', (tester) async {
      await pumpMoments(tester, noBackend: true);
      expect(text('Your first memory is waiting.'), findsOneWidget);
      expect(
        text('Saving memories opens in an upcoming version of Sirf Hum.'),
        findsOneWidget,
      );
      expect(find.text('Create a new memory'), findsNothing);
      expect(find.byType(FilledButton), findsNothing);
    });

    testWidgets('web: says where moments live; no private path at all', (
      tester,
    ) async {
      final backend = FakeMomentsBackend([fakeMoment(1, caption: 'secret')]);
      await pumpMoments(tester, backend: backend, privateContent: false);
      expect(
        text(
          'Moments stay private to your phones. Open them in the Sirf Hum app.',
        ),
        findsOneWidget,
      );
      expect(text('secret'), findsNothing);
      expect(find.text('Create a new memory'), findsNothing);
      expect(backend.opened, isEmpty);
    });

    testWidgets('empty: the first memory is waiting, with one way in', (
      tester,
    ) async {
      await pumpMoments(tester);
      expect(text('Your first memory is waiting.'), findsOneWidget);
      expect(find.text('Create a new memory'), findsOneWidget);
    });

    testWidgets('local first: this phone’s memories show while the check '
        'for new ones runs', (tester) async {
      final backend = FakeMomentsBackend([fakeMoment(1, caption: 'ours')])
        ..refreshGate = Completer();
      setPhoneWindow(tester);
      await pumpSirfHum(
        tester,
        initialLocation: ProductArea.moments.path,
        settle: false,
        extra: [momentsBackendProvider.overrideWithValue(backend)],
      );
      for (var i = 0; i < 5; i++) {
        await tester.pump();
      }
      expect(find.byType(MomentTile), findsOneWidget);
      expect(backend.refreshes, 1);
      backend.refreshGate!.complete();
      await tester.pumpAndSettle();
      expect(find.byType(MomentTile), findsOneWidget);
    });

    testWidgets('blocked: nothing private, no button that cannot help', (
      tester,
    ) async {
      final backend = FakeMomentsBackend([fakeMoment(1, caption: 'ours')])
        ..refreshError = const MomentException(MomentFailure.deviceNotTrusted);
      await pumpMoments(tester, backend: backend);
      expect(text('Set up this phone to open Moments.'), findsOneWidget);
      expect(text('ours'), findsNothing);
      expect(find.byType(MomentPhotoView), findsNothing);
      // The one button left is the way forward: set the phone up again.
      expect(
        find.widgetWithText(FilledButton, 'Set up this phone'),
        findsOneWidget,
      );
      expectNoHandles(tester);
    });

    testWidgets('failed: calm copy and a retry that works', (tester) async {
      final backend = FakeMomentsBackend()..loadError = StateError('x');
      await pumpMoments(tester, backend: backend);
      expect(text('Your moments couldn’t be opened.'), findsOneWidget);
      backend.loadError = null;
      await tester.tap(find.widgetWithText(FilledButton, 'Try again'));
      await tester.pumpAndSettle();
      expect(text('Your first memory is waiting.'), findsOneWidget);
      expectNoHandles(tester);
    });
  });

  group('timeline', () {
    testWidgets('filed by month, newest first, read in words', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpMoments(
        tester,
        backend: FakeMomentsBackend([
          fakeMoment(1, caption: 'Goa', photos: 3, addedByYou: false),
          fakeMoment(
            2,
            memoryDate: MomentDate(2024, 3, 4),
            status: MomentStatus.saving,
          ),
        ]),
      );
      expect(text('October 2026'), findsOneWidget);
      expect(text('March 2024'), findsOneWidget);
      // Highlights run newest first, left to right.
      expect(
        tester.getTopLeft(text('October 2026')).dx,
        lessThan(tester.getTopLeft(text('March 2024')).dx),
      );
      expect(
        find.bySemanticsLabel(
          RegExp(r'^Memory from .*, 3 photos, added by Ravi, Goa$'),
        ),
        findsOneWidget,
      );
      expect(
        find.bySemanticsLabel(RegExp(r'March 4, 2024.*added by you, saving')),
        findsOneWidget,
      );
      expect(find.byType(Image), findsWidgets, reason: 'covers decrypted');
      expectNoHandles(tester);
      handle.dispose();
    });

    testWidgets('earlier memories come a page at a time', (tester) async {
      await pumpMoments(
        tester,
        backend: FakeMomentsBackend([
          for (var i = 0; i < 30; i++) fakeMoment(i),
        ]),
      );
      final earlier = find.widgetWithText(
        OutlinedButton,
        'Show earlier memories',
      );
      await tapVisible(tester, earlier);
      expect(earlier, findsNothing);
    });

    testWidgets('offline: what is here stays, with a quiet notice', (
      tester,
    ) async {
      final backend = FakeMomentsBackend([fakeMoment(1, caption: 'ours')])
        ..refreshError = const MomentException(MomentFailure.unavailable);
      await pumpMoments(tester, backend: backend);
      expect(
        text(
          'Couldn’t check for new memories. You’re seeing what’s on this '
          'phone.',
        ),
        findsOneWidget,
      );
      backend.refreshError = null;
      await tester.tap(find.widgetWithText(TextButton, 'Try again'));
      await tester.pumpAndSettle();
      expect(text('Couldn’t check for new memories.'), findsNothing);
    });

    testWidgets('an unreadable memory says so calmly', (tester) async {
      await pumpMoments(
        tester,
        backend: FakeMomentsBackend([
          UnreadableMoment(
            handle: MomentHandle(fakeId(9)),
            addedAt: DateTime(2026, 10, 1),
          ),
        ]),
      );
      await tapVisible(tester, find.byType(MomentTile).first);
      await tester.pumpAndSettle();
      expect(text('This memory couldn’t be opened.'), findsOneWidget);
      expectNoHandles(tester);
    });
  });

  group('detail', () {
    testWidgets('photos, caption, dates and count; back returns', (
      tester,
    ) async {
      final m = fakeMoment(
        1,
        caption: 'Our first evening by the sea',
        photos: 2,
        memoryDate: MomentDate(2026, 10, 18),
      );
      final backend = FakeMomentsBackend([m]);
      await pumpMoments(tester, backend: backend);
      await tapVisible(tester, find.byType(MomentTile).first);
      await tester.pumpAndSettle();
      expect(text('Our first evening by the sea'), findsOneWidget);
      expect(text('Sunday, October 18, 2026'), findsOneWidget);
      expect(find.textContaining('Added by you'), findsOneWidget);
      expect(find.textContaining('2 photos'), findsOneWidget);
      expect(backend.opened, containsAll(m.photos));
      for (final social in ['Like', 'Comment', 'Share', 'Follow']) {
        expect(find.textContaining(social), findsNothing);
      }
      expectNoHandles(tester);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(text('Moments'), findsWidgets);
    });

    testWidgets('a photo that cannot open is never blank; retry when it can '
        'help', (tester) async {
      final m = fakeMoment(1, photos: 2);
      final backend = FakeMomentsBackend([m]);
      backend.photoErrors[m.photos[0]] = const MomentException(
        MomentFailure.corrupted,
      );
      backend.photoErrors[m.photos[1]] = const MomentException(
        MomentFailure.unavailable,
      );
      await pumpMoments(tester, backend: backend);
      await tapVisible(tester, find.byType(MomentTile).first);
      await tester.pumpAndSettle();
      expect(text('This photo couldn’t be opened.'), findsOneWidget);
      expect(text('This photo isn’t on this phone yet.'), findsOneWidget);
      backend.photoErrors.remove(m.photos[1]);
      final before = backend.opened.length;
      await tapVisible(tester, find.widgetWithText(TextButton, 'Try again'));
      expect(backend.opened.length, before + 1);
      expect(text('This photo isn’t on this phone yet.'), findsNothing);
      expect(text('This photo couldn’t be opened.'), findsOneWidget);
    });

    testWidgets('photos still arriving are said, not invented', (tester) async {
      await pumpMoments(
        tester,
        backend: FakeMomentsBackend([
          fakeMoment(
            1,
            photos: 1,
            photoCount: 3,
            addedByYou: false,
            problem: MomentProblem.photosArriving,
          ),
        ]),
      );
      await tapVisible(tester, find.byType(MomentTile).first);
      await tester.pumpAndSettle();
      expect(text('Some photos are still on their way.'), findsOneWidget);
      expect(find.byType(MomentPhotoView), findsOneWidget);
    });

    testWidgets('signing out while a memory is open leaves nothing behind', (
      tester,
    ) async {
      final session = FakeAccountSession(alice);
      await pumpMoments(
        tester,
        session: session,
        backend: FakeMomentsBackend([fakeMoment(1, caption: 'ours')]),
      );
      await tapVisible(tester, find.byType(MomentTile).first);
      await tester.pumpAndSettle();
      session.emit(null);
      await tester.pumpAndSettle();
      expect(text('ours'), findsNothing);
      expect(find.byType(MomentPhotoView), findsNothing);
    });
  });

  group('adding a memory', () {
    testWidgets('choose → preview → note → save → back on the timeline', (
      tester,
    ) async {
      final picker = FakePhotoPicker();
      final backend = FakeMomentsBackend()
        ..onCreated = (d) => fakeMoment(5, caption: d.caption?.trim());
      await pumpMoments(tester, backend: backend, picker: picker);
      await tapVisible(tester, find.text('Create a new memory'));
      await tester.pumpAndSettle();
      expect(text('Keep a memory'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Save memory'), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Save memory'),
            )
            .onPressed,
        isNull,
        reason: 'nothing chosen yet',
      );

      picker.next = [picker.photo(), picker.photo()];
      await tester.tap(find.widgetWithText(FilledButton, 'Choose photos'));
      await tester.pumpAndSettle();
      expect(find.bySemanticsLabel('Chosen photo 2'), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'By the sea');
      await tapVisible(
        tester,
        find.widgetWithText(FilledButton, 'Save memory'),
      );
      expect(backend.created.single.photos, hasLength(2));
      expect(backend.created.single.caption, 'By the sea');
      expect(text('Saved. It’s here for both of you.'), findsOneWidget);
      expect(text('Keep a memory'), findsNothing);
      expect(picker.released, hasLength(2), reason: 'temporary copies gone');
    });

    testWidgets('saved on the phone only: said plainly', (tester) async {
      final picker = FakePhotoPicker();
      final backend = FakeMomentsBackend()
        ..outcome = MomentSaveOutcome.savedOnPhone;
      await pumpMoments(tester, backend: backend, picker: picker);
      await tapVisible(tester, find.text('Create a new memory'));
      await tester.pumpAndSettle();
      picker.next = [picker.photo()];
      await tester.tap(find.widgetWithText(FilledButton, 'Choose photos'));
      await tester.pumpAndSettle();
      await tapVisible(
        tester,
        find.widgetWithText(FilledButton, 'Save memory'),
      );
      expect(
        text('Saved on this phone. It will finish when you’re back online.'),
        findsOneWidget,
      );
    });

    testWidgets('a failed save says nothing was saved, and can be retried', (
      tester,
    ) async {
      final picker = FakePhotoPicker();
      final backend = FakeMomentsBackend()
        ..createError = const MomentException(MomentFailure.photoTooLarge);
      await pumpMoments(tester, backend: backend, picker: picker);
      await tapVisible(tester, find.text('Create a new memory'));
      await tester.pumpAndSettle();
      picker.next = [picker.photo()];
      await tester.tap(find.widgetWithText(FilledButton, 'Choose photos'));
      await tester.pumpAndSettle();
      await tapVisible(
        tester,
        find.widgetWithText(FilledButton, 'Save memory'),
      );
      expect(
        find.textContaining(
          'too large to keep (over 64 MB). Nothing was saved',
        ),
        findsOneWidget,
      );
      expect(text('Keep a memory'), findsOneWidget);
      expectNoHandles(tester);
    });

    testWidgets('while saving the screen cannot be left', (tester) async {
      final picker = FakePhotoPicker();
      final backend = FakeMomentsBackend()..createGate = Completer();
      await pumpMoments(tester, backend: backend, picker: picker);
      await tapVisible(tester, find.text('Create a new memory'));
      await tester.pumpAndSettle();
      picker.next = [picker.photo()];
      await tester.tap(find.widgetWithText(FilledButton, 'Choose photos'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.widgetWithText(FilledButton, 'Save memory'),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Save memory'));
      await tester.pump();
      expect(text('Saving your memory…'), findsOneWidget);
      final close = tester.widget<IconButton>(
        find.widgetWithIcon(IconButton, Icons.close).first,
      );
      expect(close.onPressed, isNull);
      expect(picker.released, isEmpty);
      backend.createGate!.complete();
      await tester.pumpAndSettle();
      expect(backend.created, hasLength(1));
    });
  });

  testWidgets('Home tells the truth about kept memories', (tester) async {
    await pumpMoments(
      tester,
      location: ProductArea.home.path,
      backend: FakeMomentsBackend([fakeMoment(1), fakeMoment(2)]),
    );
    expect(text('2 memories'), findsOneWidget);
    expect(text('Your first memory is waiting.'), findsNothing);
  });

  group('accessibility', () {
    final states = <String, FakeMomentsBackend Function()>{
      'empty': FakeMomentsBackend.new,
      'timeline': () => FakeMomentsBackend([
        fakeMoment(1, caption: 'Goa', photos: 3),
        fakeMoment(2, status: MomentStatus.saving),
        UnreadableMoment(
          handle: MomentHandle(fakeId(3)),
          addedAt: DateTime(2026, 9, 1),
        ),
      ]),
      'blocked': () => FakeMomentsBackend()
        ..refreshError = const MomentException(MomentFailure.deviceNotTrusted),
      'offline': () =>
          FakeMomentsBackend([fakeMoment(1)])
            ..refreshError = const MomentException(MomentFailure.unavailable),
    };
    for (final brightness in Brightness.values) {
      for (final MapEntry(key: name, value: make) in states.entries) {
        testWidgets('$name meets guidelines in ${brightness.name}', (
          tester,
        ) async {
          tester.platformDispatcher.platformBrightnessTestValue = brightness;
          addTearDown(
            tester.platformDispatcher.clearPlatformBrightnessTestValue,
          );
          final handle = tester.ensureSemantics();
          await pumpMoments(tester, backend: make());
          await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
          await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
          await expectLater(tester, meetsGuideline(textContrastGuideline));
          handle.dispose();
        });
      }

      testWidgets('detail and composer meet guidelines in ${brightness.name}', (
        tester,
      ) async {
        tester.platformDispatcher.platformBrightnessTestValue = brightness;
        addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
        final handle = tester.ensureSemantics();
        final picker = FakePhotoPicker();
        await pumpMoments(
          tester,
          picker: picker,
          backend: FakeMomentsBackend([fakeMoment(1, caption: 'Goa')]),
        );
        await tapVisible(tester, find.byType(MomentTile).first);
        await tester.pumpAndSettle();
        await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
        await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
        await expectLater(tester, meetsGuideline(textContrastGuideline));
        await tester.pageBack();
        await tester.pumpAndSettle();
        await tapVisible(tester, find.text('Create a new memory'));
        await tester.pumpAndSettle();
        picker.next = [picker.photo()];
        await tester.tap(find.widgetWithText(FilledButton, 'Choose photos'));
        await tester.pumpAndSettle();
        await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
        await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
        await expectLater(tester, meetsGuideline(textContrastGuideline));
        handle.dispose();
      });
    }

    for (final MapEntry(key: name, value: make) in states.entries) {
      testWidgets('$name survives 200% text', (tester) async {
        tester.platformDispatcher.textScaleFactorTestValue = 2;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        await pumpMoments(tester, backend: make(), size: const Size(360, 740));
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('detail and composer survive 200% text on a small phone', (
      tester,
    ) async {
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final picker = FakePhotoPicker();
      await pumpMoments(
        tester,
        picker: picker,
        size: const Size(360, 740),
        backend: FakeMomentsBackend([
          fakeMoment(1, caption: 'A long caption ' * 10, photos: 2),
        ]),
      );
      await tester.scrollUntilVisible(
        find.byType(MomentTile),
        200,
        // The page, not the chips or highlights strips inside it.
        scrollable: find
            .descendant(
              of: find.byType(MomentsScreen),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      expect(tester.takeException(), isNull, reason: 'timeline at 200%');
      await tapVisible(tester, find.byType(MomentTile).first);
      expect(tester.takeException(), isNull);
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('Create a new memory'),
        -200,
        scrollable: find
            .descendant(
              of: find.byType(MomentsScreen),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tapVisible(tester, find.text('Create a new memory'));
      picker.next = [
        for (var i = 0; i < MomentPayload.maxPhotos; i++) picker.photo(),
      ];
      await tapVisible(
        tester,
        find.widgetWithText(FilledButton, 'Choose photos'),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('wide windows: a readable width', (tester) async {
      await pumpMoments(
        tester,
        size: const Size(1280, 900),
        backend: FakeMomentsBackend([
          for (var i = 0; i < 8; i++)
            fakeMoment(i, addedAt: DateTime(2026, 10, 1 + i)),
        ]),
      );
      final first = tester.getSize(find.byType(MomentTile).first);
      expect(first.width, lessThan(720));
      expect(tester.takeException(), isNull);
    });
  });
}
