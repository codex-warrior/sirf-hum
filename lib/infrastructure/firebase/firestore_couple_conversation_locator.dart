import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:sirf_hum/security/couple/couple_conversation.dart';
import 'package:sirf_hum/security/messaging/message_envelope.dart';
import 'package:sirf_hum_crypto/sirf_hum_crypto.dart';

/// Reads `accountPartners/{uid}` (server-written at pairing, owner-readable,
/// D-086). A record that does not have exactly the expected shape is treated
/// as no couple: nothing here guesses.
class FirestoreCoupleConversationLocator implements CoupleConversationLocator {
  FirestoreCoupleConversationLocator({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  static final RegExp _conversationPattern = RegExp(r'^[0-9a-f]{32}$');
  static final RegExp _accountPattern = RegExp(r'^[A-Za-z0-9_-]{1,128}$');

  @override
  Future<CoupleConversation?> locate(AccountId account) async {
    final doc = await _firestore.doc('accountPartners/${account.value}').get();
    return parse(account, doc.data());
  }

  /// The record's meaning, or null. Public for tests.
  static CoupleConversation? parse(
    AccountId account,
    Map<String, dynamic>? data,
  ) {
    final partner = data?['partnerAccountId'];
    final conversation = data?['conversationId'];
    if (partner is! String ||
        !_accountPattern.hasMatch(partner) ||
        partner == account.value ||
        conversation is! String ||
        !_conversationPattern.hasMatch(conversation)) {
      return null;
    }
    return CoupleConversation(
      partner: AccountId(partner),
      conversation: ConversationId(
        EncryptedMessageEnvelope.bytesOfHex(conversation),
      ),
    );
  }
}
