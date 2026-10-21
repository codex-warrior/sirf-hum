import 'package:sirf_hum/security/account/sign_in_result.dart';

/// Port to "Continue with Google" (D-150).
///
/// Like email link (D-138), Google only establishes *which account* this
/// installation is. It never registers, activates or trusts a device and
/// never touches keys: device trust stays with person keys, certificates
/// and device proofs (D-070, D-081, D-127). A Google token is never key
/// material and never leaves the sign-in exchange.
abstract interface class GoogleAccountSignIn {
  /// Lets the user pick a Google account and signs in to Firebase with it.
  /// The account then arrives through `AccountSession`; an existing account
  /// is signed in, a new one is created by Firebase (one account per email).
  Future<SignInResult> signIn();

  /// Forgets the Google account choice on this device, so the next sign-in
  /// asks again (after sign-out). Best effort; never throws.
  Future<void> forget();
}

/// Why Google sign-in did not happen. Categories only: no address, token
/// or Google account detail appears in a failure, a log or the UI.
enum GoogleAccountFailure {
  /// The user closed the account picker. Not an error.
  cancelled,

  /// The email already belongs to an account that signs in by email link,
  /// and Firebase will not attach Google to it on its own. Never linked
  /// silently: the user signs in by email link instead (D-150).
  emailLinkAccount,

  /// Google did not vouch for the address; such an account can do nothing
  /// (D-149), so it is signed out at once.
  unverifiedEmail,

  /// The account was disabled by an operator.
  accountDisabled,
  tooManyRequests,
  network,

  /// Not configured, no Google account support on this phone, or a backend
  /// problem. Retryable later; the email path still works.
  unavailable,
}

class GoogleAccountException implements Exception {
  const GoogleAccountException(this.failure);

  final GoogleAccountFailure failure;

  @override
  String toString() => 'GoogleAccountException(${failure.name})';
}
