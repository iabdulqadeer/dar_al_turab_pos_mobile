import '../../../core/network/api_client.dart';
import '../../models/auth_user.dart';

/// Result of a successful login: the plaintext Sanctum token plus the user.
class LoginResult {
  const LoginResult({required this.token, required this.user});

  final String token;
  final AuthUser user;
}

/// Wraps the `/v1/auth/*` and `/v1/profile` endpoints.
class AuthApi {
  const AuthApi(this._client);

  final ApiClient _client;

  /// `POST /v1/auth/login`
  ///
  /// [login] accepts either a username or an email — the server decides which
  /// column to match with `filter_var(..., FILTER_VALIDATE_EMAIL)`.
  /// Rate limited to 5 attempts per 60s per IP+login.
  Future<LoginResult> login({
    required String login,
    required String password,
    required String deviceName,
  }) {
    return _client.post(
      'v1/auth/login',
      body: {
        'login': login,
        'password': password,
        'device_name': deviceName,
      },
      parse: (data) {
        final json = Map<String, dynamic>.from(data as Map);
        return LoginResult(
          token: json['token'] as String,
          user: AuthUser.fromJson(
            Map<String, dynamic>.from(json['user'] as Map),
          ),
        );
      },
    );
  }

  /// `POST /v1/auth/logout` — revokes only the current device's token.
  Future<void> logout() =>
      _client.post('v1/auth/logout', parse: (_) {});

  /// `GET /v1/auth/me`
  Future<AuthUser> me() => _client.get(
    'v1/auth/me',
    parse: (data) => AuthUser.fromJson(Map<String, dynamic>.from(data as Map)),
  );

  /// `GET /v1/profile`
  Future<AuthUser> profile() => _client.get(
    'v1/profile',
    parse: (data) => AuthUser.fromJson(Map<String, dynamic>.from(data as Map)),
  );

  /// `PUT /v1/profile` — only name/email/phone/company_name are honoured;
  /// role, warehouse, and active flags are ignored server-side.
  Future<AuthUser> updateProfile({
    required String name,
    String? email,
    String? phone,
    String? companyName,
  }) {
    return _client.put(
      'v1/profile',
      body: {
        'name': name,
        'email': email,
        'phone': phone,
        'company_name': companyName,
      },
      parse: (data) =>
          AuthUser.fromJson(Map<String, dynamic>.from(data as Map)),
    );
  }

  /// `PUT /v1/profile/password`
  ///
  /// On success the server revokes all *other* tokens and keeps this one, so
  /// the current session stays valid and no re-login is needed.
  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  }) {
    return _client.put(
      'v1/profile/password',
      body: {
        'current_password': currentPassword,
        'new_password': newPassword,
        'new_password_confirmation': newPassword,
      },
      parse: (_) {},
    );
  }
}
