import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sirf_hum/security/account/email_link_sign_in.dart';
import 'package:sirf_hum/security/account/google_account_sign_in.dart';
import 'package:sirf_hum/security/account/sign_in_result.dart';
import 'package:sirf_hum/session/sign_in_controller.dart';

const _domain = 'sirf-hum-staging.firebaseapp.com';
const _link =
    'https://$_domain/__/auth/action?apiKey=k&mode=signIn&oobCode=abc&continueUrl=x';

class FakeEmailLinkSignIn implements EmailLinkSignIn {
  final sent = <String>[];
  final completed = <(String, String)>[];
  EmailLinkFailure? sendFailure;
  EmailLinkFailure? completeFailure;
  bool newAccount = false;

  @override
  Future<void> sendLink(String email) async {
    if (sendFailure case final f?) throw EmailLinkException(f);
    sent.add(email);
  }

  @override
  Future<SignInResult> completeSignIn({
    required String email,
    required String link,
  }) async {
    if (completeFailure case final f?) throw EmailLinkException(f);
    completed.add((email, link));
    return SignInResult(isNewAccount: newAccount);
  }
}

/// A Google sign-in the test answers. [gate], when set, holds the attempt
/// open (picker showing) until completed.
class FakeGoogleSignIn implements GoogleAccountSignIn {
  int attempts = 0;
  int forgets = 0;
  GoogleAccountFailure? failure;
  bool newAccount = false;
  Completer<void>? gate;

  @override
  Future<SignInResult> signIn() async {
    attempts++;
    await gate?.future;
    if (failure case final f?) throw GoogleAccountException(f);
    return SignInResult(isNewAccount: newAccount);
  }

  @override
  Future<void> forget() async => forgets++;
}

