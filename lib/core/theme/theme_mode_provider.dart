import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The user's chosen theme, persisted across restarts.
///
/// Mirrors the printer/branding provider pattern: the saved value is restored
/// asynchronously via `Future.microtask(_restore)` so it never blocks first
/// paint. Until the restore completes the app shows [ThemeMode.light], which is
/// also the default when nothing has been saved.
class ThemeModeController extends Notifier<ThemeMode> {
  static const _prefsKey = 'theme_mode';

  /// Shown on first launch and used as the fallback for an unreadable value.
  static const _default = ThemeMode.light;

  @override
  ThemeMode build() {
    Future.microtask(_restore);
    return _default;
  }

  Future<void> _restore() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);
    if (raw == null) return;

    state = _fromName(raw);
  }

  /// Updates the mode immediately and persists the choice.
  Future<void> setMode(ThemeMode mode) async {
    if (mode == state) return;
    state = mode;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, mode.name);
  }

  static ThemeMode _fromName(String name) => switch (name) {
    'light' => ThemeMode.light,
    'dark' => ThemeMode.dark,
    'system' => ThemeMode.system,
    _ => _default,
  };
}

final themeModeProvider = NotifierProvider<ThemeModeController, ThemeMode>(
  ThemeModeController.new,
);
