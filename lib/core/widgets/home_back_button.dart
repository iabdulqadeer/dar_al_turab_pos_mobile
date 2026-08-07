import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../router/app_router.dart';

/// A back arrow for the bottom-nav tab roots (Sales, Printer, Profile).
///
/// These are branch roots, so there is nothing to pop — instead this returns to
/// the Dashboard (home) tab, giving every tab a consistent, discoverable way
/// back to the start, matching the app-bar back arrow on pushed screens.
class HomeBackButton extends StatelessWidget {
  const HomeBackButton({super.key});

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: const Icon(Icons.arrow_back),
      tooltip: 'Back to Dashboard',
      onPressed: () => context.go(Routes.dashboard),
    );
  }
}
