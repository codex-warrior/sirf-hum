import 'package:firebase_auth/firebase_auth.dart';
import 'package:sirf_hum/security/account/account_session.dart';
import 'package:sirf_hum_crypto/sirf_hum_crypto.dart';

/// Firebase Auth implementation of [AccountSession] (D-107).
///
/// `authStateChanges` emits the restored session first, which is the app's
/// only "auth restoration" path. Sign-in itself is not implemented: the
/// sign-in method is an open product decision.
class FirebaseAccountSession implements AccountSession {
  FirebaseAccountSession({FirebaseAuth? auth})
    : _auth = auth ?? FirebaseAuth.instance;

  final FirebaseAuth _auth;

  @override
  Stream<AccountId?> get accountChanges =>
      _auth.authStateChanges().map((user) => accountOf(user?.uid));

  @override
  Future<void> signOut() => _auth.signOut();

  /// A UID that cannot be an [AccountId] is treated as signed out rather
  /// than passed on.
  static AccountId? accountOf(String? uid) {
    if (uid == null) return null;
    try {
      return AccountId(uid);
    } on CryptoException {
      return null;
    }
  }
}
