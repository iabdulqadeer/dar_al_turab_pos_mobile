import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/app_config.dart';
import '../../../core/network/api_client.dart';
import '../../../data/datasources/local/secure_session_store.dart';
import '../../../data/datasources/remote/auth_api.dart';
import '../../../data/models/auth_user.dart';

final sessionStoreProvider = Provider<SecureSessionStore>((ref) {
  return SecureSessionStore();
});

final apiClientProvider = Provider<ApiClient>((ref) {
  final store = ref.watch(sessionStoreProvider);

  return ApiClient(
    baseUrl: AppConfig.apiBaseUrl,
    tokenProvider: store.readToken,
    onUnauthenticated: () async {
      // The server rejected our token (revoked, or the account was
      // deactivated). Drop it so the router redirects to login.
      await ref.read(authControllerProvider.notifier).forceSignOut();
    },
  );
});

final authApiProvider = Provider<AuthApi>((ref) {
  return AuthApi(ref.watch(apiClientProvider));
});

/// Session state. [AuthState.unknown] is the pre-restore state that keeps the
/// router on the splash screen until we know whether a stored token exists.
sealed class AuthState {
  const AuthState();
}

class AuthUnknown extends AuthState {
  const AuthUnknown();
}

class AuthSignedOut extends AuthState {
  const AuthSignedOut({this.message});

  /// Set when the session ended involuntarily (token revoked, account
  /// deactivated) so the login screen can explain why.
  final String? message;
}

class AuthSignedIn extends AuthState {
  const AuthSignedIn(this.user);

  final AuthUser user;
}

class AuthController extends Notifier<AuthState> {
  @override
  AuthState build() {
    return const AuthUnknown();
  }

  SecureSessionStore get _store => ref.read(sessionStoreProvider);
  AuthApi get _api => ref.read(authApiProvider);

  /// Restores a stored token on cold start and revalidates it against
  /// `/auth/me`. Revalidating (rather than trusting the cached token) matters
  /// because permissions and warehouse assignment can change server-side, and
  /// `EnsureUserIsActive` can revoke access at any time.
  Future<void> restore() async {
    if (AppConfig.enableServerToggle) {
      final baseUrl = await _store.readBaseUrl();
      if (baseUrl != null && baseUrl.isNotEmpty) {
        ref.read(apiClientProvider).baseUrl = baseUrl;
      }
    } else {
      // Locked build: ignore any stored override (e.g. a dev URL carried over
      // from a previous internal build) and pin to production.
      ref.read(apiClientProvider).baseUrl = AppConfig.productionBaseUrl;
    }

    final token = await _store.readToken();
    if (token == null || token.isEmpty) {
      state = const AuthSignedOut();
      return;
    }

    try {
      state = AuthSignedIn(await _api.me());
    } on Object {
      // Any failure here (revoked token, inactive account, unreachable
      // server) lands the user on login rather than a broken shell.
      await _store.clearToken();
      state = const AuthSignedOut();
    }
  }

  Future<void> signIn({
    required String login,
    required String password,
  }) async {
    final result = await _api.login(
      login: login,
      password: password,
      deviceName: await _deviceName(),
    );

    await _store.writeToken(result.token);
    state = AuthSignedIn(result.user);
  }

  Future<void> signOut() async {
    try {
      await _api.logout();
    } on Object {
      // Best effort: if the network is down we still clear locally. The
      // server-side token is then orphaned until revoked from device
      // management, which is an accepted trade-off versus trapping the user
      // in a session they asked to leave.
    }
    await _store.clearToken();
    state = const AuthSignedOut();
  }

  /// Called by the API client when a request comes back 401.
  Future<void> forceSignOut() async {
    if (state is AuthSignedOut) return;
    await _store.clearToken();
    state = const AuthSignedOut(
      message: 'Your session has ended. Please sign in again.',
    );
  }

  /// Refreshes the cached user, e.g. after a profile edit.
  Future<void> refreshUser() async {
    if (state is! AuthSignedIn) return;
    try {
      state = AuthSignedIn(await _api.me());
    } on Object {
      // Keep the existing user rather than dropping the session on a
      // transient refresh failure.
    }
  }

  /// Ends the session after a server switch. A token issued by one server's
  /// database is meaningless against another, so switching must never carry a
  /// stale token across — clear it and send the user back to login.
  Future<void> switchServer() async {
    await _store.clearToken();
    state = const AuthSignedOut(
      message: 'Server changed. Please sign in again.',
    );
  }

