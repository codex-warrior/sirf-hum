import 'package:flutter_test/flutter_test.dart';
import 'package:sirf_hum/infrastructure/firebase/firebase_account_session.dart';
import 'package:sirf_hum/security/account/account_session.dart';
import 'package:sirf_hum_crypto/sirf_hum_crypto.dart';

void main() {
  test('a Firebase UID becomes the account', () {
    expect(FirebaseAccountSession.accountOf('uid123'), AccountId('uid123'));
  });

  test('no user, or an unusable UID, is signed out', () {
    expect(FirebaseAccountSession.accountOf(null), isNull);
    expect(FirebaseAccountSession.accountOf(''), isNull);
    expect(FirebaseAccountSession.accountOf('x' * 129), isNull);
  });

  test('a build without Firebase is always signed out', () async {
    expect(await const SignedOutAccountSession().accountChanges.toList(), [
      null,
    ]);
  });
}
