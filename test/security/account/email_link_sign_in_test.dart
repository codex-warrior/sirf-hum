import 'package:flutter_test/flutter_test.dart';
import 'package:sirf_hum/security/account/email_link_sign_in.dart';

void main() {
  const domain = 'sirf-hum-staging.firebaseapp.com';
  const action =
      'https://$domain/__/auth/action?apiKey=k&mode=signIn&oobCode=abc&continueUrl=x';

  String? linkFrom(String s) =>
      signInLinkFrom(Uri.parse(s), linkDomain: domain);

  group('normalizeEmail', () {
    test('trims a plausible address', () {
      expect(normalizeEmail('  a.b@example.com '), 'a.b@example.com');
    });

    test('refuses what cannot be an address', () {
      for (final bad in [
        '',
        'plain',
        '@example.com',
        'a@',
        'a@b',
        'a@@example.com',
        'a@exa mple.com',
        'a@.example.com',
        'a@example.com.',
        '${'x' * 250}@example.com',
      ]) {
        expect(normalizeEmail(bad), isNull, reason: bad);
      }
    });
  });

  group('signInLinkFrom', () {
    test('accepts the bare action link', () {
      expect(linkFrom(action), action);
    });

    test('unwraps the email wrapper link', () {
      final wrapped = Uri(
        scheme: 'https',
        host: domain,
        path: '/__/auth/links',
        queryParameters: {'link': action},
      ).toString();
      expect(linkFrom(wrapped), action);
    });

    test('anchors an App Link the router received without a host', () {
      final routed = Uri(
        path: '/__/auth/links',
        queryParameters: {'link': action},
      ).toString();
      expect(linkFrom(routed), action);
    });

    test('refuses another host, also inside the wrapper', () {
      expect(linkFrom(action.replaceFirst(domain, 'evil.example')), isNull);
      expect(
        linkFrom(action.replaceFirst(domain, 'sirf-hum-prod.firebaseapp.com')),
        isNull,
      );
      final wrappedForeign = Uri(
        scheme: 'https',
        host: domain,
        path: '/__/auth/links',
        queryParameters: {'link': action.replaceFirst(domain, 'evil.example')},
      ).toString();
      expect(linkFrom(wrappedForeign), isNull);
    });

    test('refuses http, other paths, other modes and a missing code', () {
      expect(linkFrom(action.replaceFirst('https', 'http')), isNull);
      expect(linkFrom(action.replaceFirst('/__/auth/action', '/x')), isNull);
      expect(linkFrom(action.replaceFirst('signIn', 'resetPassword')), isNull);
      expect(linkFrom(action.replaceFirst('oobCode=abc', 'oobCode=')), isNull);
      expect(linkFrom('not a link at all'), isNull);
    });

    test('refuses everything when no link domain is configured', () {
      expect(signInLinkFrom(Uri.parse(action), linkDomain: ''), isNull);
    });
  });
}
