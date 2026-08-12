import 'dart:convert';

import 'package:dar_al_turab_pos/core/network/api_client.dart';
import 'package:dar_al_turab_pos/core/network/api_exception.dart';
import 'package:dar_al_turab_pos/data/datasources/remote/auth_api.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

/// Serves a canned response so the login parse is exercised without a server.
class _StubAdapter implements HttpClientAdapter {
  _StubAdapter(this.statusCode, this.body);

  final int statusCode;
  final Object? body;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    return ResponseBody.fromString(
      body is String ? body as String : jsonEncode(body),
      statusCode,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

AuthApi _authApiWith(_StubAdapter adapter) {
  final dio = Dio(
    BaseOptions(
      baseUrl: 'http://example.test/api/',
      validateStatus: (_) => true,
      headers: {'Accept': 'application/json'},
    ),
  )..httpClientAdapter = adapter;

  return AuthApi(
    ApiClient(
      baseUrl: 'http://example.test/api/',
      tokenProvider: () async => null,
      dio: dio,
    ),
  );
}

void main() {
  group('AuthApi.login token parsing', () {
    test('reads the token from data.token (nested under the envelope)', () async {
      final adapter = _StubAdapter(200, {
        'success': true,
        'message': 'Login successful.',
        'data': {
          'token': '1|abcdef1234567890',
          'token_type': 'Bearer',
          'user': {'id': 1, 'name': 'Hamza', 'role_id': 1, 'permissions': []},
        },
      });

      final result = await _authApiWith(adapter).login(
        login: 'hamza',
        password: 'secret',
        deviceName: 'test',
      );

      expect(result.token, '1|abcdef1234567890');
      expect(result.user.id, 1);
      expect(result.user.name, 'Hamza');
    });

    test('throws a clear error when data.token is missing', () async {
      // The exact bug shape: a 200 login whose data has no token must fail
      // loudly, not save a null token and 401 every request afterwards.
      final adapter = _StubAdapter(200, {
        'success': true,
        'message': 'Login successful.',
        'data': {
          'user': {'id': 1, 'name': 'Hamza', 'role_id': 1, 'permissions': []},
        },
      });

      expect(
        () => _authApiWith(adapter).login(
          login: 'hamza',
          password: 'secret',
          deviceName: 'test',
        ),
        throwsA(
          isA<ApiException>().having(
            (e) => e.code,
            'code',
            ApiErrorCode.unexpectedResponse,
          ),
        ),
      );
    });

    test('throws when data.token is blank', () async {
      final adapter = _StubAdapter(200, {
        'success': true,
        'data': {
          'token': '',
          'user': {'id': 1, 'name': 'Hamza', 'role_id': 1, 'permissions': []},
        },
      });

      expect(
        () => _authApiWith(adapter).login(
          login: 'hamza',
          password: 'secret',
          deviceName: 'test',
        ),
        throwsA(isA<ApiException>()),
      );
    });
  });
}
