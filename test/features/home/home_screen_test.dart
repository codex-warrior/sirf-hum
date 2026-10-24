import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sirf_hum/app/product_area.dart';
import 'package:sirf_hum/design_system/design_system.dart';
import 'package:sirf_hum/features/home/presentation/home_screen.dart';
import 'package:sirf_hum/features/notebook/application/notebook_controller.dart';
import 'package:sirf_hum/security/couple/couple_profiles.dart';
import 'package:sirf_hum/security/couple/pairing.dart';
import 'package:sirf_hum/security/moments/moment_payload.dart';
import 'package:sirf_hum/security/notebook/notebook_payload.dart';
import 'package:sirf_hum/session/session_controller.dart';

import '../../support/notebook_fakes.dart';
import '../../support/session_fakes.dart';

void main() {
  int selectedIndex(WidgetTester tester) =>
      tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex;

  testWidgets('paired Home: greeting, couple, one primary action', (
    tester,
  ) async {
    setPhoneWindow(tester);
    await pumpSirfHum(tester);

    expect(find.text('Good evening,'), findsOneWidget);
    expect(find.text('Asha & Ravi.'), findsOneWidget);
    for (final label in ['Watch', 'Listen', 'Call', 'Play']) {
      expect(find.text(label), findsOneWidget);
    }
    await tester.scrollUntilVisible(find.text('+ Plan'), 100);
    expect(
      find.byType(FilledButton),
      findsOneWidget,
      reason: 'one primary action per screen',
    );
  });

  testWidgets('without profiles the couple still reads naturally', (
    tester,
  ) async {
    setPhoneWindow(tester);
    await pumpSirfHum(tester, profiles: FakeCoupleProfiles());
    expect(find.text('Just the two of you.'), findsOneWidget);
  });

  testWidgets('empty states are deliberate and human', (tester) async {
    setPhoneWindow(tester);
    await pumpSirfHum(tester);

    expect(find.text('Your first memory is waiting.'), findsOneWidget);
    expect(find.text('Add your day'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('No plans yet.'), 100);
    expect(find.text('No plans yet.'), findsOneWidget);
    for (final generic in ['No data', 'No items', 'Lorem', 'TODO']) {
      expect(find.textContaining(generic), findsNothing);
    }
  });

  testWidgets('the soonest plan ahead is what is coming up; a passed or '
      'undated plan is not', (tester) async {
    setPhoneWindow(tester);
    final backend = FakeNotebookBackend([
      fakeEntry(1, plan('Someday trip')),
      fakeEntry(2, plan('Last spring', date: MomentDate(2026, 4, 1))),
      fakeEntry(3, plan('Udaipur', date: MomentDate(2026, 12, 28))),
      fakeEntry(4, plan('Dinner', date: MomentDate(2026, 10, 25))),
    ]);
    await pumpSirfHum(
      tester,
      extra: [notebookBackendProvider.overrideWithValue(backend)],
    );
    await tester.scrollUntilVisible(find.text('Dinner'), 100);
    expect(
      find.text(
        const DefaultMaterialLocalizations().formatMediumDate(
          DateTime(2026, 10, 25),
        ),
      ),
      findsOneWidget,
    );
    for (final other in ['Udaipur', 'Someday trip', 'Last spring']) {
      expect(find.text(other), findsNothing, reason: other);
    }
    expect(find.text('No plans yet.'), findsNothing);
  });

  testWidgets('days together come from the date in Us, never invented', (
    tester,
  ) async {
    setPhoneWindow(tester);
    final backend = FakeNotebookBackend([
      fakeEntry(
        1,
        NotebookFields(
          section: NotebookSection.togetherSince,
          category: 0,
          status: 0,
          title: '',
          date: MomentDate(2025, 10, 19),
        ),
      ),
    ]);
    await pumpSirfHum(
      tester,
      extra: [notebookBackendProvider.overrideWithValue(backend)],
    );
    expect(find.text('Together for'), findsOneWidget);
    expect(find.text('365 days'), findsOneWidget);
  });

  testWidgets('Home leads to Together, Moments, Future and Us', (tester) async {
    setPhoneWindow(tester);
    final entries = {
      'Watch': ProductArea.together,
      'Your Moments': ProductArea.moments,
      'View all': ProductArea.future,
      'Our Space': ProductArea.us,
    };
    for (final MapEntry(key: label, value: area) in entries.entries) {
      await tester.pumpWidget(const SizedBox());
      await pumpSirfHum(tester);
      await tester.scrollUntilVisible(find.text(label), 100);
      await tester.ensureVisible(find.text(label));
      await tester.pumpAndSettle();
      await tester.tap(find.text(label));
      await tester.pumpAndSettle();
      expect(selectedIndex(tester), area.index, reason: label);
    }
  });

  testWidgets('loading: a Home-shaped skeleton, not a spinner', (tester) async {
    setPhoneWindow(tester);
    final handle = tester.ensureSemantics();
    final answer = Completer<PairingState>();
    await pumpSirfHum(
      tester,
      backend: FakePairingBackend(() => answer.future),
      settle: false,
    );
    await tester.pump();

    expect(find.byType(HomeSkeleton), findsOneWidget);
    expect(find.bySemanticsLabel('Opening Sirf Hum'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.byType(NavigationBar), findsNothing);

    answer.complete(paired);
    await tester.pumpAndSettle();
    expect(find.text('Asha & Ravi.'), findsOneWidget);
    handle.dispose();
  });

  testWidgets('the skeleton holds still with reduced motion', (tester) async {
    setPhoneWindow(tester);
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    await pumpSirfHum(
      tester,
      backend: FakePairingBackend(() => Completer<PairingState>().future),
      settle: false,
    );
    // Would time out if the pulse kept animating.
    await tester.pumpAndSettle();
    expect(find.byType(Skeleton), findsOneWidget);
  });

  testWidgets('error: human copy and retry, never internals', (tester) async {
    setPhoneWindow(tester);
    await pumpSirfHum(
      tester,
      backend: FakePairingBackend.failing(PairingFailure.unavailable),
    );
    expect(find.text('We couldn’t reach Sirf Hum.'), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
    expectNoSecretsOnScreen(tester);
  });

  testWidgets('a failed refresh keeps Home on screen', (tester) async {
    setPhoneWindow(tester);
    var fail = false;
    final backend = FakePairingBackend(
      () async => fail
          ? throw const PairingException(PairingFailure.unavailable)
          : paired,
    );
    await pumpSirfHum(tester, backend: backend);
    fail = true;
    final container = ProviderScope.containerOf(
      tester.element(find.byType(HomeScreen)),
    );
    await container.read(sessionProvider.notifier).refresh();
    await tester.pumpAndSettle();
    expect(find.text('Asha & Ravi.'), findsOneWidget);
  });

  testWidgets('no private data or internal IDs on Home or Us', (tester) async {
    setPhoneWindow(tester);
    final handle = tester.ensureSemantics();
    await pumpSirfHum(tester);
    expectNoSecretsOnScreen(tester);

    await tester.tap(find.byIcon(ProductArea.us.icon));
    await tester.pumpAndSettle();
    expect(find.text('Asha & Ravi'), findsOneWidget);
    expectNoSecretsOnScreen(tester);
    handle.dispose();
  });

  testWidgets('a hostile display name is not rendered', (tester) async {
    setPhoneWindow(tester);
    await pumpSirfHum(
      tester,
      profiles: FakeCoupleProfiles(
        CoupleNames(
          yours: CoupleNames.sanitize('Asha'),
          partner: CoupleNames.sanitize('Ravi\u0000<script>'),
        ),
      ),
    );
    expect(find.text('Asha & your person.'), findsOneWidget);
  });

  testWidgets('web: Home says where private content lives', (tester) async {
    setPhoneWindow(tester);
    await pumpSirfHum(tester, privateContent: false);
    await tester.scrollUntilVisible(
      find.textContaining('app on your phone'),
      100,
    );
    expect(find.textContaining('app on your phone'), findsOneWidget);
  });

  testWidgets('mobile: no web notice', (tester) async {
    setPhoneWindow(tester);
    await pumpSirfHum(tester);
    expect(find.textContaining('app on your phone'), findsNothing);
  });
}
