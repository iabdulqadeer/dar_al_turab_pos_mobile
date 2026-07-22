import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/config/app_config.dart';
import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';
import 'features/auth/providers/auth_providers.dart';
import 'features/branding/providers/branding_providers.dart';
import 'features/printing/providers/printer_providers.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ProviderScope(child: DarAlTurabPosApp()));
}

class DarAlTurabPosApp extends ConsumerStatefulWidget {
  const DarAlTurabPosApp({super.key});

  @override
  ConsumerState<DarAlTurabPosApp> createState() => _DarAlTurabPosAppState();
}

class _DarAlTurabPosAppState extends ConsumerState<DarAlTurabPosApp>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // The Bluetooth link drops when the app is backgrounded/closed or the phone
    // sleeps. Silently re-establish it on resume so the printer is ready.
    if (state == AppLifecycleState.resumed) {
      ref.read(printerControllerProvider.notifier).autoReconnect();
    }
  }

  @override
  Widget build(BuildContext context) {
    // Branding needs a token, so refresh it once the session is live. Listening
    // here (rather than inside the auth controller) keeps auth and branding
    // from importing each other.
    ref.listen<AuthState>(authControllerProvider, (previous, next) {
      if (next is AuthSignedIn && previous is! AuthSignedIn) {
        ref.read(brandingProvider.notifier).refresh();
      }
    });

    final router = ref.watch(routerProvider);

    return MaterialApp.router(
      title: AppConfig.appName,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: ThemeMode.system,
      routerConfig: router,
    );
  }
}
