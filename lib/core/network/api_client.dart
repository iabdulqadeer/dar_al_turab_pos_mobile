import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../config/app_config.dart';
import 'api_exception.dart';
import 'api_response.dart';

/// Supplies the bearer token for outgoing requests.
typedef TokenProvider = Future<String?> Function();

/// Invoked when the server rejects our token, so the app can clear session
/// state and bounce to login.
typedef UnauthenticatedCallback = Future<void> Function();

/// Thin wrapper over Dio that speaks the v1 API's envelope.
///
/// Every successful v1 response is `{success, message, data, meta?}`, so
/// callers here receive the unwrapped `data` directly and never deal with the
/// envelope. Every failure is converted to an [ApiException] carrying the
/// server's `code`, so no call site inspects raw status codes or Dio types.
class ApiClient {
  ApiClient({
    required String baseUrl,
    required TokenProvider tokenProvider,
    UnauthenticatedCallback? onUnauthenticated,
    Dio? dio,
  }) : _tokenProvider = tokenProvider,
       _onUnauthenticated = onUnauthenticated,
       _dio =
           dio ??
           Dio(
             BaseOptions(
               baseUrl: baseUrl,
               connectTimeout: const Duration(seconds: 15),
               receiveTimeout: const Duration(seconds: 30),
               sendTimeout: const Duration(seconds: 30),
               // We map non-2xx ourselves so the error envelope is preserved.
               validateStatus: (_) => true,
               headers: {
                 'Accept': 'application/json',
                 'Content-Type': 'application/json',
               },
             ),
           ) {
    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          final token = await _tokenProvider();
          if (token != null && token.isNotEmpty) {
            options.headers['Authorization'] = 'Bearer $token';
          }
          // Diagnostic (internal/test builds only): record whether a token was
          // attached, without ever logging the token itself. A `GET
          // settings/general auth=MISSING` right after a login pinpoints the
          // "token never attached" bug (login_token_issue_august_12_2026).
          if (AppConfig.enableServerToggle) {
            final auth = token != null && token.isNotEmpty
                ? 'attached(len=${token.length})'
                : 'MISSING';
            debugPrint('[API] → ${options.method} ${options.uri} auth=$auth');
          }
          handler.next(options);
        },
        onResponse: (response, handler) {
          if (AppConfig.enableServerToggle) {
            debugPrint(
              '[API] ← ${response.statusCode} '
              '${response.requestOptions.method} ${response.requestOptions.uri}',
            );
          }
          handler.next(response);
        },
      ),
    );
  }

  final Dio _dio;
  final TokenProvider _tokenProvider;
  final UnauthenticatedCallback? _onUnauthenticated;

  Dio get raw => _dio;

  set baseUrl(String value) => _dio.options.baseUrl = value;

  Future<T> get<T>(
    String path, {
    Map<String, dynamic>? query,
    required T Function(dynamic data) parse,
  }) {
    return _send(path, parse, () => _dio.get(path, queryParameters: query));
  }

  Future<T> post<T>(
    String path, {
    Object? body,
    Map<String, dynamic>? query,
    Map<String, String>? headers,
    required T Function(dynamic data) parse,
  }) {
    return _send(
      path,
      parse,
      () => _dio.post(
        path,
        data: body,
        queryParameters: query,
        options: headers == null ? null : Options(headers: headers),
      ),
    );
  }

  Future<T> put<T>(
    String path, {
    Object? body,
    required T Function(dynamic data) parse,
  }) {
    return _send(path, parse, () => _dio.put(path, data: body));
  }

  Future<T> delete<T>(
    String path, {
    Object? body,
    required T Function(dynamic data) parse,
  }) {
    return _send(path, parse, () => _dio.delete(path, data: body));
  }

  /// GET on a list endpoint, pairing parsed items with `meta` pagination.
  Future<Paginated<T>> getList<T>(
    String path, {
    Map<String, dynamic>? query,
    required T Function(Map<String, dynamic> json) parseItem,
  }) async {
    final response = await _raw(() => _dio.get(path, queryParameters: query));
    final envelope = _unwrapEnvelope(response, path);

    final data = envelope.data;
    if (data is! List) {
      throw ApiException(
        code: ApiErrorCode.unexpectedResponse,
        message: 'Expected a list from $path but received ${data.runtimeType}.',
        statusCode: response.statusCode,
      );
    }

    return Paginated(
      items: data
          .whereType<Map>()
          .map((e) => parseItem(Map<String, dynamic>.from(e)))
          .toList(growable: false),
      meta: PageMeta.fromJson(envelope.meta ?? const {}),
    );
  }

  Future<T> _send<T>(
    String path,
    T Function(dynamic data) parse,
    Future<Response<dynamic>> Function() request,
  ) async {
    final response = await _raw(request);
    final envelope = _unwrapEnvelope(response, path);
    return parse(envelope.data);
  }

  Future<Response<dynamic>> _raw(
    Future<Response<dynamic>> Function() request,
  ) async {
    try {
      return await request();
    } on DioException catch (e) {
      // A body that isn't JSON makes Dio's transformer throw while decoding.
      // That means we reached *something* but not the API — almost always a
      // base URL pointing at a web route that returned HTML. Reporting it as
      // a network error would send the user chasing the wrong problem.
      if (e.error is FormatException) {
        throw ApiException(
          code: ApiErrorCode.unexpectedResponse,
          message:
              'The server returned a non-JSON response. '
              'Verify the API base URL points at the Laravel /api endpoint.',
          statusCode: e.response?.statusCode,
        );
      }

      throw ApiException(
        code: ApiErrorCode.networkError,
        message: switch (e.type) {
          DioExceptionType.connectionTimeout ||
          DioExceptionType.sendTimeout ||
          DioExceptionType.receiveTimeout =>
            'The server took too long to respond. Check your connection and try again.',
          DioExceptionType.connectionError =>
            'Cannot reach the server. Check your network connection.',
          _ => e.message ?? 'A network error occurred.',
        },
      );
    }
  }

  _Envelope _unwrapEnvelope(Response<dynamic> response, String path) {
    final status = response.statusCode ?? 0;
    final body = response.data;

    if (body is! Map) {
      // Reaching here usually means we hit a non-API route and got HTML back,
      // which points at a misconfigured base URL rather than a real API error.
      throw ApiException(
        code: ApiErrorCode.unexpectedResponse,
        message:
            'The server returned an unexpected response for $path. '
            'Verify the API base URL points at the Laravel /api endpoint.',
        statusCode: status,
      );
    }

    final json = Map<String, dynamic>.from(body);
    final success = json['success'] == true;

    if (success && status >= 200 && status < 300) {
      return _Envelope(
        data: json['data'],
        meta: json['meta'] is Map
            ? Map<String, dynamic>.from(json['meta'] as Map)
            : null,
      );
    }

    final exception = ApiException(
      code: (json['code'] as String?) ?? ApiErrorCode.serverError,
      message: (json['message'] as String?) ?? 'Request failed.',
      statusCode: status,
      errors: _parseErrors(json['errors']),
    );

    if (exception.isUnauthenticated) {
      // Fire and forget: session teardown must not block the throw.
      unawaited(Future(() async => _onUnauthenticated?.call()));
    }

    throw exception;
  }

  Map<String, List<String>>? _parseErrors(dynamic raw) {
    if (raw is! Map) return null;
    return raw.map(
      (key, value) => MapEntry(
        key.toString(),
        value is List
            ? value.map((e) => e.toString()).toList()
            : <String>[value.toString()],
      ),
    );
  }
}

class _Envelope {
  const _Envelope({required this.data, required this.meta});
  final dynamic data;
  final Map<String, dynamic>? meta;
}
