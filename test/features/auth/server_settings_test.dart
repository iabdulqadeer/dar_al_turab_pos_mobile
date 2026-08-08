import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dar_al_turab_pos/core/config/app_config.dart';
import 'package:dar_al_turab_pos/data/datasources/local/secure_session_store.dart';
import 'package:dar_al_turab_pos/features/auth/providers/auth_providers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // In-memory stand-in for the platform keystore so SecureSessionStore can be
  // exercised without a device.
  late Map<String, String> storage;

  setUp(() {
    storage = {};
    const channel = MethodChannel(
      'plugins.it_nomads.com/flutter_secure_storage',
    );
    TestDefaultBinaryMessengerBinding
        .instance
        .defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          final args = (call.arguments as Map?)?.cast<String, dynamic>() ?? {};
          switch (call.method) {
            case 'write':
              storage[args['key'] as String] = args['value'] as String;
              return null;
            case 'read':
              return storage[args['key'] as String];
            case 'delete':
              storage.remove(args['key'] as String);
              return null;
            case 'readAll':
              return storage;
            case 'containsKey':
              return storage.containsKey(args['key'] as String);
            default:
              return null;
          }
        });
  });

  group('ServerSettings.effectiveBaseUrl', () {
    test('dev mode uses the dev URL, normalised with a trailing slash', () {
      const settings = ServerSettings(
        mode: ServerMode.dev,
        devBaseUrl: 'http://10.0.2.2:8765/api',
      );
      expect(settings.isDev, isTrue);
      expect(settings.effectiveBaseUrl, 'http://10.0.2.2:8765/api/');
    });

    test('production mode ignores the dev URL and uses production', () {
      const settings = ServerSettings(
        mode: ServerMode.production,
        devBaseUrl: 'http://10.0.2.2:8765/api',
      );
      expect(settings.isDev, isFalse);
      expect(settings.effectiveBaseUrl, AppConfig.productionBaseUrl);
    });
  });

  group('SecureSessionStore server mode', () {
    test('defaults to production before anything is saved', () async {
      final store = SecureSessionStore();
      expect(await store.readServerMode(), ServerMode.production);
      expect(await store.readDevBaseUrl(), isNull);
    });

    test('round-trips the saved mode and dev URL', () async {
      final store = SecureSessionStore();
      await store.writeServerMode(ServerMode.dev);
      await store.writeDevBaseUrl('http://192.168.1.5:8765/api/');
      expect(await store.readServerMode(), ServerMode.dev);
      expect(await store.readDevBaseUrl(), 'http://192.168.1.5:8765/api/');
    });
  });

  group('ServerSettingsController.save', () {
    test('switching to dev persists, points Dio at it, and signs out',
        () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      // Seed a token so the switch has something to clear.
      await container.read(sessionStoreProvider).writeToken('old-token');

      await container
          .read(serverSettingsControllerProvider.notifier)
          .save(mode: ServerMode.dev, devBaseUrl: 'http://10.0.2.2:8765/api');

      final settings = container.read(serverSettingsControllerProvider);
      expect(settings.mode, ServerMode.dev);
      expect(settings.effectiveBaseUrl, 'http://10.0.2.2:8765/api/');

      // Effective URL was persisted for restore() and applied to Dio.
      expect(storage['api_base_url'], 'http://10.0.2.2:8765/api/');
      expect(
        container.read(apiClientProvider).raw.options.baseUrl,
        'http://10.0.2.2:8765/api/',
      );

      // Session was cleared and the user bounced to login.
      expect(await container.read(sessionStoreProvider).readToken(), isNull);
      expect(container.read(authControllerProvider), isA<AuthSignedOut>());
    });

    test('switching back to production restores the production URL', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final controller =
          container.read(serverSettingsControllerProvider.notifier);
      await controller.save(
        mode: ServerMode.dev,
        devBaseUrl: 'http://10.0.2.2:8765/api',
      );
      await controller.save(
        mode: ServerMode.production,
        devBaseUrl: 'http://10.0.2.2:8765/api',
      );

      expect(
        container.read(serverSettingsControllerProvider).effectiveBaseUrl,
        AppConfig.productionBaseUrl,
      );
      expect(storage['api_base_url'], AppConfig.productionBaseUrl);
      expect(
        container.read(apiClientProvider).raw.options.baseUrl,
        AppConfig.productionBaseUrl,
      );
    });
  });
}
