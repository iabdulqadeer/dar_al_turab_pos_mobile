import 'package:flutter/material.dart';

/// Brand palette, mirrored from the Dar Al Turab web POS so the mobile app
/// reads as the same product.
///
/// Sources: `public/css/custom-default.css` (primary purple, 71 occurrences)
/// and `public/css/auth.css` (login accent) in the Laravel project.
abstract final class AppColors {
  // Core brand
  static const primary = Color(0xFF7C5CC4);
  static const primaryDark = Color(0xFF6244A6);
  static const secondary = Color(0xFF7C70F4);
  static const primaryContainer = Color(0xFFE4E6FC);
  static const primaryContainerAlt = Color(0xFFD6DEFF);

  // Status
  static const success = Color(0xFF34CEA7);
  static const warning = Color(0xFFEB543A);
  static const error = Color(0xFFFF6B6B);
  static const errorAlt = Color(0xFFFF7588);

  // Light surfaces
  static const lightBackground = Color(0xFFF7F7F7);
  static const lightSurface = Color(0xFFFFFFFF);
  static const lightOutline = Color(0xFFEBE9F1);
  static const lightOutlineStrong = Color(0xFFD0D2D6);
  static const lightTextPrimary = Color(0xFF5E5873);
  static const lightTextSecondary = Color(0xFF6E6B7B);

  // Dark surfaces
  static const darkBackground = Color(0xFF141B2E);
  static const darkSurface = Color(0xFF283046);
  static const darkSurfaceAlt = Color(0xFF343D55);
  static const darkOutline = Color(0xFF3B4253);
  static const darkTextPrimary = Color(0xFFD0D2D6);
  static const darkTextSecondary = Color(0xFFB4B7BD);
}

/// 8pt spacing scale. Use these instead of raw numbers so density stays
/// consistent across screens.
abstract final class AppSpacing {
  static const xs = 4.0;
  static const sm = 8.0;
  static const md = 16.0;
  static const lg = 24.0;
  static const xl = 32.0;
  static const xxl = 48.0;

  /// Minimum touch target for warehouse use (gloves, movement).
  static const minTouchTarget = 48.0;
}

abstract final class AppRadius {
  static const sm = 6.0;
  static const md = 10.0;
  static const lg = 16.0;
  static const pill = 999.0;
}
