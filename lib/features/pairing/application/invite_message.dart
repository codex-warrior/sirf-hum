import 'package:sirf_hum/security/couple/pairing.dart';

/// The text the inviter shares (WhatsApp, Messages, …). The token alone
/// pairs no one: the inviter must still type the six-digit code that only
/// the accepting phone shows (D-131).
String inviteMessage(String token) =>
    'Join me on Sirf Hum, our private space for two.\n\n'
    'Open Sirf Hum, tap "I have an invite" and paste this whole message.\n\n'
    'Invite code: $token';

final _labelled = RegExp(
  r'Invite code:\s*([A-Za-z0-9_-]{22})(?![A-Za-z0-9_-])',
);
final _standalone = RegExp(
  r'(?<![A-Za-z0-9_-])([A-Za-z0-9_-]{22})(?![A-Za-z0-9_-])',
);

/// The invitation token in what the invitee pasted: the whole message, or
/// just the code. Null when there is none; the server decides whether it is
/// usable.
String? inviteTokenIn(String text) {
  final match = _labelled.firstMatch(text) ?? _standalone.firstMatch(text);
  final token = match?.group(1);
  return token != null && PairingInvitation.tokenPattern.hasMatch(token)
      ? token
      : null;
}
