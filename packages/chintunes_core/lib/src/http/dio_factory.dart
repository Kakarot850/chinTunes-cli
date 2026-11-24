import 'package:dio/dio.dart';

/// Desktop Chrome UA used by every chinTunes-cli request (`USER_AGENT` constant).
/// JioSaavn's `api.php` serves the same JSON to this UA as to its web player.
const String kDesktopUserAgent =
    'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 '
    '(KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36';

/// Builds a Dio instance with CLI-equivalent headers and timeouts.
Dio createDio({
  String? baseUrl,
  Duration connectTimeout = const Duration(seconds: 8),
  Duration receiveTimeout = const Duration(seconds: 10),
  String userAgent = kDesktopUserAgent,
  int maxRetries = 2,
}) {
  final dio = Dio(
    BaseOptions(
      baseUrl: baseUrl ?? '',
      connectTimeout: connectTimeout,
      receiveTimeout: receiveTimeout,
      // JioSaavn answers with `text/html` content-type; decode JSON ourselves.
      responseType: ResponseType.plain,
      headers: {'User-Agent': userAgent, 'Accept': 'application/json, */*'},
    ),
  );
  dio.interceptors.add(RetryInterceptor(dio, maxRetries: maxRetries));
  return dio;
}

/// Retries transient failures (timeouts, connection errors, 429, 5xx) with
/// linear back-off. Mirrors the CLI's tolerant "try again later" behaviour
/// without hammering the API (see HANDOVER "rate limits").
class RetryInterceptor extends Interceptor {
  RetryInterceptor(this._dio, {this.maxRetries = 2, this.baseDelay = const Duration(milliseconds: 400)});

  final Dio _dio;
  final int maxRetries;
  final Duration baseDelay;

  static const _attemptKey = 'chintunes_retry_attempt';

  bool _shouldRetry(DioException err) {
    switch (err.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.receiveTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.connectionError:
        return true;
      case DioExceptionType.badResponse:
        final code = err.response?.statusCode ?? 0;
        return code == 429 || code >= 500;
      default:
        return false;
    }
  }

  @override
  Future<void> onError(DioException err, ErrorInterceptorHandler handler) async {
    final attempt = (err.requestOptions.extra[_attemptKey] as int?) ?? 0;
    if (attempt >= maxRetries || !_shouldRetry(err)) {
      handler.next(err);
      return;
    }
    await Future<void>.delayed(baseDelay * (attempt + 1));
    final options = err.requestOptions..extra[_attemptKey] = attempt + 1;
    try {
      final response = await _dio.fetch<dynamic>(options);
      handler.resolve(response);
    } on DioException catch (e) {
      handler.next(e);
    }
  }
}
