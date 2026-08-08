import 'package:dio/dio.dart';

import '../config/app_config.dart';

/// Outcome of a server reachability check.
enum ServerProbeStatus {
  /// Reached the host and it answered like the Laravel API (JSON envelope).
  reachableApi,

  /// Reached *something* at the URL, but it did not look like the API — almost
  /// always a wrong path (e.g. pointing at the web root, not `/api/`).
  reachableNotApi,

  /// Nothing answered in time — wrong host/port, server down, or off-network.
  unreachable,
}

class ServerProbeResult {
  const ServerProbeResult(this.status, this.detail);

  final ServerProbeStatus status;
  final String detail;

  bool get ok => status == ServerProbeStatus.reachableApi;
}

/// Quickly checks whether [url] is a reachable, valid API endpoint, so the user
/// can confirm a dev URL before switching the whole app to it.
///
/// Uses a short timeout of its own (independent of the app's normal 15s) so a
/// dead URL fails fast instead of making the user wait. It hits an authenticated
/// endpoint unauthenticated: a live API answers with its JSON envelope (a 401),
/// which both proves reachability and that this really is the API — not just any
/// web server.
Future<ServerProbeResult> probeServer(String url) async {
  final normalized = AppConfig.normalizeBaseUrl(url);
  final dio = Dio(
    BaseOptions(
      baseUrl: normalized,
      connectTimeout: const Duration(seconds: 5),
      receiveTimeout: const Duration(seconds: 5),
      sendTimeout: const Duration(seconds: 5),
      validateStatus: (_) => true,
      headers: {'Accept': 'application/json'},
    ),
  );

  try {
    final response = await dio.get<dynamic>('v1/settings/general');
    final body = response.data;
    final looksLikeApi =
        body is Map &&
        (body.containsKey('success') ||
            body.containsKey('code') ||
            body.containsKey('message'));
    if (looksLikeApi) {
      return const ServerProbeResult(
        ServerProbeStatus.reachableApi,
        'Reached the API.',
      );
    }
    return const ServerProbeResult(
      ServerProbeStatus.reachableNotApi,
      'Reached the host, but it did not respond like the API. '
          'Check the path ends at /api/.',
    );
  } on DioException catch (e) {
    // A non-JSON body (HTML) throws while decoding — the host answered but at a
    // non-API route, so the URL is wrong rather than unreachable.
    if (e.error is FormatException) {
      return const ServerProbeResult(
        ServerProbeStatus.reachableNotApi,
        'Reached the host, but got a non-JSON page. '
            'Check the path ends at /api/.',
      );
    }
    return ServerProbeResult(
      ServerProbeStatus.unreachable,
      switch (e.type) {
        DioExceptionType.connectionTimeout ||
        DioExceptionType.sendTimeout ||
        DioExceptionType.receiveTimeout =>
          'Timed out. Check the IP/port, that the dev server is running, and '
              '(for a USB tunnel) that "adb reverse tcp:8080 tcp:80" is set.',
        _ =>
          'Cannot reach this URL. Check the IP/port and that the phone is on '
              'the same network as the dev server.',
      },
    );
  } finally {
    dio.close(force: true);
  }
}
