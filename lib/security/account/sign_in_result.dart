/// What a completed sign-in reports, whichever provider was used.
///
/// Deliberately nothing about the account (no UID, address or token): the
/// account arrives through `AccountSession`, and a new account is treated
/// exactly like an existing one. [isNewAccount] is only logged, so the
/// beta can tell sign-ups from sign-ins.
final class SignInResult {
  const SignInResult({required this.isNewAccount});

  final bool isNewAccount;
}