void main() {
  late FakeEmailLinkSignIn backend;
  late FakeGoogleSignIn google;
  late ProviderContainer container;
  SignInController controller() => container.read(signInProvider.notifier);
  SignInState state() => container.read(signInProvider);

  setUp(() {
    backend = FakeEmailLinkSignIn();
    google = FakeGoogleSignIn();
    container = ProviderContainer(
      overrides: [
        emailLinkSignInProvider.overrideWithValue(backend),
        authLinkDomainProvider.overrideWithValue(_domain),
        googleSignInProvider.overrideWithValue(google),
      ],
    );
    addTearDown(container.dispose);
  });

  test('an invalid address never reaches the backend', () async {
    await controller().send('not-an-email');
    expect(backend.sent, isEmpty);
    expect(
      state(),
      isA<SignInEnterEmail>().having(
        (s) => s.failure,
        'failure',
        EmailLinkFailure.invalidEmail,
      ),
    );
  });

  test('send, then the link completes for the same address', () async {
    await controller().send(' a@example.com ');
    expect(backend.sent, ['a@example.com']);
    expect(state(), isA<SignInLinkSent>());

    await controller().receiveLink(_link);
    expect(backend.completed, [('a@example.com', _link)]);
    // Ready for a later sign-out.
    expect(state(), isA<SignInChooseMethod>());
  });

  test('a new address and an existing one complete the same way', () async {
    for (final isNew in [true, false]) {
      backend.newAccount = isNew;
      await controller().send('a@example.com');
      await controller().receiveLink(_link);
      expect(state(), isA<SignInChooseMethod>());
    }
    expect(backend.completed, hasLength(2));
  });

  test('a send failure is shown as a category on the form', () async {
    backend.sendFailure = EmailLinkFailure.tooManyRequests;
    await controller().send('a@example.com');
    expect(
      state(),
      isA<SignInEnterEmail>().having(
        (s) => s.failure,
        'failure',
        EmailLinkFailure.tooManyRequests,
      ),
    );
  });

  test(
    'a link without a known address asks for it (restart, other phone)',
    () async {
      await controller().receiveLink(_link);
      expect(state(), isA<SignInNeedsEmail>());
      expect(backend.completed, isEmpty);

      await controller().confirmEmail('b@example.com');
      expect(backend.completed, [('b@example.com', _link)]);
    },
  );

  test('a link for another host or a non-link is refused locally', () async {
    await controller().send('a@example.com');
    for (final foreign in [
      _link.replaceFirst(_domain, 'evil.example'),
      _link.replaceFirst(_domain, 'sirf-hum-prod.firebaseapp.com'),
      'hello',
    ]) {
      await controller().receiveLink(foreign);
      expect(
        state(),
        isA<SignInLinkSent>().having(
          (s) => s.failure,
          'failure',
          EmailLinkFailure.invalidLink,
        ),
      );
    }
    expect(backend.completed, isEmpty);
  });

  test('a mismatched address keeps the link and asks again', () async {
    await controller().receiveLink(_link);
    backend.completeFailure = EmailLinkFailure.emailMismatch;
    await controller().confirmEmail('wrong@example.com');
    expect(
      state(),
      isA<SignInNeedsEmail>().having(
        (s) => s.failure,
        'failure',
        EmailLinkFailure.emailMismatch,
      ),
    );
    backend.completeFailure = null;
    await controller().confirmEmail('right@example.com');
    expect(backend.completed, [('right@example.com', _link)]);
  });

  test(
    'an expired link returns to the waiting screen with the reason',
    () async {
      await controller().send('a@example.com');
      backend.completeFailure = EmailLinkFailure.expiredLink;
      await controller().receiveLink(_link);
      expect(
        state(),
        isA<SignInLinkSent>().having(
          (s) => s.failure,
          'failure',
          EmailLinkFailure.expiredLink,
        ),
      );
    },
  );

  test('restart forgets the address', () async {
    await controller().send('a@example.com');
    controller().restart();
    await controller().receiveLink(_link);
    expect(state(), isA<SignInNeedsEmail>());
  });

  test('without a configured domain every link is refused', () async {
    final bare = ProviderContainer(
      overrides: [emailLinkSignInProvider.overrideWithValue(backend)],
    );
    addTearDown(bare.dispose);
    await bare.read(signInProvider.notifier).receiveLink(_link);
    expect(bare.read(signInProvider), isA<SignInEnterEmail>());
    expect(backend.completed, isEmpty);
  });

  group('choose a method (D-150)', () {
    test('starts on the choice, with no sign-up/sign-in question', () {
      expect(state(), isA<SignInChooseMethod>());
    });

    test('Continue with Email asks for the address; back returns', () async {
      controller().continueWithEmail();
      expect(state(), isA<SignInEnterEmail>());
      await controller().send('a@example.com');
      controller().back();
      expect(state(), isA<SignInChooseMethod>());
      // Back forgot the address: a link now asks for it again.
      await controller().receiveLink(_link);
      expect(state(), isA<SignInNeedsEmail>());
    });
  });

  group('Continue with Google (D-150)', () {
    test('a new Google user and an existing one both just sign in', () async {
      for (final isNew in [true, false]) {
        google.newAccount = isNew;
        await controller().continueWithGoogle();
        expect(
          state(),
          isA<SignInChooseMethod>().having((s) => s.failure, 'failure', null),
        );
      }
      expect(google.attempts, 2);
      // Google never touches the email path.
      expect(backend.sent, isEmpty);
      expect(backend.completed, isEmpty);
    });

    test('shows progress while the picker is open', () async {
      google.gate = Completer<void>();
      final attempt = controller().continueWithGoogle();
      expect(state(), isA<SignInWithGoogle>());
      google.gate!.complete();
      await attempt;
      expect(state(), isA<SignInChooseMethod>());
    });

    test('a double tap starts one attempt; email waits too', () async {
      google.gate = Completer<void>();
      final first = controller().continueWithGoogle();
      await controller().continueWithGoogle();
      controller().continueWithEmail();
      controller().back();
      expect(state(), isA<SignInWithGoogle>());
      google.gate!.complete();
      await first;
      expect(google.attempts, 1);
    });

    test('cancelling the picker is not an error', () async {
      google.failure = GoogleAccountFailure.cancelled;
      await controller().continueWithGoogle();
      expect(
        state(),
        isA<SignInChooseMethod>().having((s) => s.failure, 'failure', null),
      );
    });

    test('a failure is shown as a category on the choice', () async {
      for (final failure in [
        GoogleAccountFailure.unavailable,
        GoogleAccountFailure.network,
        GoogleAccountFailure.unverifiedEmail,
        GoogleAccountFailure.accountDisabled,
      ]) {
        google.failure = failure;
        await controller().continueWithGoogle();
        expect(
          state(),
          isA<SignInChooseMethod>().having(
            (s) => s.failure,
            'failure',
            failure,
          ),
        );
      }
    });

    test(
      'an email-link account conflict is reported, never resolved by linking',
      () async {
        google.failure = GoogleAccountFailure.emailLinkAccount;
        await controller().continueWithGoogle();
        expect(
          state(),
          isA<SignInChooseMethod>().having(
            (s) => s.failure,
            'failure',
            GoogleAccountFailure.emailLinkAccount,
          ),
        );
        // Nothing was sent on the user's behalf; they choose email.
        expect(backend.sent, isEmpty);
      },
    );

    test('not offered: the call does nothing', () async {
      final bare = ProviderContainer(
        overrides: [emailLinkSignInProvider.overrideWithValue(backend)],
      );
      addTearDown(bare.dispose);
      await bare.read(signInProvider.notifier).continueWithGoogle();
      expect(bare.read(signInProvider), isA<SignInChooseMethod>());
      expect(google.attempts, 0);
    });

    test(
      'a pending email address is forgotten after Google signs in',
      () async {
        await controller().send('a@example.com');
        controller().back();
        await controller().continueWithGoogle();
        await controller().receiveLink(_link);
        expect(state(), isA<SignInNeedsEmail>());
        expect(backend.completed, isEmpty);
      },
    );
  });
}
