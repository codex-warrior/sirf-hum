import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:sirf_hum/core/logging/app_logger.dart';
import 'package:sirf_hum/security/couple/couple_profiles.dart';
import 'package:sirf_hum_crypto/sirf_hum_crypto.dart';

/// Reads the couple's display names (D-100). Rules: `users/{uid}` is
/// readable by its owner and partner; `accountPartners/{uid}` by its owner.
/// The partner's account ID is used only to address their profile; it never
/// leaves this class.
class FirestoreCoupleProfiles implements CoupleProfiles {
  FirestoreCoupleProfiles({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  @override
  Future<CoupleNames> names(AccountId account) async {
    try {
      final own = _firestore.doc('users/${account.value}').get();
      final partners = await _firestore
          .doc('accountPartners/${account.value}')
          .get();
      final partnerId = partners.data()?['partnerAccountId'];
      final partner = partnerId is String && partnerId.isNotEmpty
          ? await _firestore.doc('users/$partnerId').get()
          : null;
      return CoupleNames(
        yours: CoupleNames.sanitize((await own).data()?['displayName']),
        partner: CoupleNames.sanitize(partner?.data()?['displayName']),
      );
    } on FirebaseException catch (e) {
      // Names are presentation only; the error type is enough to diagnose.
      AppLogger.warning('couple_profiles_unavailable', error: e);
      return CoupleNames.unknown;
    }
  }

  /// Creates the profile with the rules' exact fields the first time, and
  /// afterwards changes only the name and its timestamp.
  @override
  Future<void> setYourName(AccountId account, String name) async {
    final value = acceptableName(name);
    if (value == null) {
      throw const CoupleProfileException(CoupleProfileFailure.invalidName);
    }
    final doc = _firestore.doc('users/${account.value}');
    try {
      final existing = await doc.get();
      if (existing.exists) {
        await doc.update({
          'displayName': value,
          'updatedAt': FieldValue.serverTimestamp(),
        });
      } else {
        await doc.set({
          'schemaVersion': 1,
          'displayName': value,
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }
      AppLogger.info('profile_name_saved');
    } on FirebaseException catch (e) {
      AppLogger.warning('profile_name_save_failed', error: e);
      throw const CoupleProfileException(CoupleProfileFailure.unavailable);
    }
  }
}
