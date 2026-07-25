import 'package:dar_al_turab_pos/core/theme/theme_mode_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('defaults to system when nothing is saved', () async {
    SharedPreferences.setMockInitialValues({});
    final container = ProviderContainer();
    addTearDown(container.dispose);

    expect(container.read(themeModeProvider), ThemeMode.system);
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

  test('restores a saved mode on build', () async {
    SharedPreferences.setMockInitialValues({'theme_mode': 'light'});
    final container = ProviderContainer();
    // Keep it alive and let the async restore settle before asserting.
    container.listen(themeModeProvider, (_, _) {});
    addTearDown(container.dispose);

    final mode = await _settled(container, until: ThemeMode.light);

    expect(mode, ThemeMode.light);
  });

  test('a corrupt/unknown saved value falls back to system', () async {
    SharedPreferences.setMockInitialValues({'theme_mode': 'garbage'});
    final container = ProviderContainer();
    container.listen(themeModeProvider, (_, _) {});
    addTearDown(container.dispose);

    // Let any pending restore run, then confirm it stayed on the fallback.
    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(container.read(themeModeProvider), ThemeMode.system);
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
