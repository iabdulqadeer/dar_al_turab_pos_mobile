import 'package:flutter_secure_storage/flutter_secure_storage.dart';

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
}
