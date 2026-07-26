import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../auth/providers/auth_providers.dart';
import '../../branding/presentation/brand_logo.dart';

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
    // The splash is always light to match the native splash and the app's light
    // default, so the colour emblem always sits on white and reads well.
    return Scaffold(
      backgroundColor: AppColors.lightSurface,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const BrandLogo(width: 200, onDark: false),
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
