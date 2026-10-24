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

      expect(find.text('Your private space for two.'), findsOneWidget);
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
    testWidgets('sets the phone up, then offers invite or join', (
      tester,
    ) async {
      setPhoneWindow(tester);
      final handle = tester.ensureSemantics();
      await pumpSirfHum(
        tester,
        backend: FakePairingBackend.returning(const PairingNone()),
      );

      expect(find.text('Bring your person in.'), findsOneWidget);
      expect(find.text('Invite your person'), findsOneWidget);
      expect(find.text('I have an invite'), findsOneWidget);
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
      expect(find.text('Invite your person'), findsNothing);
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
      expect(find.text('Your private space for two.'), findsOneWidget);
    });
  });

  group('pairing in progress, as the server reports it', () {
    testWidgets('invitation out: waiting, no IDs', (tester) async {
      setPhoneWindow(tester);
      reduceMotion(tester);
      final handle = tester.ensureSemantics();
      await pumpSirfHum(tester, backend: FakePairingBackend.returning(invited));
      // Restarted: this phone no longer holds the token to share.
      expect(find.text('Your invite is out.'), findsOneWidget);
      expect(find.text('Share invite'), findsNothing);
      expect(find.text('Cancel invite'), findsOneWidget);
      expectNoSecretsOnScreen(tester);
      handle.dispose();
    });

    testWidgets('inviter: asks for the code, never shows it', (tester) async {
      setPhoneWindow(tester);
      await pumpSirfHum(
        tester,
        backend: FakePairingBackend.returning(awaiting(isInviter: true)),
      );
      expect(find.text('Ravi joined.'), findsOneWidget);
      expect(find.text('Six-digit code'), findsOneWidget);
      expectNoSecretsOnScreen(tester);
    });

    testWidgets('invitee: shows the code to read out', (tester) async {
      setPhoneWindow(tester);
      reduceMotion(tester);
      await pumpSirfHum(
        tester,
        backend: FakePairingBackend.returning(awaiting(isInviter: false)),
      );
      expect(find.text('Read this code to Ravi.'), findsOneWidget);
      expect(find.text('482 913'), findsOneWidget);
      expect(find.textContaining(testPairingId), findsNothing);
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
      expect(find.text('Asha & Ravi.'), findsOneWidget);
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
      expect(find.text('Your private space for two.'), findsOneWidget);
    });

    testWidgets('Firebase failed to start: honest copy, no dead button', (
      tester,
    ) async {
      setPhoneWindow(tester);
      await pumpSirfHum(tester, session: const UnavailableAccountSession());
      expect(find.text('Sirf Hum couldn’t start.'), findsOneWidget);
      expect(find.byType(FilledButton), findsNothing);
      expect(find.byType(NavigationBar), findsNothing);
      expect(find.text('Your private space for two.'), findsNothing);
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
