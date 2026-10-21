import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:sirf_hum/core/logging/app_logger.dart';
import 'package:sirf_hum/core/logging/log_value.dart';
import 'package:sirf_hum/security/account/google_account_sign_in.dart';
import 'package:sirf_hum/security/account/sign_in_result.dart';

/// "Continue with Google" on Android (D-150): the official `google_sign_in`
/// plugin (Credential Manager) returns a Google ID token for
/// [serverClientId], and Firebase Auth exchanges it once
/// (`signInWithCredential`, its documented flow). No OAuth secret exists
/// in the client, no access token or scope is requested, and the ID token
/// is never stored, logged or sent anywhere but Firebase Auth.
///
/// [serverClientId] is the project's *Web* OAuth client ID (public; the
/// audience of the ID token Firebase verifies). The Android OAuth client
/// is matched by package name and signing-certificate SHA-1, registered per
/// environment in that environment's project only.
class FirebaseGoogleSignIn implements GoogleAccountSignIn {
  FirebaseGoogleSignIn({
    required this.serverClientId,
    FirebaseAuth? auth,
    GoogleSignIn? google,
  }) : _auth = auth ?? FirebaseAuth.instance,
       _google = google ?? GoogleSignIn.instance;

  final String serverClientId;
  final FirebaseAuth _auth;
  final GoogleSignIn _google;
  Future<void>? _initialized;

  // The plugin must be initialized exactly once per process.
  Future<void> _ready() =>
      _initialized ??= _google.initialize(serverClientId: serverClientId);

  @override
  Future<SignInResult> signIn() => GoogleSignInFlow(
    idToken: () async {
      await _ready();
      final account = await _google.authenticate();
      return account.authentication.idToken;
    },
    exchange: (idToken) async {
      final result = await _auth.signInWithCredential(
        GoogleAuthProvider.credential(idToken: idToken),
      );
      return (
        emailVerified: result.user?.emailVerified ?? false,
        isNewUser: result.additionalUserInfo?.isNewUser ?? false,
      );
    },
    signOutFirebase: _auth.signOut,
    forgetGoogle: forget,
  ).run();

  @override
  Future<void> forget() async {
    try {
      await _ready();
      await _google.signOut();
    } on Object catch (e) {
      AppLogger.warning('google_forget_failed', error: e);
    }
  }
}

typedef FirebaseExchange = ({bool emailVerified, bool isNewUser});

/// The decisions of a Google sign-in, apart from the plugins so every
/// branch is unit-tested (`firebase_google_sign_in_test.dart`).
@visibleForTesting
class GoogleSignInFlow {
  GoogleSignInFlow({
    required this.idToken,
    required this.exchange,
    required this.signOutFirebase,
    required this.forgetGoogle,
  });

  final Future<String?> Function() idToken;
  final Future<FirebaseExchange> Function(String idToken) exchange;
  final Future<void> Function() signOutFirebase;
  final Future<void> Function() forgetGoogle;

  Future<SignInResult> run() async {
    final String? token;
    try {
      token = await idToken();
    } on GoogleSignInException catch (e) {
      throw _googleFailure(e);
    }
    if (token == null || token.isEmpty) {
      _log('google_sign_in_failed', step: 'token', code: 'no_id_token');
      throw const GoogleAccountException(GoogleAccountFailure.unavailable);
    }

    final FirebaseExchange outcome;
    try {
      outcome = await exchange(token);
    } on FirebaseAuthException catch (e) {
      // Let the user pick another account next time.
      await forgetGoogle();
      throw _firebaseFailure(e);
    }

    if (!outcome.emailVerified) {
      // Callables refuse it anyway (D-149); do not leave it signed in.
      _log('google_sign_in_failed', step: 'verify', code: 'email_unverified');
      await signOutFirebase();
      await forgetGoogle();
      throw const GoogleAccountException(GoogleAccountFailure.unverifiedEmail);
    }
    return SignInResult(isNewAccount: outcome.isNewUser);
  }

  // The exception's description and details can name the account; only
  // the code is logged.
  static GoogleAccountException _googleFailure(GoogleSignInException e) {
    final failure = switch (e.code) {
      GoogleSignInExceptionCode.canceled ||
      GoogleSignInExceptionCode.interrupted => GoogleAccountFailure.cancelled,
      _ => GoogleAccountFailure.unavailable,
    };
    if (failure != GoogleAccountFailure.cancelled) {
      _log('google_sign_in_failed', step: 'picker', code: e.code.name);
    }
    return GoogleAccountException(failure);
  }

  // Firebase codes are identifiers, safe to log; messages are not.
  static GoogleAccountException _firebaseFailure(FirebaseAuthException e) {
    _log('google_sign_in_failed', step: 'firebase', code: e.code);
    return GoogleAccountException(switch (e.code) {
      // One account per email: the address signs in by email link and
      // Firebase does not trust Google for it. Never linked silently.
      'account-exists-with-different-credential' =>
        GoogleAccountFailure.emailLinkAccount,
      'user-disabled' => GoogleAccountFailure.accountDisabled,
      'too-many-requests' ||
      'quota-exceeded' => GoogleAccountFailure.tooManyRequests,
      'network-request-failed' => GoogleAccountFailure.network,
      _ => GoogleAccountFailure.unavailable,
    });
  }

  static void _log(
    String event, {
    required String step,
    required String code,
  }) => AppLogger.warning(
    event,
    fields: {'step': SafeLogString(step), 'code': SafeLogString(code)},
  );
}
