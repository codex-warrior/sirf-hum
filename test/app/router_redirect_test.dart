import 'package:flutter_test/flutter_test.dart';
import 'package:sirf_hum/app/product_area.dart';
import 'package:sirf_hum/app/router.dart';
import 'package:sirf_hum/security/couple/couple_profiles.dart';
import 'package:sirf_hum/session/session_state.dart';

void main() {
  const pairedSession = SessionPaired(names: CoupleNames.unknown);
  final notPaired = <String, (SessionState, String)>{
    'starting': (const SessionStarting(), EntryRoutes.start),
    'unavailable': (
      const SessionUnavailable(SessionProblem.unreachable),
      EntryRoutes.start,
    ),
    'start failed': (
      const SessionUnavailable(SessionProblem.startFailed),
      EntryRoutes.start,
    ),
    'sign in again': (
      const SessionUnavailable(SessionProblem.signInAgain),
      EntryRoutes.start,
    ),
    'signed out': (const SessionSignedOut(), EntryRoutes.welcome),
    'not paired': (const SessionNotPaired(canPairHere: true), EntryRoutes.pair),
    'pairing': (
      const SessionPairing(
        stage: PairingStage.invitationSent,
        canPairHere: true,
      ),
      EntryRoutes.pair,
    ),
  };

  String? go(SessionState s, String location) =>
      redirectFor(s, Uri.parse(location));
  String pathOf(String? location) => Uri.parse(location!).path;

  group('no couple screen is reachable without a paired session', () {
    notPaired.forEach((name, testCase) {
      final (session, entry) = testCase;
      for (final area in ProductArea.values) {
        test('$name: ${area.path} → $entry', () {
          expect(pathOf(go(session, area.path)), entry);
        });
      }
      test('$name: unknown paths → $entry', () {
        expect(pathOf(go(session, '/admin/couples')), entry);
      });
      test('$name: stays on $entry', () {
        expect(go(session, entry), isNull);
      });
    });

    test('a query parameter cannot claim a couple', () {
      expect(
        pathOf(go(const SessionSignedOut(), '/home?paired=true&from=/home')),
        EntryRoutes.welcome,
      );
    });
  });

  group('paired', () {
    for (final area in ProductArea.values) {
      test('${area.path} is reachable', () {
        expect(go(pairedSession, area.path), isNull);
      });
    }

    test('entry routes lead home', () {
      for (final entry in [
        EntryRoutes.start,
        EntryRoutes.welcome,
        EntryRoutes.pair,
      ]) {
        expect(go(pairedSession, entry), ProductArea.home.path);
      }
    });

    test('unknown paths lead home', () {
      expect(go(pairedSession, '/nowhere'), ProductArea.home.path);
    });
  });

  group('deep links survive loading', () {
    test('an area opened while starting is remembered', () {
      final to = go(const SessionStarting(), ProductArea.moments.path);
      expect(to, '/start?from=%2Fmoments');
      expect(go(pairedSession, to!), ProductArea.moments.path);
    });

    test('only known areas are remembered', () {
      expect(go(const SessionStarting(), '/evil'), EntryRoutes.start);
      expect(
        go(pairedSession, '/start?from=https://example.com'),
        ProductArea.home.path,
      );
      expect(go(pairedSession, '/start?from=/pair'), ProductArea.home.path);
    });
  });
}
