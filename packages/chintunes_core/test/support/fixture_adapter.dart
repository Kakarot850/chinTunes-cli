import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';

String fixture(String name) => File('test/fixtures/$name').readAsStringSync();

typedef FixtureRoute = String? Function(RequestOptions options);

/// Offline [HttpClientAdapter]: answers JioSaavn `api.php` calls from
/// fixtures keyed by `__call`, and anything else via [fallback].
class FixtureAdapter implements HttpClientAdapter {
  FixtureAdapter({this.calls = const {}, this.fallback, this.statusFor});

  /// `__call` value → fixture file name.
  final Map<String, String> calls;
  final FixtureRoute? fallback;
  final int? Function(RequestOptions options)? statusFor;
  final List<RequestOptions> requests = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    final status = statusFor?.call(options) ?? 200;
    final call = options.queryParameters['__call']?.toString();
    String? body;
    if (call != null && calls.containsKey(call)) {
      body = fixture(calls[call]!);
    } else {
      body = fallback?.call(options);
    }
    if (body == null) {
      return ResponseBody.fromString('', 404);
    }
    return ResponseBody.fromString(
      body,
      status,
      headers: {
        Headers.contentTypeHeader: ['text/html; charset=UTF-8'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

Dio fixtureDio(FixtureAdapter adapter, {String baseUrl = 'https://www.jiosaavn.com'}) {
  final dio = Dio(BaseOptions(baseUrl: baseUrl, responseType: ResponseType.plain));
  dio.httpClientAdapter = adapter;
  return dio;
}
