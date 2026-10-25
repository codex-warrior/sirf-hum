/// What this phone remembers about the partner's security code (D-160),
/// WhatsApp-style: the code it last trusted, and the code the person last
/// compared by hand. Both are the safety number's digits, which are shown
/// on screen anyway: nothing here is secret. Kept in the account's local
/// slot, so removing the account from the phone removes it too.
abstract interface class PartnerCodeMemory {
  /// The code trusted most recently, or null before the first time.
  Future<String?> lastTrusted();

  Future<void> setLastTrusted(String code);

  /// The code the person compared with their partner, or null.
  Future<String?> compared();

  Future<void> setCompared(String code);
}

/// A memory that forgets (tests, builds without a phone).
class InMemoryPartnerCodeMemory implements PartnerCodeMemory {
  String? _trusted;
  String? _compared;

  @override
  Future<String?> lastTrusted() async => _trusted;

  @override
  Future<void> setLastTrusted(String code) async => _trusted = code;

  @override
  Future<String?> compared() async => _compared;

  @override
  Future<void> setCompared(String code) async => _compared = code;
}
