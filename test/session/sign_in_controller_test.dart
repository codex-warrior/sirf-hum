import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sirf_hum/security/account/email_link_sign_in.dart';
import 'package:sirf_hum/session/sign_in_controller.dart';

const _domain = 'sirf-hum-staging.firebaseapp.com';
const _link =
    'https://$_domain/__/auth/action?apiKey=k&mode=signIn&oobCode=abc&continueUrl=x';

class FakeEmailLinkSignIn implements EmailLinkSignIn {
  final sent = <String>[];
  final completed = <(String, String)>[];
  EmailLinkFailure? sendFailure;
  EmailLinkFailure? completeFailure;

  @override
  Future<void> sendLink(String email) async {
    if (sendFailure case final f?) throw EmailLinkException(f);
    sent.add(email);
  }

  @override
  Future<void> completeSignIn({
    required String email,
    required String link,
  }) async {
    if (completeFailure case final f?) throw EmailLinkException(f);
    completed.add((email, link));
  }
}

void main() {
  late FakeEmailLinkSignIn backend;
  late ProviderContainer container;
  SignInController controller() => container.read(signInProvider.notifier);
  SignInState state() => container.read(signInProvider);

  setUp(() {
    backend = FakeEmailLinkSignIn();
    container = ProviderContainer(
      overrides: [
        emailLinkSignInProvider.overrideWithValue(backend),
        authLinkDomainProvider.overrideWithValue(_domain),
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
    expect(state(), isA<SignInEnterEmail>());
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
}
