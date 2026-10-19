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
}
