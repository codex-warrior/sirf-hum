import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sirf_hum/app/product_area.dart';
import 'package:sirf_hum/features/future/application/future_providers.dart';
import 'package:sirf_hum/features/notebook/application/notebook_controller.dart';
import 'package:sirf_hum/features/notebook/presentation/notebook_editor_screen.dart';
import 'package:sirf_hum/security/couple/couple_profiles.dart';
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

/// "Mar 12, 2021", as the story card says it.
String _sinceDay(MomentDate d) =>
    '${const DefaultMaterialLocalizations().formatShortMonthDay(d.toLocal())}'
    ', ${d.year}';

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

  Future<void> scrollTo(WidgetTester tester, Finder finder) =>
      tester.scrollUntilVisible(
        finder,
        200,
        scrollable: find.byType(Scrollable).last,
      );

  Future<void> tapScrolled(WidgetTester tester, Finder finder) async {
    await scrollTo(tester, finder);
    await tester.pumpAndSettle();
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  /// Opens one part of About Us (Our Story, Little Things, Our Rituals).
  Future<void> openPart(WidgetTester tester, String title) =>
      tapScrolled(tester, find.text(title));

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
    fakeEntry(6, plan('Goa')), // a plan: Future only, not Us
  ];

  group('entry states', () {
    testWidgets('production today: names, an honest notice, sign out', (
      tester,
    ) async {
      await pumpUs(tester, noBackend: true);
      expect(text('Asha & Ravi'), findsOneWidget);
      await scrollTo(tester, text('This is your space.'));
      expect(
        text('Saving to Us opens in an upcoming version of Sirf Hum.'),
        findsOneWidget,
      );
      expect(text('Add the day you got together'), findsNothing);
      await tapScrolled(tester, text('Settings'));
      expect(text('Sign out'), findsOneWidget);
    });

    testWidgets('web: the shell and names only; private content fails '
        'closed', (tester) async {
      final backend = FakeNotebookBackend(List.of(full));
      await pumpUs(tester, backend: backend, privateContent: false);
      expect(text('Asha & Ravi'), findsOneWidget);
      await scrollTo(
        tester,
        text('Us stays private to your phones. Open it in the Sirf Hum app.'),
      );
      for (final secret in ['How we started', 'Tum Hi Ho', 'Friday movie']) {
        expect(find.textContaining(secret), findsNothing);
      }
      expect(find.textContaining('Together since'), findsNothing);
      expect(backend.refreshes, 0);
    });

    testWidgets('empty: the story card invites the day, and each part has '
        'a way in', (tester) async {
      await pumpUs(tester);
      expect(text('Add the day you got together'), findsOneWidget);
      for (final (part, add) in [
        ('Our Story', 'Add to your story'),
        ('Little Things', 'Add a little thing'),
        ('Our Rituals', 'Add a ritual'),
      ]) {
        await openPart(tester, part);
        expect(text(add), findsOneWidget, reason: add);
        await tester.pageBack();
        await tester.pumpAndSettle();
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
      await scrollTo(tester, text('Set up this phone to open Us.'));
      expect(find.textContaining('Tum Hi Ho'), findsNothing);
      expect(find.textContaining('Together since'), findsNothing);
      await tapScrolled(tester, text('Settings'));
      expect(text('Sign out'), findsOneWidget);
      expectNoSecretsOnScreen(tester);
    });
  });

  group('who you are', () {
    testWidgets('days together come from the saved day, never invented', (
      tester,
    ) async {
      await pumpUs(tester, backend: FakeNotebookBackend(List.of(full)));
      expect(
        text('Together since ${_sinceDay(MomentDate(2021, 3, 12))}'),
        findsOneWidget,
      );
      // Home's clock in tests: 2026-10-19.
      final days = DateTime.utc(
        2026,
        10,
        19,
      ).difference(DateTime.utc(2021, 3, 12)).inDays;
      expect(
        text(const DefaultMaterialLocalizations().formatDecimal(days)),
        findsOneWidget,
      );
    });

    testWidgets('story, little things and rituals each on their page — and '
        'no plans', (tester) async {
      await pumpUs(tester, backend: FakeNotebookBackend(List.of(full)));
      for (final (part, shown) in [
        ('Our Story', ['How we started', 'A rainy Tuesday.']),
        ('Little Things', ['Tum Hi Ho', 'Our song']),
        ('Our Rituals', ['Friday movie', 'Every Friday']),
      ]) {
        await openPart(tester, part);
        for (final t in shown) {
          expect(find.textContaining(t), findsWidgets, reason: t);
        }
        expect(text('Goa'), findsNothing);
        final strings = visibleStrings(tester).join('\n');
        expect(strings, isNot(contains('beef')), reason: 'a handle leaked');
        for (final word in ['score', 'streak', 'followers', 'likes']) {
          expect(strings.toLowerCase(), isNot(contains(word)));
        }
        await tester.pageBack();
        await tester.pumpAndSettle();
      }
    });

    testWidgets('add a little thing: kind and name', (tester) async {
      final backend = FakeNotebookBackend();
      await pumpUs(tester, backend: backend);
      await openPart(tester, 'Little Things');
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
      expect(text('Tum Hi Ho'), findsOneWidget);
      expect(text('Our song'), findsOneWidget);
    });

    testWidgets('a story can start from a suggestion', (tester) async {
      final backend = FakeNotebookBackend();
      await pumpUs(tester, backend: backend);
      await openPart(tester, 'Our Story');
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
      await openPart(tester, 'Our Rituals');
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

    testWidgets('together since: a day, required, then shown', (tester) async {
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
      await openPart(tester, 'Our Rituals');
      await scrollTo(
        tester,
        text('That’s all the room there is here for now.'),
      );
      expect(text('Add a ritual'), findsNothing);
    });

    testWidgets('back from an editor returns unchanged', (tester) async {
      final backend = FakeNotebookBackend(List.of(full));
      await pumpUs(tester, backend: backend);
      await openPart(tester, 'Our Rituals');
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

  group('cards', () {
    testWidgets('profile shows the names; devices says it is coming', (
      tester,
    ) async {
      await pumpUs(tester);
      await tapScrolled(tester, text('Our Profile'));
      expect(text('Asha'), findsOneWidget);
      expect(text('Ravi'), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tapScrolled(tester, text('Devices'));
      expect(text('Managing your devices is coming soon.'), findsOneWidget);
    });

    testWidgets('safety never claims more than the safety number says', (
      tester,
    ) async {
      await pumpUs(tester);
      final strings = visibleStrings(tester).join('\n').toLowerCase();
      for (final claim in ['always safe', 'encrypted', 'secure']) {
        expect(strings, isNot(contains(claim)), reason: claim);
      }
      expect(text('Privacy & Safety'), findsOneWidget);
    });
  });

  group('your name', () {
    Future<FakeCoupleProfiles> pumpNamed(
      WidgetTester tester,
      CoupleNames names,
    ) async {
      final profiles = FakeCoupleProfiles(names);
      setPhoneWindow(tester);
      await pumpSirfHum(
        tester,
        profiles: profiles,
        initialLocation: ProductArea.us.path,
        extra: [
          notebookBackendProvider.overrideWithValue(FakeNotebookBackend()),
        ],
      );
      return profiles;
    }

    testWidgets('added from Our Profile, then shown everywhere', (
      tester,
    ) async {
      final profiles = await pumpNamed(
        tester,
        const CoupleNames(partner: 'Ravi'),
      );
      await tapScrolled(tester, text('Our Profile'));
      await tester.tap(find.widgetWithText(TextButton, 'Add your name'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '  Asha ');
      await tester.tap(find.widgetWithText(TextButton, 'Save'));
      await tester.pumpAndSettle();
      expect(profiles.saved, ['Asha']);
      expect(text('Saved. Your person will see it too.'), findsOneWidget);
      expect(text('Asha'), findsOneWidget);
      expect(text('Asha & Ravi'), findsOneWidget);
    });

    testWidgets('an empty name is refused before saving; a failed save says '
        'so and keeps the dialog', (tester) async {
      final profiles = await pumpNamed(tester, CoupleNames.unknown);
      await tapScrolled(tester, text('Our Profile'));
      await tester.tap(find.widgetWithText(TextButton, 'Add your name'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '   ');
      await tester.tap(find.widgetWithText(TextButton, 'Save'));
      await tester.pumpAndSettle();
      expect(text('Write a name, up to 40 letters.'), findsOneWidget);
      expect(profiles.saved, isEmpty);

      profiles.saveError = const CoupleProfileException(
        CoupleProfileFailure.unavailable,
      );
      await tester.enterText(find.byType(TextField), 'Asha');
      await tester.tap(find.widgetWithText(TextButton, 'Save'));
      await tester.pumpAndSettle();
      expect(
        text('That didn’t save. Check your connection and try again.'),
        findsOneWidget,
      );
      expect(find.byType(AlertDialog), findsOneWidget);
    });

    testWidgets('Home asks for your name only while it is missing', (
      tester,
    ) async {
      setPhoneWindow(tester);
      await pumpSirfHum(tester, profiles: FakeCoupleProfiles());
      expect(text('Add your name'), findsOneWidget);
      await tester.tap(text('Add your name'));
      await tester.pumpAndSettle();
      expect(text('The little things about the two of you.'), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
      await pumpSirfHum(tester);
      expect(text('Add your name'), findsNothing);
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
      await scrollTo(tester, text('Asha & Ravi'));
      await tapScrolled(tester, text('Settings'));
      await tester.tap(find.widgetWithText(OutlinedButton, 'Sign out'));
      await tester.pumpAndSettle();
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
        await scrollTo(tester, text('Our Rituals'));
        expect(tester.takeException(), isNull);
        await openPart(tester, 'Our Story');
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('the editor for each part meets guidelines', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpUs(tester);
      await tester.tap(text('Add the day you got together'));
      await tester.pumpAndSettle();
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      await expectLater(tester, meetsGuideline(textContrastGuideline));
      await tester.tap(find.byTooltip('Close'));
      await tester.pumpAndSettle();
      for (final (part, add) in [
        ('Our Story', 'Add to your story'),
        ('Little Things', 'Add a little thing'),
        ('Our Rituals', 'Add a ritual'),
      ]) {
        await openPart(tester, part);
        await tapScrolled(tester, text(add));
        await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
        await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
        await expectLater(tester, meetsGuideline(textContrastGuideline));
        await tester.tap(find.byTooltip('Close'));
        await tester.pumpAndSettle();
        await tester.pageBack();
        await tester.pumpAndSettle();
      }
      handle.dispose();
    });
  });
}
