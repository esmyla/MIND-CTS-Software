/// lib/routing/app_scaffold.dart
///
/// Main scaffold with 5-tab bottom navigation bar.
/// Tab order: Flexion | FSR Grip | Home (default) | PT Tracking | Pinch
library;

import 'package:flutter/material.dart';

import '../features/flexion/presentation/flexion_tab.dart';
import '../features/fsr_grip/presentation/fsr_grip_page.dart';
import '../features/home/presentation/home_screen.dart';
import '../features/pt_tracking/presentation/pt_tracking_page.dart';
import '../features/pinch_strength/presentation/pinch_strength_page.dart';

class AppScaffold extends StatefulWidget {
  const AppScaffold({super.key});

  @override
  State<AppScaffold> createState() => _AppScaffoldState();
}

class _AppScaffoldState extends State<AppScaffold> {
  // Home is the default tab (index 2).
  int _currentIndex = 2;

  static const List<_TabSpec> _tabs = [
    _TabSpec(
      label: 'Flexion',
      icon: Icons.fitness_center_rounded,
      activeIcon: Icons.fitness_center,
    ),
    _TabSpec(
      label: 'FSR Grip',
      icon: Icons.stacked_line_chart_rounded,
      activeIcon: Icons.stacked_line_chart,
    ),
    _TabSpec(
      label: 'Home',
      icon: Icons.home_outlined,
      activeIcon: Icons.home_rounded,
    ),
    _TabSpec(
      label: 'PT Tracking',
      icon: Icons.assignment_outlined,
      activeIcon: Icons.assignment_rounded,
    ),
    _TabSpec(
      label: 'Pinch',
      icon: Icons.touch_app_outlined,
      activeIcon: Icons.touch_app_rounded,
    ),
  ];

  /// Pages are built lazily and kept alive once visited.
  late final List<Widget> _pages = [
    const FlexionTab(),       // 0 — Flexion (existing, unmodified)
    const FsrGripPage(),      // 1 — FSR Grip (WIP)
    const HomeScreen(),       // 2 — Home dashboard (default)
    const PtTrackingPage(),   // 3 — PT Tracking (WIP)
    const PinchStrengthPage(), // 4 — Pinch Strength (WIP)
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: _pages,
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (i) {
          setState(() => _currentIndex = i);
          // TODO(analytics): Track nav_tab_changed event
        },
        destinations: _tabs.map((t) {
          return NavigationDestination(
            icon: Icon(t.icon),
            selectedIcon: Icon(t.activeIcon),
            label: t.label,
            tooltip: t.label,
          );
        }).toList(),
      ),
    );
  }
}

class _TabSpec {
  final String label;
  final IconData icon;
  final IconData activeIcon;

  const _TabSpec({
    required this.label,
    required this.icon,
    required this.activeIcon,
  });
}
