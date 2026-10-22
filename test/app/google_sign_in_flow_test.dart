import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:sirf_hum/app/router.dart';
import 'package:sirf_hum/security/account/google_account_sign_in.dart';
import 'package:sirf_hum/security/account/sign_in_result.dart';
import 'package:sirf_hum/security/couple/pairing.dart';
import 'package:sirf_hum/session/session_controller.dart';
import 'package:sirf_hum/session/session_state.dart';
import 'package:sirf_hum/session/sign_in_controller.dart';

import '../session/sign_in_controller_test.dart' show FakeEmailLinkSignIn;
import '../support/session_fakes.dart';

const _domain = 'sirf-hum-staging.firebaseapp.com';

/// Google as Firebase behaves: a successful sign-in makes the account
/// session emit the account; nothing else changes.
class _GoogleThatSignsIn implements GoogleAccountSignIn {
  _GoogleThatSignsIn(this.session, {this.failure});

  final FakeAccountSession session;
  final GoogleAccountFailure? failure;
  int forgets = 0;

  @override
  Future<SignInResult> signIn() async {
    if (failure case final f?) throw GoogleAccountException(f);
    session.emit(alice);
    return const SignInResult(isNewAccount: true);
  }

  @override
  Future<void> forget() async => forgets++;
}

String _location(WidgetTester tester) {
  final router =
      tester.widget<MaterialApp>(find.byType(MaterialApp)).routerConfig!
          as GoRouter;
  return router.routerDelegate.currentConfiguration.uri.path;
}

