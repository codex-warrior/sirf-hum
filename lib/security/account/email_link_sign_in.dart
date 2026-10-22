import 'package:sirf_hum/security/account/sign_in_result.dart';

/// Port to passwordless email-link sign-in (D-138), the fallback to
/// Google (D-150).
///
/// Signing in only establishes *which account* this installation is. It
/// never registers, activates or trusts a device and never touches keys:
/// device trust stays with person keys, certificates and device proofs
/// (D-070, D-081, D-127). A signed-in account with no trusted device holds
/// nothing.
abstract interface class EmailLinkSignIn {
  /// Asks the backend to email a single-use sign-in link to [email].
  Future<void> sendLink(String email);

  /// Completes sign-in with a [link] from the email, for the same [email]
  /// it was sent to. The account then arrives through `AccountSession`; a
  /// new address creates the account, an existing one signs in to it.
  Future<SignInResult> completeSignIn({
    required String email,
    required String link,
  });
}

/// Why sign-in did not happen. Categories only: the email address and the
/// link never appear in a failure, a log or the UI's error text.
enum EmailLinkFailure {
  invalidEmail,
  invalidLink,
  expiredLink,
  emailMismatch,
  tooManyRequests,
  network,
  unavailable,
}

class EmailLinkException implements Exception {
  const EmailLinkException(this.failure);

  final EmailLinkFailure failure;

  @override
  String toString() => 'EmailLinkException(${failure.name})';
}

/// A build without Firebase: sign-in is not possible. Never a fallback for
/// a configured build.
class UnavailableEmailLinkSignIn implements EmailLinkSignIn {
  const UnavailableEmailLinkSignIn();

  @override
  Future<void> sendLink(String email) =>
      Future.error(const EmailLinkException(EmailLinkFailure.unavailable));

  @override
  Future<SignInResult> completeSignIn({
    required String email,
    required String link,
  }) => Future.error(const EmailLinkException(EmailLinkFailure.unavailable));
}

/// The trimmed address if it can be an email address, else null. A shape
/// check only (one `@`, a dotted domain, no spaces, RFC 5321 length): the
/// backend is the authority, this just catches typos before a round trip.
String? normalizeEmail(String input) {
  final email = input.trim();
  if (email.isEmpty || email.length > 254) return null;
  final at = email.indexOf('@');
  if (at <= 0 || at != email.lastIndexOf('@')) return null;
  final domain = email.substring(at + 1);
  if (RegExp(r'\s').hasMatch(email)) return null;
  if (!domain.contains('.') || domain.startsWith('.') || domain.endsWith('.')) {
    return null;
  }
  return email;
}

/// Path prefix of Firebase's email action links on the Hosting domain; the
/// Android App Link filter matches the same prefix.
const authLinkPathPrefix = '/__/auth/';

/// The sign-in link to hand to [EmailLinkSignIn.completeSignIn], or null if
/// [uri] is not a sign-in link for [linkDomain].
///
/// Accepts the email's wrapper (`/__/auth/links?link=<action link>`) and the
/// bare action link (`/__/auth/action?mode=signIn&oobCode=…`). A link for
/// another host is refused, so a pasted or deep-linked URL from elsewhere
/// is never sent to the backend. An App Link delivered without its host
/// (the router sees only path and query) is anchored to [linkDomain],
/// because Android only opens the app for that host.
String? signInLinkFrom(Uri uri, {required String linkDomain}) {
  if (linkDomain.isEmpty) return null;
  final anchored = uri.hasAuthority
      ? uri
      : uri.replace(scheme: 'https', host: linkDomain);
  if (anchored.scheme != 'https' || anchored.host != linkDomain) return null;
  if (!anchored.path.startsWith(authLinkPathPrefix)) return null;

  final wrapped = anchored.queryParameters['link'];
  if (wrapped != null) {
    final inner = Uri.tryParse(wrapped);
    if (inner == null || !inner.hasAuthority) return null;
    return signInLinkFrom(inner, linkDomain: linkDomain);
  }
  final query = anchored.queryParameters;
  if (query['mode'] != 'signIn' || (query['oobCode'] ?? '').isEmpty) {
    return null;
  }
  return anchored.toString();
}
