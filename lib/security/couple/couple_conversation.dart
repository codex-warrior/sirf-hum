import 'package:sirf_hum_crypto/sirf_hum_crypto.dart';

/// The couple's conversation as the server provisioned it from the accepted
/// pairing (D-086): who the partner is and which conversation is theirs.
/// Addressing only; trust in the partner comes from verification (D-128),
/// never from this record.
class CoupleConversation {
  const CoupleConversation({required this.partner, required this.conversation});

  final AccountId partner;
  final ConversationId conversation;
}

/// Finds the signed-in account's couple conversation. `null` when the
/// server has none (not paired, or unpaired meanwhile). Throws on network or
/// backend failures.
abstract interface class CoupleConversationLocator {
  Future<CoupleConversation?> locate(AccountId account);
}
