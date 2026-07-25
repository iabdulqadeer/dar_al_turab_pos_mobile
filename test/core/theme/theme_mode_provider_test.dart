import 'package:dar_al_turab_pos/core/theme/theme_mode_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('defaults to light when nothing is saved', () async {
    SharedPreferences.setMockInitialValues({});
    final container = ProviderContainer();
    addTearDown(container.dispose);

    expect(container.read(themeModeProvider), ThemeMode.light);
  });

  test('restores an explicitly saved system mode', () async {
    SharedPreferences.setMockInitialValues({'theme_mode': 'system'});
    final container = ProviderContainer();
    container.listen(themeModeProvider, (_, _) {});
    addTearDown(container.dispose);

    final mode = await _settled(container, until: ThemeMode.system);

    expect(mode, ThemeMode.system);
  });

  test('setMode updates state and persists the choice', () async {
    SharedPreferences.setMockInitialValues({});
    final container = ProviderContainer();
    addTearDown(container.dispose);

    await container.read(themeModeProvider.notifier).setMode(ThemeMode.dark);

    expect(container.read(themeModeProvider), ThemeMode.dark);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('theme_mode'), 'dark');
  });

  test('restores a saved non-default mode on build', () async {
    // Saved value differs from the light default, so this proves restoration.
    SharedPreferences.setMockInitialValues({'theme_mode': 'dark'});
    final container = ProviderContainer();
    // Keep it alive and let the async restore settle before asserting.
    container.listen(themeModeProvider, (_, _) {});
    addTearDown(container.dispose);

    final mode = await _settled(container, until: ThemeMode.dark);

    expect(mode, ThemeMode.dark);
  });

  test('a corrupt/unknown saved value falls back to the light default', () async {
    SharedPreferences.setMockInitialValues({'theme_mode': 'garbage'});
    final container = ProviderContainer();
    container.listen(themeModeProvider, (_, _) {});
    addTearDown(container.dispose);

    // Let any pending restore run, then confirm it stayed on the fallback.
    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(container.read(themeModeProvider), ThemeMode.light);
  });
}

/// Waits for the provider's async restore to reach [until] (or times out),
/// so the test does not race the `Future.microtask(_restore)` chain.
Future<ThemeMode> _settled(
  ProviderContainer container, {
  required ThemeMode until,
}) async {
  var mode = container.read(themeModeProvider);
  for (var i = 0; i < 50 && mode != until; i++) {
    await Future<void>.delayed(const Duration(milliseconds: 5));
    mode = container.read(themeModeProvider);
  }
  return mode;
}
