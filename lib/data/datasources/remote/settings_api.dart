import '../../../core/network/api_client.dart';
import '../../models/brand_settings.dart';

/// Wraps the read-only `/v1/settings/*` endpoints.
class SettingsApi {
  const SettingsApi(this._client);

  final ApiClient _client;

  /// `GET /v1/settings/general` — company branding for the header, the About
  /// screen and receipts.
  ///
  /// Requires authentication but no special permission: every user needs their
  /// company's branding regardless of role.
  Future<BrandSettings> general() {
    return _client.get(
      'v1/settings/general',
      parse: (data) =>
          BrandSettings.fromJson(Map<String, dynamic>.from(data as Map)),
    );
  }
}