void main() {
  Future<_GoogleThatSignsIn> pumpWelcome(
    WidgetTester tester, {
    PairingBackend? backend,
    GoogleAccountFailure? failure,
    bool offerGoogle = true,
  }) async {
    setPhoneWindow(tester);
    final session = FakeAccountSession();
    final google = _GoogleThatSignsIn(session, failure: failure);
    await pumpSirfHum(
      tester,
      session: session,
      backend: backend ?? FakePairingBackend.returning(const PairingNone()),
      extra: [
        emailLinkSignInProvider.overrideWithValue(FakeEmailLinkSignIn()),
        authLinkDomainProvider.overrideWithValue(_domain),
        if (offerGoogle) googleSignInProvider.overrideWithValue(google),
      ],
    );
    return google;
  }

  group('welcome (D-150)', () {
    testWidgets('Google first, email second, no sign-up/sign-in choice', (
      tester,
    ) async {
      await pumpWelcome(tester);
      expect(find.text('Sirf Hum'), findsOneWidget);
      expect(find.text('Your private space for two.'), findsOneWidget);
      final google = find.widgetWithText(FilledButton, 'Continue with Google');
      final email = find.widgetWithText(OutlinedButton, 'Continue with Email');
      expect(google, findsOneWidget);
      expect(email, findsOneWidget);
      expect(
        tester.getTopLeft(google).dy,
        lessThan(tester.getTopLeft(email).dy),
      );
      expect(find.text('or'), findsOneWidget);
      expect(
        find.text('By continuing, you agree to our Terms and Privacy Policy.'),
        findsOneWidget,
      );
      for (final word in ['Sign up', 'Create account', 'Password']) {
        expect(find.textContaining(word), findsNothing);
      }
      // Touch targets stay comfortable for one-handed use.
      expect(tester.getSize(google).height, greaterThanOrEqualTo(48));
      expect(tester.getSize(email).height, greaterThanOrEqualTo(48));
    });

    testWidgets('without the Google client, email is the primary action', (
      tester,
    ) async {
      await pumpWelcome(tester, offerGoogle: false);
      expect(find.text('Continue with Google'), findsNothing);
      expect(
        find.widgetWithText(FilledButton, 'Continue with Email'),
        findsOneWidget,
      );
    });

    testWidgets('fits a small phone at 200% text without overflow', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.view.reset);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await pumpSirfHum(
        tester,
        session: FakeAccountSession(),
        extra: [
          emailLinkSignInProvider.overrideWithValue(FakeEmailLinkSignIn()),
          authLinkDomainProvider.overrideWithValue(_domain),
          googleSignInProvider.overrideWithValue(
            _GoogleThatSignsIn(FakeAccountSession()),
          ),
        ],
      );
      expect(tester.takeException(), isNull);
      await tester.scrollUntilVisible(
        find.textContaining('By continuing'),
        100,
      );
      expect(find.textContaining('By continuing'), findsOneWidget);
    });

    testWidgets('a conflict says to use email; no account is touched', (
      tester,
    ) async {
      await pumpWelcome(tester, failure: GoogleAccountFailure.emailLinkAccount);
      await tester.tap(find.text('Continue with Google'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('already signs in with an email link'),
        findsOneWidget,
      );
      expect(_location(tester), EntryRoutes.welcome);
      await tester.tap(find.text('Continue with Email'));
      await tester.pumpAndSettle();
      expect(find.byType(TextField), findsOneWidget);
    });

    testWidgets('cancelling the picker shows nothing and stays put', (
      tester,
    ) async {
      await pumpWelcome(tester, failure: GoogleAccountFailure.cancelled);
      await tester.tap(find.text('Continue with Google'));
      await tester.pumpAndSettle();
      expect(_location(tester), EntryRoutes.welcome);
      expect(find.textContaining('isn’t available'), findsNothing);
    });

    testWidgets('the email step goes back to the choice', (tester) async {
      await pumpWelcome(tester);
      await tester.tap(find.text('Continue with Email'));
      await tester.pumpAndSettle();
      expect(find.byType(TextField), findsOneWidget);
      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();
      expect(find.text('Continue with Google'), findsOneWidget);
    });
  });

  group('Google sign-in is identity only (D-150)', () {
    testWidgets(
      'a new Google account lands on pairing, never on the couple screens',
      (tester) async {
        await pumpWelcome(tester);
        await tester.tap(find.text('Continue with Google'));
        await tester.pumpAndSettle();
        // The server, not the sign-in, says where this account stands.
        expect(_location(tester), EntryRoutes.pair);
      },
    );

    testWidgets(
      'an account the server refuses stays refused (unverified, disabled)',
      (tester) async {
        await pumpWelcome(
          tester,
          backend: FakePairingBackend.failing(PairingFailure.unauthenticated),
        );
        await tester.tap(find.text('Continue with Google'));
        await tester.pumpAndSettle();
        expect(_location(tester), EntryRoutes.start);
        expect(find.text('Please sign in again.'), findsOneWidget);
      },
    );

    test(
      'a restored Google session is resolved by the server like any',
      () async {
        // The session sees an AccountId only; the provider is not visible to
        // it, so a restored Google session cannot skip the server's answer.
        for (final backend in [
          FakePairingBackend.returning(const PairingNone()),
          FakePairingBackend.failing(PairingFailure.unauthenticated),
        ]) {
          final container = ProviderContainer(
            overrides: sessionOverrides(
              session: FakeAccountSession(alice),
              backend: backend,
            ),
          );
          addTearDown(container.dispose);
          container.listen(sessionProvider, (_, _) {});
          for (var i = 0; i < 10; i++) {
            await Future<void>.delayed(Duration.zero);
          }
          expect(container.read(sessionProvider), isNot(isA<SessionPaired>()));
        }
      },
    );

    test('sign-out ends the session and forgets the Google choice', () async {
      final session = FakeAccountSession(alice);
      final google = _GoogleThatSignsIn(session);
      final container = ProviderContainer(
        overrides: sessionOverrides(
          session: session,
          backend: FakePairingBackend.returning(const PairingNone()),
          extra: [googleSignInProvider.overrideWithValue(google)],
        ),
      );
      addTearDown(container.dispose);
      container.listen(sessionProvider, (_, _) {});
      await Future<void>.delayed(Duration.zero);
      await container.read(sessionProvider.notifier).signOut();
      await Future<void>.delayed(Duration.zero);
      expect(session.signOuts, 1);
      expect(google.forgets, 1);
      expect(container.read(sessionProvider), isA<SessionSignedOut>());
    });
  });

  group('sign-in code cannot reach device trust (static)', () {
    // Every file on the sign-in path. If one of them could register,
    // activate, approve or revoke a device, or touch keys, Google (or email)
    // sign-in could bypass device trust. They cannot even import it.
    const signInFiles = [
      'lib/security/account/google_account_sign_in.dart',
      'lib/security/account/email_link_sign_in.dart',
      'lib/security/account/sign_in_result.dart',
      'lib/session/sign_in_controller.dart',
      'lib/infrastructure/firebase/firebase_google_sign_in.dart',
      'lib/infrastructure/firebase/firebase_email_link_sign_in.dart',
      'lib/app/entry/welcome_screen.dart',
    ];
    const forbiddenImports = [
      'security/device',
      'security/crypto',
      'security/couple',
      'security/messaging',
      'security/verification',
      'sirf_hum_crypto',
      'device_registry',
      'secure_key_store',
      'cloud_firestore',
      'cloud_functions',
      'shared_preferences',
      'flutter_secure_storage',
    ];

    test('no sign-in file imports device, key, couple or storage code', () {
      for (final path in signInFiles) {
        final imports = File(
          path,
        ).readAsLinesSync().where((l) => l.startsWith('import ')).join('\n');
        for (final forbidden in forbiddenImports) {
          expect(
            imports,
            isNot(contains(forbidden)),
            reason: '$path must not import $forbidden',
          );
        }
      }
    });

    test(
      'Google asks for no access token or scope; nothing links silently',
      () {
        final google = File(
          'lib/infrastructure/firebase/firebase_google_sign_in.dart',
        ).readAsStringSync();
        for (final forbidden in [
          'accessToken',
          'authorizationClient',
          'authorizeScopes',
          'authorizeServer',
          'scopeHint',
        ]) {
          expect(google, isNot(contains(forbidden)));
        }
        final lib = Directory('lib')
            .listSync(recursive: true)
            .whereType<File>()
            .where((f) => f.path.endsWith('.dart'));
        for (final file in lib) {
          expect(
            file.readAsStringSync(),
            isNot(contains('linkWithCredential')),
            reason: '${file.path}: accounts are never linked by the app',
          );
        }
      },
    );
  });
}
