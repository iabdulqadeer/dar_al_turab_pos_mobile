import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../auth/providers/auth_providers.dart';

/// Shown while the stored token is restored and revalidated against
/// `/auth/me`. The router keeps us here until auth state resolves.
class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen> {
  @override
  void initState() {
    super.initState();
    // Deferred to the first frame: restore() mutates provider state, which
    // must not happen during widget construction.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(authControllerProvider.notifier).restore();
    });
  }

  @override
  Widget build(BuildContext context) {
    // The emblem is drawn on white, so on a dark surface it needs the
    // mono-white variant or the black arcs and wordmark vanish.
    final onDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.asset(
              onDark
                  ? 'assets/brand/logo_mono_light.png'
                  : 'assets/brand/logo.png',
              width: 200,
              // The launcher already showed the mark; if the asset is missing
              // the app should still boot rather than throw on a grey screen.
              errorBuilder: (_, _, _) => const Icon(
                Icons.storefront_outlined,
                size: 56,
                color: AppColors.primary,
              ),
            ),
            const SizedBox(height: AppSpacing.xl),
            const SizedBox(
              height: 24,
              width: 24,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ],
        ),
      ),
    );
  }
}
