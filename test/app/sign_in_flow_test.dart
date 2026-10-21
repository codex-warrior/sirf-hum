import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:sirf_hum/app/product_area.dart';
import 'package:sirf_hum/app/router.dart';
import 'package:sirf_hum/core/config/app_environment.dart';
import 'package:sirf_hum/security/couple/couple_profiles.dart';
import 'package:sirf_hum/security/couple/pairing.dart';
import 'package:sirf_hum/session/session_state.dart';
import 'package:sirf_hum/session/sign_in_controller.dart';

import '../session/sign_in_controller_test.dart' show FakeEmailLinkSignIn;
import '../support/session_fakes.dart';

const _domain = 'sirf-hum-staging.firebaseapp.com';
const _action =
    'https://$_domain/__/auth/action?apiKey=k&mode=signIn&oobCode=abc&continueUrl=x';
final _routed = Uri(
  path: '/__/auth/links',
  queryParameters: {'link': _action},
).toString();

void main() {
  group('redirect: sign-in links (D-138)', () {
    String? go(SessionState s) => redirectFor(s, Uri.parse(_routed));

    test('kept while signed out or starting (cold start from the email)', () {
      expect(go(const SessionSignedOut()), isNull);
      expect(go(const SessionStarting()), isNull);
    });

    test(
      'ignored once signed in: couple screens still need a paired session',
      () {
        expect(go(const SessionNotPaired(canPairHere: true)), EntryRoutes.pair);
        expect(
          go(const SessionPaired(names: CoupleNames.unknown)),
          ProductArea.home.path,
        );
        expect(
          go(const SessionUnavailable(SessionProblem.unreachable)),
          EntryRoutes.start,
        );
      },
    );

    test('a look-alike path is not a sign-in link', () {
      expect(
        redirectFor(const SessionSignedOut(), Uri.parse('/__/other')),
        EntryRoutes.welcome,
      );
    });
  });

  test('each environment returns links only to its own Android app', () {
    expect(
      AppEnvironment.development.androidApplicationId,
      'com.sirfhum.app.dev',
    );
    expect(
      AppEnvironment.staging.androidApplicationId,
      'com.sirfhum.app.staging',
    );
    expect(AppEnvironment.production.androidApplicationId, 'com.sirfhum.app');
  });

  group('welcome screen', () {
    testWidgets('sends a link, then signs in from the App Link', (
      tester,
    ) async {
      setPhoneWindow(tester);
      final signIn = FakeEmailLinkSignIn();
      final session = FakeAccountSession();
      await pumpSirfHum(
        tester,
        session: session,
        backend: FakePairingBackend.returning(const PairingNone()),
        extra: [
          emailLinkSignInProvider.overrideWithValue(signIn),
          authLinkDomainProvider.overrideWithValue(_domain),
        ],
      );

      await tester.tap(find.text('Continue with Email'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'a@example.com');
      await tester.tap(find.text('Send link'));
      await tester.pumpAndSettle();
      expect(signIn.sent, ['a@example.com']);
      expect(find.textContaining('Check your email'), findsOneWidget);
      // The address is never echoed back on screen.
      expect(find.textContaining('a@example.com'), findsNothing);

      final router = tester
          .widget<MaterialApp>(find.byType(MaterialApp))
          .routerConfig!;
      (router as GoRouter).go(_routed);
      await tester.pumpAndSettle();
      expect(signIn.completed, [('a@example.com', _action)]);
    });

    testWidgets('a bad address shows a category, not a request', (
      tester,
    ) async {
      setPhoneWindow(tester);
      final signIn = FakeEmailLinkSignIn();
      await pumpSirfHum(
        tester,
        session: FakeAccountSession(),
        extra: [
          emailLinkSignInProvider.overrideWithValue(signIn),
          authLinkDomainProvider.overrideWithValue(_domain),
        ],
      );
      await tester.tap(find.text('Continue with Email'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'nope');
      await tester.tap(find.text('Send link'));
      await tester.pumpAndSettle();
      expect(signIn.sent, isEmpty);
      expect(
        find.text('That doesn’t look like an email address.'),
        findsOneWidget,
      );
    });

    testWidgets('without sign-in (no Firebase, web) it says so plainly', (
      tester,
    ) async {
      setPhoneWindow(tester);
      await pumpSirfHum(tester, session: FakeAccountSession());
      expect(find.byType(TextField), findsNothing);
      expect(
        find.text('Signing in opens in an upcoming version of Sirf Hum.'),
        findsOneWidget,
      );
    });
  });
}
