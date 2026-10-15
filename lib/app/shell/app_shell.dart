import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:sirf_hum/app/product_area.dart';
import 'package:sirf_hum/design_system/design_system.dart';

/// Adaptive navigation frame: a bottom bar on phones (thumb reach), a rail on
/// wider windows (tablet, web).
class AppShell extends StatelessWidget {
  const AppShell({required this.navigationShell, super.key});

  final StatefulNavigationShell navigationShell;

  void _select(int index) {
    navigationShell.goBranch(
      index,
      // Re-selecting the current area returns to its root.
      initialLocation: index == navigationShell.currentIndex,
    );
  }

  @override
  Widget build(BuildContext context) {
    const areas = ProductArea.values;
    final selected = navigationShell.currentIndex;

    if (WindowSize.of(context) == WindowSize.compact) {
      return Scaffold(
        body: navigationShell,
        bottomNavigationBar: NavigationBar(
          selectedIndex: selected,
          onDestinationSelected: _select,
          destinations: [
            for (final area in areas)
              NavigationDestination(
                icon: Icon(area.icon),
                selectedIcon: Icon(area.selectedIcon),
                label: area.label,
              ),
          ],
        ),
      );
    }

    return Scaffold(
      body: Row(
        children: [
          NavigationRail(
            selectedIndex: selected,
            onDestinationSelected: _select,
            labelType: NavigationRailLabelType.all,
            backgroundColor: context.colors.background,
            destinations: [
              for (final area in areas)
                NavigationRailDestination(
                  icon: Icon(area.icon),
                  selectedIcon: Icon(area.selectedIcon),
                  label: Text(area.label),
                ),
            ],
          ),
          VerticalDivider(width: 1, color: context.colors.border),
          Expanded(child: navigationShell),
        ],
      ),
    );
  }
}
