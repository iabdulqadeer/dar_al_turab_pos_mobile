import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/models/auth_user.dart';
import '../../features/auth/providers/auth_providers.dart';
import '../router/app_router.dart';

/// Bottom-navigation shell wrapping the primary destinations.
///
/// Uses go_router's [StatefulNavigationShell] so each tab keeps its own
/// navigation stack and scroll position — switching away from a filtered sales
/// list and back should not reset it.
class AppShell extends ConsumerWidget {
  const AppShell({required this.navigationShell, super.key});

  final StatefulNavigationShell navigationShell;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);
    final canCreateSale = user?.can(Permissions.salesAdd) ?? false;

    return Scaffold(
      body: navigationShell,
      floatingActionButton: canCreateSale
          ? FloatingActionButton.extended(
              onPressed: () => context.push(Routes.pos),
              icon: const Icon(Icons.add_shopping_cart),
              label: const Text('New sale'),
            )
          : null,
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
