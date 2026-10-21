import 'package:firebase_auth/firebase_auth.dart';
import 'package:sirf_hum/core/logging/app_logger.dart';
import 'package:sirf_hum/core/logging/log_value.dart';
import 'package:sirf_hum/security/account/email_link_sign_in.dart';

/// Firebase Auth email-link (passwordless) sign-in, D-138.
///
/// The link opens on the project's Hosting domain ([linkDomain], the
/// Firebase auth domain) and returns to the app through an Android App Link
/// for [androidPackageName]. Firebase makes links single-use and expiring;
/// the email must match the one the link was sent to.
class FirebaseEmailLinkSignIn implements EmailLinkSignIn {
  FirebaseEmailLinkSignIn({
    required this.linkDomain,
    required this.androidPackageName,
    FirebaseAuth? auth,
  }) : _auth = auth ?? FirebaseAuth.instance;

  final String linkDomain;
  final String androidPackageName;
  final FirebaseAuth _auth;

  @override
  Future<void> sendLink(String email) async {
    try {
      await _auth.sendSignInLinkToEmail(
        email: email,
        actionCodeSettings: ActionCodeSettings(
          url: 'https://$linkDomain/',
          linkDomain: linkDomain,
          handleCodeInApp: true,
          androidPackageName: androidPackageName,
        ),
      );
    } on FirebaseAuthException catch (e) {
      throw _failure(e, completing: false);
    }
  }

  @override
  Future<void> completeSignIn({
    required String email,
    required String link,
  }) async {
    if (!_auth.isSignInWithEmailLink(link)) {
      throw const EmailLinkException(EmailLinkFailure.invalidLink);
    }
    try {
      await _auth.signInWithEmailLink(email: email, emailLink: link);
    } on FirebaseAuthException catch (e) {
      throw _failure(e, completing: true);
    }
  }

  // Codes are Firebase's own identifiers, safe to log; messages are not
  // (they can quote the address).
  static EmailLinkException _failure(
    FirebaseAuthException e, {
    required bool completing,
  }) {
    AppLogger.warning(
      'email_link_failed',
      fields: {
        'code': SafeLogString(e.code),
        'step': SafeLogString(completing ? 'complete' : 'send'),
      },
    );
    return EmailLinkException(switch (e.code) {
      // Completing with an address the link was not sent to.
      'invalid-email' when completing => EmailLinkFailure.emailMismatch,
      'invalid-email' || 'missing-email' => EmailLinkFailure.invalidEmail,
      'expired-action-code' => EmailLinkFailure.expiredLink,
      'invalid-action-code' => EmailLinkFailure.invalidLink,
      'too-many-requests' ||
      'quota-exceeded' => EmailLinkFailure.tooManyRequests,
      'network-request-failed' => EmailLinkFailure.network,
      _ => EmailLinkFailure.unavailable,
    });
  }
}
