import 'package:sirf_hum/security/couple/couple_profiles.dart';

/// Home's greeting line, from the local time of day.
String greetingFor(DateTime localTime) => switch (localTime.hour) {
  >= 5 && < 12 => 'Good morning',
  >= 12 && < 17 => 'Good afternoon',
  >= 17 && < 22 => 'Good evening',
  _ => 'Hello, you two',
};

/// The couple's name on Home. Profiles are optional, so every combination
/// reads naturally; the fallback is the product's own promise.
String coupleTitle(CoupleNames names) => switch ((names.yours, names.partner)) {
  (final String a, final String b) => '$a & $b',
  (null, final String b) => 'You & $b',
  (final String a, null) => '$a & your person',
  (null, null) => 'Just the two of you',
};
