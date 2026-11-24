import 'package:dio/dio.dart';

import '../http/dio_factory.dart';

/// An open HTTP body. [abort] stops the transfer (pause / cancel).
class FetchResponse {
  const FetchResponse({required this.body, required this.abort, this.totalBytes, this.resumed = false});

  final Stream<List<int>> body;

  /// Full resource size (not just the remaining range), when known.
  final int? totalBytes;

  /// True when the server honoured `Range: bytes=<start>-` (HTTP 206).
  final bool resumed;
  final void Function() abort;
}

abstract interface class ByteFetcher {
  Future<FetchResponse> open(Uri uri, {int start = 0});
}

/// Dio-backed fetcher with range resume. JioSaavn's CDN and googlevideo both
/// answer `Range` requests with 206 (`Accept-Ranges: bytes`).
class DioByteFetcher implements ByteFetcher {
  DioByteFetcher({Dio? dio})
      : _dio = dio ??
            createDio(
              connectTimeout: const Duration(seconds: 15),
              receiveTimeout: const Duration(seconds: 30),
              maxRetries: 1,
            );

  final Dio _dio;

  static int? _totalFrom(Headers headers, int start, bool partial) {
    final range = headers.value('content-range'); // bytes 100-999/1000
    if (range != null) {
      final total = int.tryParse(range.split('/').last.trim());
      if (total != null) return total;
    }
    final length = int.tryParse(headers.value(Headers.contentLengthHeader) ?? '');
    if (length == null) return null;
    return partial ? length + start : length;
  }

  @override
  Future<FetchResponse> open(Uri uri, {int start = 0}) async {
    final token = CancelToken();
    final res = await _dio.getUri<ResponseBody>(
      uri,
      cancelToken: token,
      options: Options(
        responseType: ResponseType.stream,
        headers: start > 0 ? {'Range': 'bytes=$start-'} : null,
      ),
    );
    final partial = res.statusCode == 206;
    final body = res.data;
    if (body == null) throw StateError('Empty response for $uri');
    return FetchResponse(
      body: body.stream,
      totalBytes: _totalFrom(res.headers, start, partial),
      resumed: partial,
      abort: () {
        if (!token.isCancelled) token.cancel('paused');
      },
    );
  }
}
