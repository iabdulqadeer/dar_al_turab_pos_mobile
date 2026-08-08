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

  /// The permanent production endpoint. An alias of [apiBaseUrl] for call sites
  /// that want to be explicit that they mean "production, not the dev server".
  static const productionBaseUrl = apiBaseUrl;

  /// Seed value for the editable **dev** server URL in Server Settings. A dev
  /// machine's LAN IP changes across networks and restarts, so this is only a
  /// starting point — the field is editable at runtime.
  ///
  /// `10.0.2.2` is the Android emulator's alias for its host machine; on a
  /// physical test device replace it with the dev machine's LAN IP. Note the
  /// URL ends at `/api/` (no `v1`) because request paths already add `v1/`.
  static const defaultDevBaseUrl = String.fromEnvironment(
    'DEV_BASE_URL',
    defaultValue: 'http://10.0.2.2:8765/api/',
  );

  /// Whether the Dev/Production server toggle is present at all.
  ///
  /// Defaults to on so internal test builds carry it. Strip it from the build
  /// that ships to business staff — an accidental switch to an offline dev
  /// server would be confusing and hard to diagnose remotely — by building with
  /// `--dart-define=ENABLE_SERVER_TOGGLE=false`. When off, the app is locked to
  /// [productionBaseUrl] and the Server Settings entry is hidden.
  static const enableServerToggle = bool.fromEnvironment(
    'ENABLE_SERVER_TOGGLE',
    defaultValue: true,
  );

  /// Trailing slash matters: Dio joins relative paths against the base URL.
  static String normalizeBaseUrl(String url) {
    final trimmed = url.trim();
    if (trimmed.isEmpty) return apiBaseUrl;
    return trimmed.endsWith('/') ? trimmed : '$trimmed/';
  }
}

/// Which backend the app talks to. Dev is a local/LAN server entered by the
/// tester; production is the permanent [AppConfig.productionBaseUrl].
enum ServerMode { dev, production }
