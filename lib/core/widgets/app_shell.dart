import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

/// Bottom-navigation shell wrapping the primary destinations.
///
/// Uses go_router's [StatefulNavigationShell] so each tab keeps its own
/// navigation stack and scroll position — switching away from a filtered sales
/// list and back should not reset it.
///
/// Deliberately owns no floating action button. A FAB here is visible on every
/// screen inside every branch, including pushed ones like a sale's detail page,
/// and the shell cannot tell them apart: `GoRouterState.of(context)` resolves
/// against the shell's own route match (`/sales`), not the route pushed inside
/// the branch navigator (`/sales/123`). The screens that want a FAB declare it
/// on their own Scaffold instead.
class AppShell extends StatelessWidget {
  const AppShell({required this.navigationShell, super.key});

  final StatefulNavigationShell navigationShell;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: navigationShell,
      bottomNavigationBar: NavigationBar(
        selectedIndex: navigationShell.currentIndex,
        onDestinationSelected: _onDestinationSelected,
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.dashboard_outlined),
            selectedIcon: Icon(Icons.dashboard),
            label: 'Dashboard',
          ),
          NavigationDestination(
            icon: Icon(Icons.receipt_long_outlined),
            selectedIcon: Icon(Icons.receipt_long),
            label: 'Sales',
          ),
          NavigationDestination(
            icon: Icon(Icons.print_outlined),
            selectedIcon: Icon(Icons.print),
            label: 'Printer',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline),
            selectedIcon: Icon(Icons.person),
            label: 'Profile',
          ),
        ],
      ),
    );
  }

  void _onDestinationSelected(int index) {
    HapticFeedback.selectionClick();

    // Tapping the active tab pops it back to its root, which is the standard
    // behaviour users expect from a bottom bar.
    navigationShell.goBranch(
      index,
      initialLocation: index == navigationShell.currentIndex,
    );
  }
}
