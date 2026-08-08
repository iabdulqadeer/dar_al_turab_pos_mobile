import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/auth/providers/auth_providers.dart';
import '../theme/app_colors.dart';

/// Wraps the whole app so that, while the **dev** server is selected, a loud
/// strip sits above every screen. Without this someone testing can forget they
/// are pointed at a dev database and mistake it for live production data (or the
/// reverse) — the one thing this project keeps guarding against.
///
/// When production is selected (the normal case) it adds nothing and returns the
/// child untouched.
class DevModeBanner extends ConsumerWidget {
  const DevModeBanner({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(serverSettingsControllerProvider);
    if (!settings.isDev) return child;

    return Column(
      children: [
        Material(
          color: AppColors.warning,
          child: SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical: 6,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.warning_amber_rounded,
                      size: 16, color: Colors.black),
                  const SizedBox(width: AppSpacing.xs),
                  Flexible(
                    child: Text(
                      'DEV SERVER — ${settings.effectiveBaseUrl}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.black,
                        fontWeight: FontWeight.w800,
                        fontSize: 12,
                        letterSpacing: 0.3,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        // The strip already consumed the top status-bar inset; strip it from the
        // child so its Scaffolds don't add it a second time.
        Expanded(
          child: MediaQuery.removePadding(
            context: context,
            removeTop: true,
            child: child,
          ),
        ),
      ],
    );
  }
}
