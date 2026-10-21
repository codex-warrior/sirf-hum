import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sirf_hum/app/product_area.dart';
import 'package:sirf_hum/features/future/application/future_providers.dart';
import 'package:sirf_hum/features/notebook/application/notebook_controller.dart';
import 'package:sirf_hum/features/notebook/presentation/notebook_editor_screen.dart';
import 'package:sirf_hum/security/moments/moment_payload.dart';
import 'package:sirf_hum/security/notebook/notebook_payload.dart';
import 'package:sirf_hum/security/notebook/notebook_service.dart';

import '../../support/notebook_fakes.dart';
import '../../support/session_fakes.dart';

NotebookFields _story(String title, {String? note, MomentDate? date}) =>
    NotebookFields(
      section: NotebookSection.story,
      title: title,
      note: note,
      date: date,
    );

NotebookFields _thing(LittleThingKind kind, String title) => NotebookFields(
  section: NotebookSection.littleThing,
  category: kind.wireValue,
  title: title,
);

NotebookFields _ritual(String title, {String? often}) => NotebookFields(
  section: NotebookSection.ritual,
  title: title,
  detail: often,
);

NotebookFields _since(MomentDate date) =>
    NotebookFields(section: NotebookSection.togetherSince, date: date);

String _day(MomentDate d) =>
    const DefaultMaterialLocalizations().formatMediumDate(d.toLocal());

