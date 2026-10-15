import 'package:go_router/go_router.dart';
import 'package:sirf_hum/app/product_area.dart';
import 'package:sirf_hum/app/shell/app_shell.dart';
import 'package:sirf_hum/app/shell/area_placeholder.dart';

/// URL-addressable routes so notifications and web links can deep-link into
/// any area. Auth/pairing redirects are added in the identity phase.
GoRouter buildRouter({String? initialLocation}) {
  return GoRouter(
    initialLocation: initialLocation ?? ProductArea.home.path,
    routes: [
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) =>
            AppShell(navigationShell: navigationShell),
        branches: [
          for (final area in ProductArea.values)
            StatefulShellBranch(
              routes: [
                GoRoute(
                  path: area.path,
                  builder: (context, state) => AreaPlaceholder(area: area),
                ),
              ],
            ),
        ],
      ),
    ],
  );
}
