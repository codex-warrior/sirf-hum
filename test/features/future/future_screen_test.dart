import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sirf_hum/app/product_area.dart';
import 'package:sirf_hum/features/future/application/future_providers.dart';
import 'package:sirf_hum/features/future/presentation/future_screen.dart';
import 'package:sirf_hum/features/notebook/application/notebook_controller.dart';
import 'package:sirf_hum/features/notebook/presentation/notebook_editor_screen.dart';
import 'package:sirf_hum/security/moments/moment_payload.dart';
import 'package:sirf_hum/security/notebook/notebook_payload.dart';
import 'package:sirf_hum/security/notebook/notebook_service.dart';

import '../../support/notebook_fakes.dart';
import '../../support/session_fakes.dart';

void main() {
  setUpAll(() => WidgetController.hitTestWarningShouldBeFatal = true);
  tearDownAll(() => WidgetController.hitTestWarningShouldBeFatal = false);

  Future<void> pumpFuture(
    WidgetTester tester, {
    FakeNotebookBackend? backend,
    bool noBackend = false,
    bool privateContent = true,
    Size size = const Size(390, 844),
  }) async {
    setPhoneWindow(tester, size);
    await pumpSirfHum(
      tester,
      privateContent: privateContent,
      initialLocation: ProductArea.future.path,
      extra: [
        notebookBackendProvider.overrideWithValue(
          noBackend ? null : backend ?? FakeNotebookBackend(),
        ),
        futureClockProvider.overrideWithValue(() => DateTime(2026, 10, 20, 9)),
      ],
    );
  }

  void expectNoHandles(WidgetTester tester) {
    expectNoSecretsOnScreen(tester);
    final strings = visibleStrings(tester).join('\n');
    expect(strings, isNot(contains('beef')), reason: 'a handle leaked');
    expect(strings, isNot(contains('NotebookFailure')));
  }

  Future<void> tapVisible(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  /// For widgets below the fold of a lazy page (not built yet).
  Future<void> tapScrolled(WidgetTester tester, Finder finder) async {
    await tester.scrollUntilVisible(
      finder,
      200,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.pumpAndSettle();
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  Future<void> openAdd(WidgetTester tester) =>
      tapVisible(tester, find.widgetWithText(FilledButton, 'Add something'));

  Finder text(String s) => find.text(s);

  group('entry states', () {
    testWidgets('production today: honest, nothing to add', (tester) async {
      await pumpFuture(tester, noBackend: true);
      expect(text('There’s a lot ahead of you.'), findsOneWidget);
      expect(
        text('Saving to Future opens in an upcoming version of Sirf Hum.'),
        findsOneWidget,
      );
      expect(text('Add something'), findsNothing);
    });

    testWidgets('web: says where Future lives; no private path at all', (
      tester,
    ) async {
      final backend = FakeNotebookBackend([fakeEntry(1, plan('secret'))]);
      await pumpFuture(tester, backend: backend, privateContent: false);
      expect(
        text(
          'Future stays private to your phones. Open it in the Sirf Hum '
          'app.',
        ),
        findsOneWidget,
      );
      expect(text('secret'), findsNothing);
      expect(text('Add something'), findsNothing);
      expect(backend.refreshes, 0);
    });

    testWidgets('empty: the product’s own words and one way in', (
      tester,
    ) async {
      await pumpFuture(tester);
      expect(text('There’s a lot ahead of you.'), findsOneWidget);
      expect(text('Save something you want to do together.'), findsOneWidget);
      expect(
        find.widgetWithText(FilledButton, 'Add something'),
        findsOneWidget,
      );
    });

    testWidgets('blocked: nothing private, no way to add', (tester) async {
      final backend = FakeNotebookBackend([fakeEntry(1, plan('ours'))])
        ..refreshError = const NotebookException(
          NotebookFailure.deviceNotTrusted,
        );
      await pumpFuture(tester, backend: backend);
      expect(text('Future isn’t available on this phone.'), findsOneWidget);
      expect(text('ours'), findsNothing);
      expect(find.byType(FilledButton), findsNothing);
      expectNoHandles(tester);
    });

    testWidgets('failed: calm copy and a retry that works', (tester) async {
      final backend = FakeNotebookBackend()..loadError = StateError('x');
      await pumpFuture(tester, backend: backend);
      expect(text('Future couldn’t be opened.'), findsOneWidget);
      backend.loadError = null;
      await tester.tap(text('Try again'));
      await tester.pumpAndSettle();
      expect(text('There’s a lot ahead of you.'), findsOneWidget);
    });

    testWidgets('loading shows a skeleton, then what is on this phone', (
      tester,
    ) async {
      final backend = FakeNotebookBackend([fakeEntry(1, plan('Goa'))])
        ..refreshGate = Completer();
      setPhoneWindow(tester);
      await pumpSirfHum(
        tester,
        initialLocation: ProductArea.future.path,
        settle: false,
        extra: [notebookBackendProvider.overrideWithValue(backend)],
      );
      for (var i = 0; i < 5; i++) {
        await tester.pump();
      }
      expect(text('Goa'), findsOneWidget, reason: 'local first');
      backend.refreshGate!.complete();
      await tester.pumpAndSettle();
      expect(text('Goa'), findsOneWidget);
    });

    testWidgets('offline and unreadable changes are said plainly', (
      tester,
    ) async {
      final backend = FakeNotebookBackend([fakeEntry(1, plan('Goa'))])
        ..unreadable = 2
        ..refreshError = const NotebookException(NotebookFailure.unavailable);
      await pumpFuture(tester, backend: backend);
      expect(text('Goa'), findsOneWidget);
      expect(
        text(
          'Couldn’t check for changes. You’re seeing what’s on this '
          'phone.',
        ),
        findsOneWidget,
      );
      expect(
        text('2 changes couldn’t be opened on this phone.'),
        findsOneWidget,
      );
      backend.refreshError = null;
      await tester.tap(text('Try again'));
      await tester.pumpAndSettle();
      expect(text('Try again'), findsNothing);
    });
  });

  group('the notebook', () {
    testWidgets('files plans the way the couple thinks of them', (
      tester,
    ) async {
      await pumpFuture(
        tester,
        backend: FakeNotebookBackend([
          fakeEntry(1, plan('Go to Udaipur', date: MomentDate(2026, 10, 28))),
          fakeEntry(
            2,
            plan('Try that new café', category: FutureCategory.tryThing),
          ),
          fakeEntry(3, plan('Manali', category: FutureCategory.place)),
          fakeEntry(4, plan('Goa', category: FutureCategory.place, done: true)),
          fakeEntry(
            5,
            plan(
              'Anniversary',
              category: FutureCategory.importantDate,
              date: MomentDate(2027, 3, 12),
            ),
          ),
          fakeEntry(6, plan('Old plan', date: MomentDate(2026, 1, 1))),
        ]),
      );
      for (final heading in [
        'Coming up',
        'Plans',
        'Places',
        'Things to try',
        'Important dates',
        'Done together',
      ]) {
        expect(text(heading), findsOneWidget, reason: heading);
      }
      expect(text('Go to Udaipur'), findsOneWidget);
      final day = const DefaultMaterialLocalizations().formatMediumDate(
        DateTime(2026, 10, 28),
      );
      expect(find.text('Plan · $day'), findsOneWidget);
      // A past day is shown as a day: never "missed" or "overdue".
      final strings = visibleStrings(tester).join('\n').toLowerCase();
      for (final word in ['missed', 'overdue', 'late', 'streak', '%']) {
        expect(strings, isNot(contains(word)), reason: word);
      }
      expectNoHandles(tester);
    });

    testWidgets('add: kind, name, note → saved for both of you', (
      tester,
    ) async {
      final backend = FakeNotebookBackend();
      await pumpFuture(tester, backend: backend);
      await openAdd(tester);
      expect(find.byType(NotebookEditorScreen), findsOneWidget);

      await tester.tap(find.widgetWithText(ChoiceChip, 'Place'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, 'Where do you want to go?'),
        '  Udaipur  ',
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'Anything to remember? (optional)'),
        'The lake palace',
      );
      await tapVisible(tester, find.widgetWithText(TextButton, 'Save'));

      final f = backend.created.single;
      expect(f.section, NotebookSection.future);
      expect(f.category, FutureCategory.place.wireValue);
      expect(f.status, FutureStatus.planned.wireValue);
      expect(f.title, 'Udaipur');
      expect(f.note, 'The lake palace');
      expect(f.date, isNull);
      expect(find.byType(NotebookEditorScreen), findsNothing);
      expect(text('Saved. It’s here for both of you.'), findsOneWidget);
      expect(text('Udaipur'), findsOneWidget);
      expect(text('Places'), findsOneWidget);
    });

    testWidgets('add with a date: it is coming up', (tester) async {
      final backend = FakeNotebookBackend();
      await pumpFuture(tester, backend: backend);
      await openAdd(tester);
      await tester.enterText(
        find.widgetWithText(TextField, 'What do you want to do?'),
        'Dinner',
      );
      await tapVisible(tester, text('Choose a date'));
      await tester.tap(text('OK'));
      await tester.pumpAndSettle();
      expect(text('Remove date'), findsOneWidget);
      await tapVisible(tester, find.widgetWithText(TextButton, 'Save'));
      expect(backend.created.single.date, MomentDate.of(DateTime.now()));
    });

    testWidgets('save is single flight, the page cannot be left mid-save, '
        'and offline says so', (tester) async {
      final backend = FakeNotebookBackend()
        ..writeGate = Completer()
        ..outcome = NotebookSaveOutcome.savedOnPhone;
      await pumpFuture(tester, backend: backend);
      await openAdd(tester);
      await tester.enterText(find.byType(TextField).first, 'Goa');
      await tester.pump();
      final save = find.widgetWithText(TextButton, 'Save');
      await tester.ensureVisible(save);
      await tester.pumpAndSettle();
      await tester.tap(save);
      await tester.pump();
      await tester.tap(save, warnIfMissed: false);
      await tester.pump();
      expect(text('Saving…'), findsOneWidget);
      // Back does nothing while saving.
      await tester.binding.handlePopRoute();
      await tester.pump();
      expect(find.byType(NotebookEditorScreen), findsOneWidget);

      backend.writeGate!.complete();
      await tester.pumpAndSettle();
      expect(backend.created, hasLength(1));
      expect(
        text('Saved on this phone. It will finish when you’re back online.'),
        findsOneWidget,
      );
    });

    testWidgets('a failed save keeps what was typed and says nothing was '
        'saved', (tester) async {
      final backend = FakeNotebookBackend()
        ..writeError = const NotebookException(NotebookFailure.unavailable);
      await pumpFuture(tester, backend: backend);
      await openAdd(tester);
      await tester.enterText(find.byType(TextField).first, 'Goa');
      await tapVisible(tester, find.widgetWithText(TextButton, 'Save'));
      expect(find.byType(NotebookEditorScreen), findsOneWidget);
      expect(find.textContaining('Nothing was saved.'), findsOneWidget);
      expect(text('Goa'), findsOneWidget);
      await tapVisible(tester, find.widgetWithText(TextButton, 'Save'));
      expect(backend.created, hasLength(2));
      expect(find.byType(NotebookEditorScreen), findsNothing);
    });

    testWidgets('save waits for a name; close returns with nothing saved', (
      tester,
    ) async {
      final backend = FakeNotebookBackend();
      await pumpFuture(tester, backend: backend);
      await openAdd(tester);
      final save = tester.widget<TextButton>(
        find.widgetWithText(TextButton, 'Save'),
      );
      expect(save.onPressed, isNull);
      await tester.tap(find.byTooltip('Close'));
      await tester.pumpAndSettle();
      expect(find.byType(NotebookEditorScreen), findsNothing);
      expect(backend.created, isEmpty);
      expect(text('There’s a lot ahead of you.'), findsOneWidget);
    });

    testWidgets('mark done from the list: no celebration, no count', (
      tester,
    ) async {
      final backend = FakeNotebookBackend([fakeEntry(1, plan('Goa'))]);
      await pumpFuture(tester, backend: backend);
      await tester.tap(find.byTooltip('Mark as done'));
      await tester.pumpAndSettle();
      final (_, fields) = backend.updated.single;
      expect(fields.status, FutureStatus.done.wireValue);
      expect(fields.title, 'Goa');
      expect(text('Done together'), findsOneWidget);
      expect(find.byTooltip('Mark as not done'), findsOneWidget);
      expect(find.byType(SnackBar), findsNothing);
    });

    testWidgets('edit: change, mark done, remove after confirming', (
      tester,
    ) async {
      final backend = FakeNotebookBackend([
        fakeEntry(1, plan('Goa', note: 'beach'), addedByYou: false),
      ]);
      await pumpFuture(tester, backend: backend);
      await tester.tap(text('Goa'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        text('Added by Ravi'),
        200,
        scrollable: find.byType(Scrollable).last,
      );
      expect(text('Added by Ravi'), findsOneWidget);
      await tester.enterText(find.byType(TextField).first, 'Goa in March');
      await tapScrolled(tester, find.byType(CheckboxListTile));
      await tapVisible(tester, find.widgetWithText(TextButton, 'Save'));
      final (_, f) = backend.updated.single;
      expect(f.title, 'Goa in March');
      expect(f.note, 'beach');
      expect(f.status, FutureStatus.done.wireValue);

      await tester.tap(text('Goa in March'));
      await tester.pumpAndSettle();
      await tapScrolled(tester, find.widgetWithText(TextButton, 'Remove'));
      expect(text('It will disappear for both of you.'), findsOneWidget);
      await tester.tap(text('Keep'));
      await tester.pumpAndSettle();
      expect(backend.removed, isEmpty);
      await tapScrolled(tester, find.widgetWithText(TextButton, 'Remove'));
      await tester.tap(find.widgetWithText(TextButton, 'Remove').last);
      await tester.pumpAndSettle();
      expect(backend.removed, hasLength(1));
      expect(text('Removed for both of you.'), findsOneWidget);
      expect(text('Goa in March'), findsNothing);
    });

    testWidgets('changed on the other phone meanwhile: says so', (
      tester,
    ) async {
      final backend = FakeNotebookBackend([fakeEntry(1, plan('Goa'))]);
      await pumpFuture(tester, backend: backend);
      await tester.tap(text('Goa'));
      await tester.pumpAndSettle();
      backend.writeError = const NotebookException(NotebookFailure.notFound);
      await tapVisible(tester, find.widgetWithText(TextButton, 'Save'));
      expect(
        text(
          'This was changed or removed on the other phone. Nothing was '
          'saved.',
        ),
        findsOneWidget,
      );
    });
  });

  group('accessibility and layout', () {
    final states = <String, FakeNotebookBackend Function()>{
      'empty': FakeNotebookBackend.new,
      'full': () => FakeNotebookBackend([
        fakeEntry(1, plan('Go to Udaipur', date: MomentDate(2026, 10, 28))),
        fakeEntry(2, plan('Manali', category: FutureCategory.place)),
        fakeEntry(3, plan('Goa', done: true)),
        fakeEntry(
          4,
          plan(
            'Anniversary',
            category: FutureCategory.importantDate,
            date: MomentDate(2027, 3, 12),
          ),
          saving: true,
        ),
      ]),
      'blocked': () => FakeNotebookBackend()
        ..refreshError = const NotebookException(
          NotebookFailure.deviceNotTrusted,
        ),
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
          await pumpFuture(tester, backend: make());
          await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
          await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
          await expectLater(tester, meetsGuideline(textContrastGuideline));
          handle.dispose();
        });
      }

      testWidgets('the editor meets guidelines in ${brightness.name}', (
        tester,
      ) async {
        tester.platformDispatcher.platformBrightnessTestValue = brightness;
        addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
        final handle = tester.ensureSemantics();
        await pumpFuture(
          tester,
          backend: FakeNotebookBackend([fakeEntry(1, plan('Goa'))]),
        );
        await tester.tap(text('Goa'));
        await tester.pumpAndSettle();
        await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
        await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
        await expectLater(tester, meetsGuideline(textContrastGuideline));
        handle.dispose();
      });
    }

    testWidgets('done is said in words, not only by colour or a strike', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await pumpFuture(
        tester,
        backend: FakeNotebookBackend([fakeEntry(1, plan('Goa', done: true))]),
      );
      expect(find.text('Done'), findsOneWidget);
      expect(find.byTooltip('Mark as not done'), findsOneWidget);
      handle.dispose();
    });

    for (final MapEntry(key: name, value: make) in states.entries) {
      testWidgets('$name survives 200% text on a small phone', (tester) async {
        tester.platformDispatcher.textScaleFactorTestValue = 2;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        await pumpFuture(tester, backend: make(), size: const Size(360, 740));
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('the editor survives 200% text on a small phone', (
      tester,
    ) async {
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await pumpFuture(tester, size: const Size(360, 740));
      await openAdd(tester);
      expect(find.byType(NotebookEditorScreen), findsOneWidget);
      // The chips push the fields below the fold at this size.
      await tester.drag(find.byType(Scrollable).last, const Offset(0, -500));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, 'A long plan ' * 6);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    for (final size in [const Size(820, 1180), const Size(1440, 900)]) {
      testWidgets('tablet and web widths keep a readable column ($size)', (
        tester,
      ) async {
        await pumpFuture(tester, backend: states['full']!(), size: size);
        final row = tester.getSize(find.byType(FutureRow).first);
        expect(row.width, lessThanOrEqualTo(720));
        expect(tester.takeException(), isNull);
      });
    }
  });
}
