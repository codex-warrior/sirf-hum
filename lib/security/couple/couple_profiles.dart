import 'package:sirf_hum_crypto/sirf_hum_crypto.dart';

/// The two display names of a couple (`users/{uid}.displayName`, D-100).
/// Either may be missing: profiles are optional and carry no authority.
class CoupleNames {
  const CoupleNames({this.yours, this.partner});

  static const unknown = CoupleNames();

  final String? yours;
  final String? partner;

  /// The rules' display-name constraint (firebase/firestore.rules,
  /// `validDisplayName`), applied again on read: anything else is treated as
  /// no name rather than shown.
  static String? sanitize(Object? value) {
    if (value is! String) return null;
    if (value.isEmpty || value.length > 64 || value.trim().isEmpty) {
      return null;
    }
    if (_control.hasMatch(value)) return null;
    return value.trim();
  }

  static final _control = RegExp(r'[\u0000-\u001F\u007F-\u009F]');

  @override
  bool operator ==(Object other) =>
      other is CoupleNames && other.yours == yours && other.partner == partner;

  @override
  int get hashCode => Object.hash(yours, partner);

  // Names are personal data: never printed into logs or errors.
  @override
  String toString() => 'CoupleNames(<redacted>)';
}

/// Port to the couple's profiles. Reads only what the rules already allow a
/// member (own and partner profile, own `accountPartners` record). The
/// partner's account ID stays inside the implementation.
abstract interface class CoupleProfiles {
  /// Best effort: failures return [CoupleNames.unknown], never an error,
  /// because names are presentation, not state.
  Future<CoupleNames> names(AccountId account);
}

class NoCoupleProfiles implements CoupleProfiles {
  const NoCoupleProfiles();

  @override
  Future<CoupleNames> names(AccountId account) async => CoupleNames.unknown;
}
