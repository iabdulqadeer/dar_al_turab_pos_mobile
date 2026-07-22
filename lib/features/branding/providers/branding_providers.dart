import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../data/datasources/remote/settings_api.dart';
import '../../../data/models/brand_settings.dart';
import '../../auth/providers/auth_providers.dart';

final settingsApiProvider = Provider<SettingsApi>((ref) {
  return SettingsApi(ref.watch(apiClientProvider));
});

/// Company branding, cached on the device.
///
/// The endpoint needs a token, so a cold start (and the login screen, which has
/// no session yet) is served from the last cached copy. After sign-in the copy
/// is refreshed in the background, so changing branding on the website shows up
/// on the next launch without an app release.
///
/// State is null only until the cache is read and no branding has ever been
/// fetched — callers fall back to the bundled logo and constants.
class BrandingController extends Notifier<BrandSettings?> {
  static const _prefsKey = 'brand_settings';

  @override
  BrandSettings? build() {
    Future.microtask(_restore);
    return null;
  }

  Future<void> _restore() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);
    if (raw == null) return;

    try {
      state = BrandSettings.fromJson(
        Map<String, dynamic>.from(jsonDecode(raw) as Map),
      );
    } on Object {
      // Corrupt cache should never block the app; drop it and refetch later.
      await prefs.remove(_prefsKey);
    }
  }

  /// Fetches the latest branding and caches it. Best-effort: a failure keeps
  /// whatever is already cached rather than blanking the UI.
  Future<void> refresh() async {
    try {
      final settings = await ref.read(settingsApiProvider).general();
      state = settings;

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefsKey, jsonEncode(settings.toJson()));
    } on Object {
      // Offline or server error — keep the cached branding.
    }
  }
}

final brandingProvider =
    NotifierProvider<BrandingController, BrandSettings?>(
      BrandingController.new,
    );
