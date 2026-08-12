import '../../../core/network/api_client.dart';
import '../../../core/network/api_exception.dart';
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
        // The ApiClient has already unwrapped the {success, message, data}
        // envelope, so `data` here IS the login `data` object — the token lives
        // at `data.token`, never at the envelope root. Guard it explicitly: a
        // missing/blank token must fail loudly here, not get saved as null and
        // 401 every request afterwards (login_token_issue_august_12_2026).
        final json = Map<String, dynamic>.from(data as Map);
        final token = json['token'];
        if (token is! String || token.isEmpty) {
          throw const ApiException(
            code: ApiErrorCode.unexpectedResponse,
            message: 'Login response did not include an auth token.',
          );
        }
        return LoginResult(
          token: token,
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

  /// `POST /v1/auth/forgot-password` — unauthenticated.
  ///
  /// Always succeeds with a generic message when the address is well-formed
  /// (enumeration-safe): a `200` does not confirm the email is registered.
  /// Throws [ApiException] for `422` (validation), `429`
  /// (`TOO_MANY_ATTEMPTS`) or `503` (`EMAIL_NOT_CONFIGURED`).
  Future<void> forgotPassword({required String email}) => _client.post(
    'v1/auth/forgot-password',
    body: {'email': email},
    parse: (_) {},
  );

  /// `POST /v1/auth/reset-password` — unauthenticated.
  ///
  /// Completes the reset with the [token] copied from the emailed link. On
  /// success the server revokes every existing token for the account, so all
  /// devices must sign in again. Throws [ApiException] with `INVALID_TOKEN`
  /// (invalid/expired/reused), `INVALID_USER`, or `VALIDATION_ERROR`.
  Future<void> resetPassword({
    required String email,
    required String token,
    required String password,
  }) => _client.post(
    'v1/auth/reset-password',
    body: {
      'email': email,
      'token': token,
      'password': password,
      'password_confirmation': password,
    },
    parse: (_) {},
  );

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
