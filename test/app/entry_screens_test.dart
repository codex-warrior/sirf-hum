import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sirf_hum/security/account/account_session.dart';
import 'package:sirf_hum/security/couple/pairing.dart';

import '../support/session_fakes.dart';

void main() {
  Future<void> expectGuidelines(WidgetTester tester) async {
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    await expectLater(tester, meetsGuideline(textContrastGuideline));
  }

  group('signed out', () {
    testWidgets('shows the welcome, not Home', (tester) async {
      setPhoneWindow(tester);
      final handle = tester.ensureSemantics();
      final backend = FakePairingBackend.returning(paired);
      await pumpSirfHum(
        tester,
        session: FakeAccountSession(),
        backend: backend,
      );

      expect(find.text('A private home for the two of you.'), findsOneWidget);
      expect(
        find.text('Signing in opens in an upcoming version of Sirf Hum.'),
        findsOneWidget,
      );
      expect(find.byType(NavigationBar), findsNothing);
      expect(backend.stateCalls, 0);
      await expectGuidelines(tester);
      handle.dispose();
    });
  });

  group('signed in, not paired', () {
    testWidgets('guides toward pairing on a phone', (tester) async {
      setPhoneWindow(tester);
      final handle = tester.ensureSemantics();
      await pumpSirfHum(
        tester,
        backend: FakePairingBackend.returning(const PairingNone()),
      );

      expect(find.text('Invite your person.'), findsOneWidget);
      expect(find.text('Send your person an invitation.'), findsOneWidget);
      expect(
        find.text('Pairing opens in an upcoming version of Sirf Hum.'),
        findsOneWidget,
      );
      expect(find.byType(NavigationBar), findsNothing);
      await expectGuidelines(tester);
      expectNoSecretsOnScreen(tester);
      handle.dispose();
    });

    testWidgets('on web, points to the phone app', (tester) async {
      setPhoneWindow(tester);
      await pumpSirfHum(
        tester,
        backend: FakePairingBackend.returning(const PairingNone()),
        privateContent: false,
      );
      expect(find.textContaining('app on your phone'), findsOneWidget);
    });

    testWidgets('"Check again" only asks the server', (tester) async {
      setPhoneWindow(tester);
      PairingState answer = const PairingNone();
      final backend = FakePairingBackend(() async => answer);
      await pumpSirfHum(tester, backend: backend);

      // Still not paired: stays on the pairing screen.
      await tester.tap(find.text('Check again'));
      await tester.pumpAndSettle();
      expect(backend.stateCalls, 2);
      expect(find.text('Invite your person.'), findsOneWidget);

      // The server now reports a couple: Home opens.
      answer = paired;
      await tester.tap(find.text('Check again'));
      await tester.pumpAndSettle();
      expect(find.byType(NavigationBar), findsOneWidget);
      expect(find.text('Asha & Ravi'), findsOneWidget);
    });

    testWidgets('sign out returns to the welcome', (tester) async {
      setPhoneWindow(tester);
      final session = FakeAccountSession(alice);
      await pumpSirfHum(
        tester,
        session: session,
        backend: FakePairingBackend.returning(const PairingNone()),
      );
      await tester.tap(find.text('Sign out'));
      await tester.pumpAndSettle();
      expect(session.signOuts, 1);
      expect(find.text('A private home for the two of you.'), findsOneWidget);
    });
  });

  group('pairing in progress', () {
    final stages = <String, (PairingState, String)>{
      'invitation sent': (invited, 'Your invitation is out.'),
      'partner accepted': (awaiting(isInviter: true), 'Your person accepted.'),
      'waiting for partner': (awaiting(isInviter: false), 'Almost there.'),
    };
    stages.forEach((name, testCase) {
      testWidgets('$name: human copy, no codes or IDs', (tester) async {
        setPhoneWindow(tester);
        final handle = tester.ensureSemantics();
        await pumpSirfHum(
          tester,
          backend: FakePairingBackend.returning(testCase.$1),
        );
        expect(find.text(testCase.$2), findsOneWidget);
        expect(find.byType(NavigationBar), findsNothing);
        // The comparison code and partner name belong to the pairing UI's
        // code-comparison step, not to this status screen.
        expectNoSecretsOnScreen(tester);
        expect(find.textContaining('Ravi'), findsNothing);
        handle.dispose();
      });
    });
  });

  group('cannot establish the session', () {
    testWidgets('unreachable: human error, retry recovers', (tester) async {
      setPhoneWindow(tester);
      final handle = tester.ensureSemantics();
      var fail = true;
      final backend = FakePairingBackend(
        () async => fail
            ? throw const PairingException(PairingFailure.unavailable)
            : paired,
      );
      await pumpSirfHum(tester, backend: backend);

      expect(find.text('We couldn’t reach Sirf Hum.'), findsOneWidget);
      expect(find.byType(NavigationBar), findsNothing);
      expectNoSecretsOnScreen(tester);
      expect(find.textContaining('unavailable'), findsNothing);
      await expectGuidelines(tester);

      fail = false;
      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();
      expect(find.text('Asha & Ravi'), findsOneWidget);
      handle.dispose();
    });

    testWidgets('rejected sign-in: asks to sign in again', (tester) async {
      setPhoneWindow(tester);
      final session = FakeAccountSession(alice);
      await pumpSirfHum(
        tester,
        session: session,
        backend: FakePairingBackend.failing(PairingFailure.unauthenticated),
      );
      expect(find.text('Please sign in again.'), findsOneWidget);
      expectNoSecretsOnScreen(tester);

      await tester.tap(find.text('Sign out'));
      await tester.pumpAndSettle();
      expect(session.signOuts, 1);
      expect(find.text('A private home for the two of you.'), findsOneWidget);
    });

    testWidgets('Firebase failed to start: honest copy, no dead button', (
      tester,
    ) async {
      setPhoneWindow(tester);
      await pumpSirfHum(tester, session: const UnavailableAccountSession());
      expect(find.text('Sirf Hum couldn’t start.'), findsOneWidget);
      expect(find.byType(FilledButton), findsNothing);
      expect(find.byType(NavigationBar), findsNothing);
      expect(find.text('A private home for the two of you.'), findsNothing);
      expectNoSecretsOnScreen(tester);
    });

    testWidgets('a forged server answer never opens Home', (tester) async {
      setPhoneWindow(tester);
      await pumpSirfHum(
        tester,
        backend: FakePairingBackend(
          () async => PairingState.parse({'state': 'paired', 'coupleId': 1}),
        ),
      );
      expect(find.byType(NavigationBar), findsNothing);
      expect(find.text('We couldn’t reach Sirf Hum.'), findsOneWidget);
    });
  });
}
