/// Build-time configuration.
///
/// The default now targets the **live production** API. For local development
/// against a dev backend, override the base URL at build time — the value is a
/// single config point, never scattered across screens.
abstract final class AppConfig {
  /// Where the API lives.
  ///
  /// Defaults to production. The endpoint paths the app sends already start with
  /// `v1/` (e.g. `v1/auth/login`), so the base URL ends at `/api/` — **without**
  /// a `v1` segment — otherwise requests would double up as `.../api/v1/v1/...`.
  /// The trailing slash matters: Dio joins the relative paths against it.
  ///
  /// Override for local dev, e.g.:
  ///   real LAN   --dart-define=API_BASE_URL=http://192.168.1.3/dar_al_turab_pos_1/public/api/
  ///   emulator   --dart-define=API_BASE_URL=http://10.0.2.2/dar_al_turab_pos_1/public/api/
  ///   adb tunnel --dart-define=API_BASE_URL=http://localhost:8080/dar_al_turab_pos_1/public/api/
  ///
  /// The login screen's "Server address" setting also lets a device point at a
  /// different host at runtime without rebuilding.
  static const apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'https://app.daralturabfoodstuff.com/api/',
  );

  static const appName = 'Dar Al Turab POS';

  /// Trailing slash matters: Dio joins relative paths against the base URL.
  static String normalizeBaseUrl(String url) {
    final trimmed = url.trim();
    if (trimmed.isEmpty) return apiBaseUrl;
    return trimmed.endsWith('/') ? trimmed : '$trimmed/';
  }
}