  /// Sanctum names the token after the device, which is what a future device
  /// management screen will list, so make it recognisable.
  Future<String> _deviceName() async {
    final plugin = DeviceInfoPlugin();
    try {
      if (kIsWeb) {
        final info = await plugin.webBrowserInfo;
        return '${info.browserName.name} (web)';
      }
      switch (defaultTargetPlatform) {
        case TargetPlatform.android:
          final info = await plugin.androidInfo;
          return '${info.manufacturer} ${info.model} '
              '(Android ${info.version.release})';
        case TargetPlatform.iOS:
          final info = await plugin.iosInfo;
          return '${info.name} (iOS ${info.systemVersion})';
        case _:
          break;
      }
    } on Object {
      // Fall through to the generic name below.
    }
    return 'Dar Al Turab POS mobile';
  }
}

final authControllerProvider = NotifierProvider<AuthController, AuthState>(
  AuthController.new,
);

/// The signed-in user, or null. Convenience for permission checks in widgets.
final currentUserProvider = Provider<AuthUser?>((ref) {
  final state = ref.watch(authControllerProvider);
  return state is AuthSignedIn ? state.user : null;
});

/// Whether the current user holds [permission]. Returns false when signed out.
final hasPermissionProvider = Provider.family<bool, String>((ref, permission) {
  return ref.watch(currentUserProvider)?.can(permission) ?? false;
});

/// The selected server (dev vs production) and both editable URLs. Persisted,
/// so it survives a restart, and mirrored onto the Dio client's base URL.
class ServerSettings {
  const ServerSettings({
    required this.mode,
    required this.devBaseUrl,
    required this.prodBaseUrl,
  });

  final ServerMode mode;
  final String devBaseUrl;
  final String prodBaseUrl;

  bool get isDev => mode == ServerMode.dev;

  /// The URL requests actually go to for this selection. Both URLs are editable;
  /// an empty one falls back to the production default via [normalizeBaseUrl].
  String get effectiveBaseUrl => mode == ServerMode.dev
      ? AppConfig.normalizeBaseUrl(devBaseUrl)
      : AppConfig.normalizeBaseUrl(prodBaseUrl);

  /// The URL entered for [mode] — what "Test connection" should probe.
  String get selectedUrl => mode == ServerMode.dev ? devBaseUrl : prodBaseUrl;

  ServerSettings copyWith({
    ServerMode? mode,
    String? devBaseUrl,
    String? prodBaseUrl,
  }) =>
      ServerSettings(
        mode: mode ?? this.mode,
        devBaseUrl: devBaseUrl ?? this.devBaseUrl,
        prodBaseUrl: prodBaseUrl ?? this.prodBaseUrl,
      );
}

class ServerSettingsController extends Notifier<ServerSettings> {
  @override
  ServerSettings build() {
    // Start on the safe side; _load() replaces this with the stored choice.
    // In a locked build the toggle is absent, so we stay pinned to production.
    if (AppConfig.enableServerToggle) {
      _load();
    }
    return const ServerSettings(
      mode: ServerMode.production,
      devBaseUrl: AppConfig.defaultDevBaseUrl,
      prodBaseUrl: AppConfig.productionBaseUrl,
    );
  }

  SecureSessionStore get _store => ref.read(sessionStoreProvider);

  Future<void> _load() async {
    final mode = await _store.readServerMode();
    final devUrl = await _store.readDevBaseUrl() ?? AppConfig.defaultDevBaseUrl;
    final prodUrl =
        await _store.readProdBaseUrl() ?? AppConfig.productionBaseUrl;
    state = ServerSettings(
      mode: mode,
      devBaseUrl: devUrl,
      prodBaseUrl: prodUrl,
    );
  }

  /// Persists the chosen server + both URLs, points Dio at the effective one,
  /// and — because tokens are not portable between servers — clears the session
  /// and forces re-login whenever the effective URL actually changes.
  Future<void> save({
    required ServerMode mode,
    required String devBaseUrl,
    required String prodBaseUrl,
  }) async {
    final normalizedDev = AppConfig.normalizeBaseUrl(devBaseUrl);
    final normalizedProd = AppConfig.normalizeBaseUrl(prodBaseUrl);
    final next = ServerSettings(
      mode: mode,
      devBaseUrl: normalizedDev,
      prodBaseUrl: normalizedProd,
    );
    final changed = next.effectiveBaseUrl != state.effectiveBaseUrl;

    await _store.writeServerMode(mode);
    await _store.writeDevBaseUrl(normalizedDev);
    await _store.writeProdBaseUrl(normalizedProd);
    await _store.writeBaseUrl(next.effectiveBaseUrl);
    ref.read(apiClientProvider).baseUrl = next.effectiveBaseUrl;
    state = next;

    if (changed) {
      await ref.read(authControllerProvider.notifier).switchServer();
    }
  }
}

final serverSettingsControllerProvider =
    NotifierProvider<ServerSettingsController, ServerSettings>(
      ServerSettingsController.new,
    );
