import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:sirf_hum/core/logging/app_logger.dart';
import 'package:sirf_hum/infrastructure/firebase/firebase_google_sign_in.dart';
import 'package:sirf_hum/security/account/google_account_sign_in.dart';

const _token = 'eyJhbGciOiJSUzI1NiJ9.google-id-token-must-not-leak.sig';

class _Sink implements LogSink {
  final lines = <String>[];

  @override
  void write(LogRecord record) => lines.add(record.message);
}

/// Drives [GoogleSignInFlow] (D-150) with scripted plugin answers.
class _Script {
  Object? pickerError;
  String? token = _token;
  Object? firebaseError;
  bool emailVerified = true;
  bool isNewUser = false;

  final exchanged = <String>[];
  int firebaseSignOuts = 0;
  int googleForgets = 0;

  GoogleSignInFlow flow() => GoogleSignInFlow(
    idToken: () async {
      if (pickerError case final e?) throw e;
      return token;
    },
    exchange: (idToken) async {
      exchanged.add(idToken);
      if (firebaseError case final e?) throw e;
      return (emailVerified: emailVerified, isNewUser: isNewUser);
    },
    signOutFirebase: () async => firebaseSignOuts++,
    forgetGoogle: () async => googleForgets++,
  );
}

Matcher _fails(GoogleAccountFailure failure) => throwsA(
  isA<GoogleAccountException>().having((e) => e.failure, 'failure', failure),
);

void main() {
  late _Script script;
  late _Sink sink;

  setUp(() {
    script = _Script();
    sink = _Sink();
    AppLogger.configure(sinks: [sink]);
    addTearDown(() => AppLogger.configure(sinks: const [DeveloperLogSink()]));
  });

  tearDown(() {
    // The ID token is a bearer credential: never logged, whatever happened.
    for (final line in sink.lines) {
      expect(line, isNot(contains(_token)));
      expect(line, isNot(contains('google-id-token')));
    }
  });

  group('success', () {
    test(
      'a new Google user: the token is exchanged once with Firebase',
      () async {
        script.isNewUser = true;
        final result = await script.flow().run();
        expect(result.isNewAccount, isTrue);
        expect(script.exchanged, [_token]);
        expect(script.firebaseSignOuts, 0);
        expect(script.googleForgets, 0);
      },
    );

    test('an existing Google user signs in to the same account', () async {
      final result = await script.flow().run();
      expect(result.isNewAccount, isFalse);
      expect(script.exchanged, [_token]);
    });
  });

  group('picker', () {
    test(
      'cancelled or interrupted is a quiet cancel; Firebase is never asked',
      () async {
        for (final code in [
          GoogleSignInExceptionCode.canceled,
          GoogleSignInExceptionCode.interrupted,
        ]) {
          script.pickerError = GoogleSignInException(code: code);
          await expectLater(
            script.flow().run(),
            _fails(GoogleAccountFailure.cancelled),
          );
        }
        expect(script.exchanged, isEmpty);
        expect(sink.lines, isEmpty);
      },
    );

    test('configuration and platform errors are "unavailable"', () async {
      for (final code in [
        GoogleSignInExceptionCode.clientConfigurationError,
        GoogleSignInExceptionCode.providerConfigurationError,
        GoogleSignInExceptionCode.uiUnavailable,
        GoogleSignInExceptionCode.unknownError,
      ]) {
        script.pickerError = GoogleSignInException(
          code: code,
          description: 'alice@example.com could not be used',
        );
        await expectLater(
          script.flow().run(),
          _fails(GoogleAccountFailure.unavailable),
        );
      }
      expect(script.exchanged, isEmpty);
      // Codes only: the description can name the account.
      expect(sink.lines.join('\n'), isNot(contains('alice@example.com')));
    });

    test('no ID token is "unavailable" and nothing is exchanged', () async {
      for (final token in [null, '']) {
        script.token = token;
        await expectLater(
          script.flow().run(),
          _fails(GoogleAccountFailure.unavailable),
        );
      }
      expect(script.exchanged, isEmpty);
    });
  });

  group('Firebase exchange', () {
    test(
      'an email that signs in by link is never linked silently (conflict)',
      () async {
        script.firebaseError = FirebaseAuthException(
          code: 'account-exists-with-different-credential',
          email: 'alice@example.com',
        );
        await expectLater(
          script.flow().run(),
          _fails(GoogleAccountFailure.emailLinkAccount),
        );
        // No session was created; the Google choice is cleared so another
        // account can be picked. No linking call exists in the flow at all.
        expect(script.firebaseSignOuts, 0);
        expect(script.googleForgets, 1);
        expect(sink.lines.join('\n'), isNot(contains('alice@example.com')));
      },
    );

    test('Firebase failures map to categories', () async {
      const cases = {
        'user-disabled': GoogleAccountFailure.accountDisabled,
        'too-many-requests': GoogleAccountFailure.tooManyRequests,
        'network-request-failed': GoogleAccountFailure.network,
        'invalid-credential': GoogleAccountFailure.unavailable,
        'operation-not-allowed': GoogleAccountFailure.unavailable,
      };
      for (final MapEntry(key: code, value: failure) in cases.entries) {
        script.firebaseError = FirebaseAuthException(code: code);
        await expectLater(script.flow().run(), _fails(failure));
      }
    });

    test(
      'an unverified Google email is rejected and signed out at once (D-149)',
      () async {
        script.emailVerified = false;
        await expectLater(
          script.flow().run(),
          _fails(GoogleAccountFailure.unverifiedEmail),
        );
        expect(script.firebaseSignOuts, 1);
        expect(script.googleForgets, 1);
      },
    );
  });
}
