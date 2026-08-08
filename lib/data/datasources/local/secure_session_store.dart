import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../../core/config/app_config.dart';

/// Persists the Sanctum bearer token and the API base URL.
///
/// The token is stored in the platform keystore rather than
/// SharedPreferences because Sanctum tokens here never expire
/// (`config/sanctum.php` sets `'expiration' => null`), so a leaked token is
/// valid indefinitely.
class SecureSessionStore {
  SecureSessionStore({FlutterSecureStorage? storage})
    : _storage =
          storage ??
          const FlutterSecureStorage(
            iOptions: IOSOptions(
              accessibility: KeychainAccessibility.first_unlock,
            ),
          );

  static const _tokenKey = 'auth_token';
  static const _baseUrlKey = 'api_base_url';
  static const _serverModeKey = 'server_mode';
  static const _devBaseUrlKey = 'dev_base_url';

  final FlutterSecureStorage _storage;

  // Cached so the Dio request interceptor stays synchronous-fast on the hot
  // path instead of hitting the keystore on every single request.
  String? _cachedToken;
  bool _tokenLoaded = false;

  Future<String?> readToken() async {
    if (_tokenLoaded) return _cachedToken;
    _cachedToken = await _storage.read(key: _tokenKey);
    _tokenLoaded = true;
    return _cachedToken;
  }

  Future<void> writeToken(String token) async {
    _cachedToken = token;
    _tokenLoaded = true;
    await _storage.write(key: _tokenKey, value: token);
  }

  Future<void> clearToken() async {
    _cachedToken = null;
    _tokenLoaded = true;
    await _storage.delete(key: _tokenKey);
  }

  Future<String?> readBaseUrl() => _storage.read(key: _baseUrlKey);

  Future<void> writeBaseUrl(String url) =>
      _storage.write(key: _baseUrlKey, value: url);

  /// The selected server mode. Defaults to [ServerMode.production] when nothing
  /// has been chosen — the safe side, so a fresh install never silently starts
  /// against a dev server.
  Future<ServerMode> readServerMode() async {
    final value = await _storage.read(key: _serverModeKey);
    return value == 'dev' ? ServerMode.dev : ServerMode.production;
  }

  Future<void> writeServerMode(ServerMode mode) => _storage.write(
    key: _serverModeKey,
    value: mode == ServerMode.dev ? 'dev' : 'production',
  );

  /// The editable dev server URL. Null until the tester saves one.
  Future<String?> readDevBaseUrl() => _storage.read(key: _devBaseUrlKey);

  Future<void> writeDevBaseUrl(String url) =>
      _storage.write(key: _devBaseUrlKey, value: url);
}
