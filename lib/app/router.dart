import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';
import 'package:sirf_hum/app/entry/auth_link_screen.dart';
import 'package:sirf_hum/app/entry/pair_screen.dart';
import 'package:sirf_hum/app/entry/start_screen.dart';
import 'package:sirf_hum/app/entry/welcome_screen.dart';
import 'package:sirf_hum/app/product_area.dart';
import 'package:sirf_hum/app/shell/app_shell.dart';
import 'package:sirf_hum/features/future/presentation/future_screen.dart';
import 'package:sirf_hum/features/home/presentation/home_screen.dart';
import 'package:sirf_hum/features/moments/presentation/moments_screen.dart';
import 'package:sirf_hum/features/together/presentation/together_screen.dart';
import 'package:sirf_hum/features/us/presentation/us_screen.dart';
import 'package:sirf_hum/security/account/email_link_sign_in.dart';
import 'package:sirf_hum/session/session_state.dart';

/// Routes outside the five-area shell, for everyone who is not (yet) a
/// paired, signed-in couple (D-108).
abstract final class EntryRoutes {
  static const start = '/start';
  static const welcome = '/welcome';
  static const pair = '/pair';

  /// Email sign-in App Links (D-138): `/__/auth/links`, `/__/auth/action`.
  static const authLink = '$authLinkPathPrefix:action';

  /// The area a deep link asked for, carried through [start].
  static const fromParameter = 'from';
}

/// Where [session] may be, given the requested [location]; null to stay.
///
/// This is navigation, not authorization: the server decides what each
/// account may read (rules, callables). It guarantees the shell — and with
/// it every couple screen — renders only for a [SessionPaired] produced by
/// the session controller, whatever URL or deep link was opened.
String? redirectFor(SessionState session, Uri location) {
  final path = location.path;
  final entry = switch (session) {
    SessionStarting() || SessionUnavailable() => EntryRoutes.start,
    SessionSignedOut() => EntryRoutes.welcome,
    SessionNotPaired() || SessionPairing() => EntryRoutes.pair,
    SessionPaired() => null,
  };

  // A sign-in link is kept while signed out or still starting (a cold start
  // from the email); once signed in it is ignored like any other entry URL.
  if (path.startsWith(authLinkPathPrefix) &&
      (session is SessionSignedOut || session is SessionStarting)) {
    return null;
  }
  if (entry == null) {
    if (ProductArea.fromPath(path) != null) return null;
    final from = location.queryParameters[EntryRoutes.fromParameter];
    return ProductArea.fromPath(from)?.path ?? ProductArea.home.path;
  }
  if (path == entry) return null;
  // Keep a deep-linked area while the session loads (a notification opening
  // Moments should land on Moments). Only known area paths survive.
  final area =
      ProductArea.fromPath(path) ??
      ProductArea.fromPath(location.queryParameters[EntryRoutes.fromParameter]);
  if (entry == EntryRoutes.start && area != null) {
    return Uri(
      path: EntryRoutes.start,
      queryParameters: {EntryRoutes.fromParameter: area.path},
    ).toString();
  }
  return entry;
}

/// URL-addressable routes so notifications and web links can deep-link into
/// any area. [session] is read on every navigation and whenever [refresh]
/// fires (the session changed).
GoRouter buildRouter({
  required SessionState Function() session,
  required Listenable refresh,
  String? initialLocation,
}) {
  return GoRouter(
    initialLocation: initialLocation ?? ProductArea.home.path,
    refreshListenable: refresh,
    redirect: (context, state) => redirectFor(session(), state.uri),
    routes: [
      GoRoute(
        path: EntryRoutes.start,
        builder: (context, state) => const StartScreen(),
      ),
      GoRoute(
        path: EntryRoutes.welcome,
        builder: (context, state) => const WelcomeScreen(),
      ),
      GoRoute(
        path: EntryRoutes.authLink,
        builder: (context, state) => AuthLinkScreen(location: state.uri),
      ),
      GoRoute(
        path: EntryRoutes.pair,
        builder: (context, state) => const PairScreen(),
      ),
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) =>
            AppShell(navigationShell: navigationShell),
        branches: [
          for (final area in ProductArea.values)
            StatefulShellBranch(
              routes: [
                GoRoute(
                  path: area.path,
                  builder: (context, state) => _areaScreen(context, area),
                ),
              ],
            ),
        ],
      ),
    ],
  );
}

Widget _areaScreen(BuildContext context, ProductArea area) => switch (area) {
  ProductArea.home => HomeScreen(
    onOpenTogether: () => context.go(ProductArea.together.path),
    onOpenMoments: () => context.go(ProductArea.moments.path),
    onOpenFuture: () => context.go(ProductArea.future.path),
    onOpenUs: () => context.go(ProductArea.us.path),
  ),
  ProductArea.together => TogetherScreen(
    onOpenFuture: () => context.go(ProductArea.future.path),
    onOpenUs: () => context.go(ProductArea.us.path),
  ),
  ProductArea.moments => const MomentsScreen(),
  ProductArea.future => const FutureScreen(),
  ProductArea.us => const UsScreen(),
};
