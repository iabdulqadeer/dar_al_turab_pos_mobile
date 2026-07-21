/// Build-time configuration.
///
/// Override at build time, e.g.
/// `flutter run --dart-define=API_BASE_URL=http://192.168.1.20/dar_al_turab_pos_1/public/api/`
///
/// The default targets a WAMP instance on the host machine as seen from an
/// Android emulator (10.0.2.2 maps to the host's localhost). A physical
/// device on the same LAN needs the machine's real IP instead, which the
/// settings screen lets the user set at runtime.
abstract final class AppConfig {
  /// Where the API lives.
  ///
  /// The default assumes an `adb reverse tcp:8080 tcp:80` tunnel, which
  /// forwards the phone's localhost:8080 to the development machine's port 80
  /// over USB. That path avoids Wi-Fi and Windows Firewall entirely — without
  /// an inbound rule for port 80, a direct LAN request is silently dropped
  /// and surfaces in the app as a connection timeout.
  ///
  /// Override per target:
  ///   emulator  --dart-define=API_BASE_URL=http://10.0.2.2/dar_al_turab_pos_1/public/api/
  ///   real LAN  --dart-define=API_BASE_URL=http://10.66.96.244/dar_al_turab_pos_1/public/api/
  ///   web/desktop --dart-define=API_BASE_URL=http://localhost/dar_al_turab_pos_1/public/api/
  ///
  /// The login screen also lets the user set this at runtime, which is what
  /// production devices will use.
  static const apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://localhost:8080/dar_al_turab_pos_1/public/api/',
  );

  static const appName = 'Dar Al Turab POS';

  /// Trailing slash matters: Dio joins relative paths against the base URL.
  static String normalizeBaseUrl(String url) {
    final trimmed = url.trim();
    if (trimmed.isEmpty) return apiBaseUrl;
    return trimmed.endsWith('/') ? trimmed : '$trimmed/';
  }
}