void main() {
  setUpAll(() => WidgetController.hitTestWarningShouldBeFatal = true);
  tearDownAll(() => WidgetController.hitTestWarningShouldBeFatal = false);

  Future<void> pumpUs(
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
      initialLocation: ProductArea.us.path,
      extra: [
        notebookBackendProvider.overrideWithValue(
          noBackend ? null : backend ?? FakeNotebookBackend(),
        ),
        futureClockProvider.overrideWithValue(() => DateTime(2026, 10, 20, 9)),
      ],
    );
  }

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

  Future<void> scrollTo(WidgetTester tester, Finder finder) =>
      tester.scrollUntilVisible(
        finder,
        200,
        scrollable: find.byType(Scrollable).last,
      );

  Finder text(String s) => find.text(s);

  final full = [
    fakeEntry(1, _since(MomentDate(2021, 3, 12))),
    fakeEntry(
      2,
      _story(
        'How we started',
        note: 'A rainy Tuesday.',
        date: MomentDate(2021, 3, 12),
      ),
    ),
    fakeEntry(3, _thing(LittleThingKind.ourSong, 'Tum Hi Ho')),
    fakeEntry(4, _ritual('Friday movie', often: 'Every Friday')),
    fakeEntry(
      5,
      plan(
        'Anniversary',
        category: FutureCategory.importantDate,
        date: MomentDate(2027, 3, 12),
      ),
    ),
    fakeEntry(6, plan('Goa')), // a plan: Future only, not Us
  ];

  group('entry states', () {
    testWidgets('production today: names, an honest notice, sign out', (
      tester,
    ) async {
      await pumpUs(tester, noBackend: true);
      expect(text('Asha & Ravi'), findsOneWidget);
      expect(text('This is your space.'), findsOneWidget);
      expect(
        text('Fill it with the little things that are yours.'),
        findsOneWidget,
      );
      expect(
        text('Saving to Us opens in an upcoming version of Sirf Hum.'),
        findsOneWidget,
      );
      expect(text('Add the day you got together'), findsNothing);
      await scrollTo(tester, text('Sign out'));
      expect(text('Sign out'), findsOneWidget);
    });

    testWidgets('web: the shell and names only; private content fails '
        'closed', (tester) async {
      final backend = FakeNotebookBackend(List.of(full));
      await pumpUs(tester, backend: backend, privateContent: false);
      expect(text('Asha & Ravi'), findsOneWidget);
      expect(
        text('Us stays private to your phones. Open it in the Sirf Hum app.'),
        findsOneWidget,
      );
      for (final secret in ['How we started', 'Tum Hi Ho', 'Friday movie']) {
        expect(find.textContaining(secret), findsNothing);
      }
      expect(find.textContaining('Together since'), findsNothing);
      expect(backend.refreshes, 0);
    });

    testWidgets('empty: the product’s own words, and a way into each part', (
      tester,
    ) async {
      await pumpUs(tester);
      expect(text('This is your space.'), findsOneWidget);
      expect(text('Add the day you got together'), findsOneWidget);
      for (final add in [
        'Add to your story',
        'Add a little thing',
        'Add a ritual',
        'Add an important date',
      ]) {
        await scrollTo(tester, text(add));
        expect(text(add), findsOneWidget, reason: add);
      }
    });

    testWidgets('blocked: names stay, nothing private, sign out stays', (
      tester,
    ) async {
      final backend = FakeNotebookBackend(List.of(full))
        ..refreshError = const NotebookException(
          NotebookFailure.deviceNotTrusted,
        );
      await pumpUs(tester, backend: backend);
      expect(text('Asha & Ravi'), findsOneWidget);
      expect(text('Us isn’t available on this phone.'), findsOneWidget);
      expect(find.textContaining('Tum Hi Ho'), findsNothing);
      expect(find.textContaining('Together since'), findsNothing);
      await scrollTo(tester, text('Sign out'));
      expectNoSecretsOnScreen(tester);
    });
  });

  group('who you are', () {
    testWidgets('since, story, little things, rituals and dates — and no '
        'plans', (tester) async {
      await pumpUs(tester, backend: FakeNotebookBackend(List.of(full)));
      expect(
        text('Together since ${_day(MomentDate(2021, 3, 12))}'),
        findsOneWidget,
      );
      expect(text('This is your space.'), findsNothing);
      for (final t in [
        'How we started',
        'Tum Hi Ho',
        'Our song',
        'Friday movie',
        'Every Friday',
        'Anniversary',
      ]) {
        await scrollTo(tester, find.textContaining(t));
        expect(find.textContaining(t), findsWidgets, reason: t);
      }
      expect(text('Goa'), findsNothing);
      final strings = visibleStrings(tester).join('\n');
      expect(strings, isNot(contains('beef')), reason: 'a handle leaked');
      for (final word in ['score', 'streak', 'followers', 'likes']) {
        expect(strings.toLowerCase(), isNot(contains(word)));
      }
    });

    testWidgets('add a little thing: kind and name', (tester) async {
      final backend = FakeNotebookBackend();
      await pumpUs(tester, backend: backend);
      await tapScrolled(tester, text('Add a little thing'));
      expect(find.byType(NotebookEditorScreen), findsOneWidget);
      await tester.tap(find.widgetWithText(ChoiceChip, 'Our song'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, 'What is it?'),
        'Tum Hi Ho',
      );
      await tester.pump();
      await tester.tap(find.widgetWithText(TextButton, 'Save'));
      await tester.pumpAndSettle();
      final f = backend.created.single;
      expect(f.section, NotebookSection.littleThing);
      expect(f.category, LittleThingKind.ourSong.wireValue);
      expect(f.title, 'Tum Hi Ho');
      expect(text('Saved. It’s here for both of you.'), findsOneWidget);
      await scrollTo(tester, text('Tum Hi Ho'));
      expect(text('Our song'), findsOneWidget);
    });

    testWidgets('a story can start from a suggestion', (tester) async {
      final backend = FakeNotebookBackend();
      await pumpUs(tester, backend: backend);
      await tapScrolled(tester, text('Add to your story'));
      await tester.tap(find.widgetWithText(ActionChip, 'How we started'));
      await tester.pumpAndSettle();
      expect(find.byType(ActionChip), findsNothing, reason: 'name is set');
      await tester.enterText(
        find.widgetWithText(TextField, 'Tell it your way'),
        'A rainy Tuesday.',
      );
      await tester.pump();
      await tester.tap(find.widgetWithText(TextButton, 'Save'));
      await tester.pumpAndSettle();
      final f = backend.created.single;
      expect(f.section, NotebookSection.story);
      expect(f.title, 'How we started');
      expect(f.note, 'A rainy Tuesday.');
    });

    testWidgets('a ritual: name and how often, no schedule', (tester) async {
      final backend = FakeNotebookBackend();
      await pumpUs(tester, backend: backend);
      await tapScrolled(tester, text('Add a ritual'));
      await tester.enterText(
        find.widgetWithText(TextField, 'What do you do?'),
        'Sunday call',
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'How often? (optional)'),
        'Sundays',
      );
      await tester.pump();
      await tester.tap(find.widgetWithText(TextButton, 'Save'));
      await tester.pumpAndSettle();
      final f = backend.created.single;
      expect(f.section, NotebookSection.ritual);
      expect(f.detail, 'Sundays');
      expect(f.date, isNull);
    });

    testWidgets('together since: a day, required, then changeable', (
      tester,
    ) async {
      final backend = FakeNotebookBackend();
      await pumpUs(tester, backend: backend);
      await tester.tap(text('Add the day you got together'));
      await tester.pumpAndSettle();
      final save = find.widgetWithText(TextButton, 'Save');
      expect(tester.widget<TextButton>(save).onPressed, isNull);
      await tester.tap(text('Choose a date'));
      await tester.pumpAndSettle();
      await tester.tap(text('OK'));
      await tester.pumpAndSettle();
      expect(text('Remove date'), findsNothing, reason: 'it is required');
      await tester.tap(save);
      await tester.pumpAndSettle();
      final f = backend.created.single;
      expect(f.section, NotebookSection.togetherSince);
      expect(f.date, MomentDate.of(DateTime.now()));
      expect(find.textContaining('Together since'), findsOneWidget);
      expect(text('Change the day you got together'), findsOneWidget);
    });

    testWidgets('an important date added in Us is a Future important date', (
      tester,
    ) async {
      final backend = FakeNotebookBackend();
      await pumpUs(tester, backend: backend);
      await tapScrolled(tester, text('Add an important date'));
      expect(
        tester
            .widget<ChoiceChip>(
              find.widgetWithText(ChoiceChip, 'Important date'),
            )
            .selected,
        isTrue,
      );
      await tester.enterText(find.byType(TextField).first, 'Ravi’s birthday');
      await tester.pump();
      await tester.tap(find.widgetWithText(TextButton, 'Save'));
      await tester.pumpAndSettle();
      final f = backend.created.single;
      expect(f.section, NotebookSection.future);
      expect(f.category, FutureCategory.importantDate.wireValue);

      await tester.tap(find.byIcon(ProductArea.future.icon));
      await tester.pumpAndSettle();
      expect(text('Ravi’s birthday'), findsOneWidget);
    });

    testWidgets('a full part says so instead of offering more', (tester) async {
      await pumpUs(
        tester,
        backend: FakeNotebookBackend([
          for (
            var i = 0;
            i < NotebookService.limits[NotebookSection.ritual]!;
            i++
          )
            fakeEntry(i, _ritual('r$i')),
        ]),
      );
      await scrollTo(
        tester,
        text('That’s all the room there is here for now.'),
      );
      expect(text('Add a ritual'), findsNothing);
    });

    testWidgets('back from an editor returns to Us unchanged', (tester) async {
      final backend = FakeNotebookBackend(List.of(full));
      await pumpUs(tester, backend: backend);
      await tapScrolled(tester, text('Friday movie'));
      expect(find.byType(NotebookEditorScreen), findsOneWidget);
      // System back, as on Android.
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byType(NotebookEditorScreen), findsNothing);
      expect(backend.updated, isEmpty);
      expect(text('Friday movie'), findsOneWidget);
    });
  });

  group('account switching', () {
    testWidgets('sign out from Us leaves nothing of the couple on screen', (
      tester,
    ) async {
      final session = FakeAccountSession(alice);
      setPhoneWindow(tester);
      await pumpSirfHum(
        tester,
        session: session,
        initialLocation: ProductArea.us.path,
        extra: [
          notebookBackendProvider.overrideWithValue(
            FakeNotebookBackend(List.of(full)),
          ),
        ],
      );
      expect(text('Asha & Ravi'), findsOneWidget);
      await tapScrolled(tester, text('Sign out'));
      await tester.tap(find.widgetWithText(TextButton, 'Sign out'));
      await tester.pumpAndSettle();
      expect(session.signOuts, 1);
      expect(text('Your private space for two.'), findsOneWidget);
      for (final t in ['Asha', 'Tum Hi Ho', 'Friday movie', 'Together since']) {
        expect(find.textContaining(t), findsNothing, reason: t);
      }
    });
  });

  group('accessibility and layout', () {
    for (final brightness in Brightness.values) {
      for (final (name, entries) in [('empty', <Never>[]), ('full', full)]) {
        testWidgets('$name meets guidelines in ${brightness.name}', (
          tester,
        ) async {
          tester.platformDispatcher.platformBrightnessTestValue = brightness;
          addTearDown(
            tester.platformDispatcher.clearPlatformBrightnessTestValue,
          );
          final handle = tester.ensureSemantics();
          await pumpUs(tester, backend: FakeNotebookBackend(List.of(entries)));
          await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
          await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
          await expectLater(tester, meetsGuideline(textContrastGuideline));
          handle.dispose();
        });
      }
    }

    for (final size in [
      const Size(320, 640),
      const Size(360, 740),
      const Size(430, 932),
      const Size(820, 1180),
      const Size(1440, 900),
    ]) {
      testWidgets('survives 200% text at $size', (tester) async {
        tester.platformDispatcher.textScaleFactorTestValue = 2;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        await pumpUs(
          tester,
          backend: FakeNotebookBackend(List.of(full)),
          size: size,
        );
        expect(tester.takeException(), isNull);
        await scrollTo(tester, text('Sign out'));
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('the editor for each part meets guidelines', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpUs(tester);
      for (final add in [
        'Add the day you got together',
        'Add to your story',
        'Add a little thing',
        'Add a ritual',
      ]) {
        await tapScrolled(tester, text(add));
        await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
        await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
        await expectLater(tester, meetsGuideline(textContrastGuideline));
        await tester.tap(find.byTooltip('Close'));
        await tester.pumpAndSettle();
      }
      handle.dispose();
    });
  });
}
