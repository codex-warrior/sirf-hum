import 'package:sirf_hum_crypto/sirf_hum_crypto.dart';

/// Port to the signed-in account (Firebase Auth in production, D-107).
///
/// It only says *which* account this installation is signed in as. It never
/// says anything about couples, devices or trust: those are answered by the
/// server for that account (D-100, D-106).
abstract interface class AccountSession {
  /// The current account, then every change. A restored session is emitted
  /// first, so listeners never need a separate "current user" read. `null`
  /// means signed out.
  Stream<AccountId?> get accountChanges;

  Future<void> signOut();
}

/// The account session of a build without Firebase (tests, an unconfigured
/// development build): always signed out. Never a fallback for a configured
/// build whose auth failed.
class SignedOutAccountSession implements AccountSession {
  const SignedOutAccountSession();

  @override
  Stream<AccountId?> get accountChanges => Stream.value(null);

  @override
  Future<void> signOut() async {}
}

/// The account session of a configured build whose Firebase failed to start:
/// the account cannot be known, which the session reports as unavailable —
/// never as signed out, and never as signed in.
class UnavailableAccountSession implements AccountSession {
  const UnavailableAccountSession();

  @override
  Stream<AccountId?> get accountChanges =>
      Stream.error(const AccountSessionUnavailable());

  @override
  Future<void> signOut() async {}
}

class AccountSessionUnavailable implements Exception {
  const AccountSessionUnavailable();

  @override
  String toString() => 'AccountSessionUnavailable()';
}
