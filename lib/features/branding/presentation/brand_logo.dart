import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/branding_providers.dart';

/// The company logo, taken from the web admin when available.
///
/// Falls back to the bundled asset whenever there is no cached branding yet,
/// no logo has been uploaded, or the URL fails to load — the server does not
/// verify the file exists, so a 404 is an expected case rather than an error.
class BrandLogo extends ConsumerWidget {
  const BrandLogo({required this.width, this.onDark = false, super.key});

  final double width;

  /// Use the mono-white artwork; the emblem is black-on-white line art and
  /// disappears against a dark surface.
  final bool onDark;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final logoUrl = ref.watch(brandingProvider)?.systemLogo;

    final fallback = Image.asset(
      onDark
          ? 'assets/brand/logo_mono_light.png'
          : 'assets/brand/logo.png',
      width: width,
      errorBuilder: (_, _, _) => Icon(
        Icons.storefront_outlined,
        size: width * 0.3,
        color: Theme.of(context).colorScheme.primary,
      ),
    );

    if (logoUrl == null) return fallback;

    return Image.network(
      logoUrl,
      width: width,
      // A remote logo on a dark surface can be unreadable if it is dark
      // artwork, but we cannot know — show it as-is and let the admin pick a
      // logo that works, exactly as the website does.
      errorBuilder: (_, _, _) => fallback,
      loadingBuilder: (context, child, progress) {
        if (progress == null) return child;
        // Reserve the same box so the layout does not jump when it arrives.
        return SizedBox(
          width: width,
          height: width * 0.5,
          child: const Center(
            child: SizedBox(
              height: 18,
              width: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
        );
      },
    );
  }
}
