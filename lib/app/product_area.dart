import 'package:flutter/material.dart';

/// The five primary areas of Sirf Hum (docs/product/PRODUCT-CONSTITUTION.md).
///
/// The bottom navigation, in order (D-108). Icons are Material outlines until
/// the identity phase picks an icon set. "Our Money" is deliberately absent:
/// it is a future, separately reviewed area and not part of V1.
enum ProductArea {
  home(
    path: '/home',
    label: 'Home',
    purpose: 'Your shared front door.',
    icon: Icons.home_outlined,
    selectedIcon: Icons.home,
  ),
  together(
    path: '/together',
    label: 'Together',
    purpose: 'Spend time together, wherever you are.',
    icon: Icons.people_outline,
    selectedIcon: Icons.people,
  ),
  moments(
    path: '/moments',
    label: 'Moments',
    purpose: 'Your memories, just for the two of you.',
    icon: Icons.photo_library_outlined,
    selectedIcon: Icons.photo_library,
  ),
  future(
    path: '/future',
    label: 'Future',
    purpose: 'Plan something together.',
    icon: Icons.explore_outlined,
    selectedIcon: Icons.explore,
  ),
  us(
    path: '/us',
    label: 'Us',
    purpose: 'The two of you.',
    icon: Icons.all_inclusive_outlined,
    selectedIcon: Icons.all_inclusive,
  );

  const ProductArea({
    required this.path,
    required this.label,
    required this.purpose,
    required this.icon,
    required this.selectedIcon,
  });

  final String path;
  final String label;
  final String purpose;
  final IconData icon;
  final IconData selectedIcon;

  /// The area whose root is exactly [path], or null.
  static ProductArea? fromPath(String? path) {
    for (final area in values) {
      if (area.path == path) return area;
    }
    return null;
  }
}
