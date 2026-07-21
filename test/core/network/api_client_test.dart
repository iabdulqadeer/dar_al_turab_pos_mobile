import 'dart:convert';

import 'package:dar_al_turab_pos/core/network/api_client.dart';
import 'package:dar_al_turab_pos/core/network/api_exception.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

/// Serves canned responses so we exercise envelope handling without a server.
class _StubAdapter implements HttpClientAdapter {
  _StubAdapter(this.statusCode, this.body);

  final int statusCode;
  final Object? body;

  RequestOptions? lastRequest;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    lastRequest = options;
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

ApiClient _clientWith(_StubAdapter adapter, {String? token}) {
  final dio = Dio(
    BaseOptions(
      baseUrl: 'http://example.test/api/',
      validateStatus: (_) => true,
      headers: {'Accept': 'application/json'},
    ),
  )..httpClientAdapter = adapter;

  return ApiClient(
    baseUrl: 'http://example.test/api/',
    tokenProvider: () async => token,
    dio: dio,
  );
}

void main() {
  group('ApiClient envelope handling', () {
    test('unwraps data from a success envelope', () async {
      final adapter = _StubAdapter(200, {
        'success': true,
        'message': null,
        'data': {'id': 7, 'name': 'Hamza'},
      });

      final result = await _clientWith(adapter).get<Map<String, dynamic>>(
        'v1/auth/me',
        parse: (data) => Map<String, dynamic>.from(data as Map),
      );

      expect(result['id'], 7);
      expect(result['name'], 'Hamza');
    });

    test('attaches the bearer token when one is available', () async {
      final adapter = _StubAdapter(200, {'success': true, 'data': null});

      await _clientWith(adapter, token: 'abc123').get<void>(
        'v1/auth/me',
        parse: (_) {},
      );

      expect(adapter.lastRequest?.headers['Authorization'], 'Bearer abc123');
    });

    test('omits the Authorization header when signed out', () async {
      final adapter = _StubAdapter(200, {'success': true, 'data': null});

      await _clientWith(adapter).get<void>('v1/auth/me', parse: (_) {});

      expect(adapter.lastRequest?.headers.containsKey('Authorization'), isFalse);
    });

    test('maps an error envelope to a typed ApiException', () async {
      final adapter = _StubAdapter(401, {
        'success': false,
        'message': 'Invalid credentials.',
        'errors': null,
        'code': 'INVALID_CREDENTIALS',
      });

      expect(
        () => _clientWith(adapter).post<void>('v1/auth/login', parse: (_) {}),
        throwsA(
          isA<ApiException>()
              .having((e) => e.code, 'code', ApiErrorCode.invalidCredentials)
              .having((e) => e.statusCode, 'statusCode', 401)
              .having((e) => e.message, 'message', 'Invalid credentials.'),
        ),
      );
    });

    test('exposes validation errors per field', () async {
      final adapter = _StubAdapter(422, {
        'success': false,
        'message': 'The given data was invalid.',
        'errors': {
          'login': ['The login field is required.'],
        },
        'code': 'VALIDATION_ERROR',
      });

      try {
        await _clientWith(adapter).post<void>('v1/auth/login', parse: (_) {});
        fail('expected ApiException');
      } on ApiException catch (e) {
        expect(e.isValidation, isTrue);
        expect(e.errorFor('login'), 'The login field is required.');
        expect(e.errorFor('password'), isNull);
      }
    });

    test(
      'surfaces the offending product id for INSUFFICIENT_STOCK',
      () async {
        // The server reports the blocking line as errors.product_id, which the
        // cart UI uses to highlight that specific row.
        final adapter = _StubAdapter(422, {
          'success': false,
          'message': 'Insufficient stock.',
          'errors': {
            'product_id': ['7'],
          },
          'code': 'INSUFFICIENT_STOCK',
        });

        try {
          await _clientWith(adapter).post<void>('v1/sales', parse: (_) {});
          fail('expected ApiException');
        } on ApiException catch (e) {
          expect(e.code, ApiErrorCode.insufficientStock);
          expect(e.errorFor('product_id'), '7');
        }
      },
    );

    test('flags 401 responses as unauthenticated', () async {
      final adapter = _StubAdapter(401, {
        'success': false,
        'message': 'Unauthenticated.',
        'code': 'UNAUTHENTICATED',
      });

      try {
        await _clientWith(adapter).get<void>('v1/sales', parse: (_) {});
        fail('expected ApiException');
      } on ApiException catch (e) {
        expect(e.isUnauthenticated, isTrue);
      }
    });

    test('treats an HTML body as a misconfigured base URL', () async {
      // Hitting a web route instead of /api returns HTML; the message must
      // point at the base URL rather than pretend it is a server error.
      final adapter = _StubAdapter(200, '<!doctype html><html></html>');

      try {
        await _clientWith(adapter).get<void>('v1/sales', parse: (_) {});
        fail('expected ApiException');
      } on ApiException catch (e) {
        expect(e.code, ApiErrorCode.unexpectedResponse);
        expect(e.message, contains('base URL'));
      }
    });
  });

  group('ApiClient list handling', () {
    test('parses items and meta pagination', () async {
      final adapter = _StubAdapter(200, {
        'success': true,
        'data': [
          {'id': 1},
          {'id': 2},
        ],
        'meta': {
          'current_page': 1,
          'per_page': 20,
          'total': 33,
          'last_page': 2,
          'summary': {'total_grand': 420.5, 'total_paid': 400.0},
        },
      });

      final page = await _clientWith(adapter).getList<int>(
        'v1/sales',
        parseItem: (json) => (json['id'] as num).toInt(),
      );

      expect(page.items, [1, 2]);
      expect(page.meta.total, 33);
      expect(page.hasMore, isTrue);
      expect(page.meta.nextPage, 2);
      expect(page.meta.summaryValue('total_grand'), 420.5);
    });

    test('reports no further pages on the last page', () async {
      final adapter = _StubAdapter(200, {
        'success': true,
        'data': <Object>[],
        'meta': {
          'current_page': 2,
          'per_page': 20,
          'total': 21,
          'last_page': 2,
        },
      });

      final page = await _clientWith(adapter).getList<int>(
        'v1/sales',
        parseItem: (json) => (json['id'] as num).toInt(),
      );

      expect(page.items, isEmpty);
      expect(page.hasMore, isFalse);
    });

    test('rejects a non-list data payload', () async {
      final adapter = _StubAdapter(200, {
        'success': true,
        'data': {'id': 1},
      });

      expect(
        () => _clientWith(adapter).getList<int>(
          'v1/sales',
          parseItem: (json) => (json['id'] as num).toInt(),
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
  });
}
