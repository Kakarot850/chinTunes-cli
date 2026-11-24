import 'dart:convert';

import 'package:dio/dio.dart';

import '../data/stream_selection.dart';
import '../http/dio_factory.dart';
import '../models/resolved_stream.dart';

/// YouTube stream extraction via the InnerTube `player` endpoint using the
/// **VISIONOS** client (B-032).
///
/// Why not youtube_explode for streams: since 2026-08 YouTube requires a PO
/// token for media served to the `android`, `androidVr`, `ios` and `safari`
/// clients. youtube_explode 2.5.x still uses them, so manifests resolve but
/// every audio URL answers **403**, which surfaces in the app as "The stream
/// could not be opened". The visionOS client is still served without a PO
/// token, returns plain `url`s (no signature cipher, no `n` throttling param)
/// and needs no JS solver. youtube_explode 3.x needs Deno, which isn't an option
/// on Android.
///
/// Requests need a `visitorData` identity, otherwise YouTube answers
/// `LOGIN_REQUIRED: Sign in to confirm you're not a bot`. It is fetched from
/// the light `POST /youtubei/v1/visitor_id` (~1 KB), cached, and refreshed
/// once when a bot check appears.
///
/// Verified live 2026-11-24: status OK, itags 139/140/249/250/251 with direct
/// urls. googlevideo served them (200 / 206) with or without `Range` and with
/// any User-Agent, so ExoPlayer and the cache proxy need no headers.
class InnerTubePlayerClient {
  InnerTubePlayerClient({Dio? dio, this.visitorTtl = const Duration(hours: 6)})
      : _dio = dio ?? createDio(baseUrl: baseUrl, receiveTimeout: const Duration(seconds: 15));

  static const String baseUrl = 'https://www.youtube.com';
  static const String clientName = 'VISIONOS';
  static const String clientVersion = '1.02';

  /// `X-Youtube-Client-Name` for VISIONOS (yt-dlp `INNERTUBE_CONTEXT_CLIENT_NAME`).
  static const String clientNameId = '101';
  static const String userAgent =
      'Mozilla/5.0 (Macintosh; Intel Mac OS X 15_7_3) AppleWebKit/605.1.15 '
      '(KHTML, like Gecko) Version/26.0 Safari/605.1.15';

  final Dio _dio;
  final Duration visitorTtl;
  String? _visitorData;
  DateTime? _visitorAt;

  Map<String, Object?> _client(String visitorData) => {
        'clientName': clientName,
        'clientVersion': clientVersion,
        'deviceMake': 'Apple',
        'deviceModel': 'RealityDevice17,1',
        'osName': 'visionOS',
        'osVersion': '26.5.23O471',
        'userAgent': userAgent,
        'hl': 'en',
        'timeZone': 'UTC',
        'utcOffsetMinutes': 0,
        'visitorData': visitorData,
      };

  Future<Map<String, dynamic>> _post(String path, Map<String, Object?> body, Map<String, String> headers) async {
    final res = await _dio.post<String>(
      path,
      queryParameters: const {'prettyPrint': 'false'},
      data: jsonEncode(body),
      options: Options(
        contentType: 'application/json',
        responseType: ResponseType.plain,
        headers: {'Origin': baseUrl, ...headers},
      ),
    );
    final decoded = jsonDecode(res.data ?? '{}');
    return decoded is Map ? Map<String, dynamic>.from(decoded) : <String, dynamic>{};
  }

  /// Anonymous visitor identity (cached for [visitorTtl]).
  Future<String> visitorData({bool refresh = false}) async {
    final cached = _visitorData;
    final at = _visitorAt;
    if (!refresh && cached != null && at != null && DateTime.now().difference(at) < visitorTtl) {
      return cached;
    }
    final json = await _post(
      '/youtubei/v1/visitor_id',
      {
        'context': {
          'client': {'clientName': 'WEB', 'clientVersion': '2.20250331.00.00', 'hl': 'en'},
        },
      },
      const {'User-Agent': kDesktopUserAgent},
    );
    final ctx = json['responseContext'];
    final vd = ctx is Map ? ctx['visitorData']?.toString() : null;
    if (vd == null || vd.isEmpty) throw StreamResolveException('YouTube did not return a visitor id');
    _visitorData = vd;
    _visitorAt = DateTime.now();
    return vd;
  }

  Future<Map<String, dynamic>> player(String videoId, String visitorData) => _post(
        '/youtubei/v1/player',
        {
          'context': {'client': _client(visitorData)},
          'videoId': videoId,
          'contentCheckOk': true,
          'racyCheckOk': true,
        },
        {
          'User-Agent': userAgent,
          'X-Youtube-Client-Name': clientNameId,
          'X-Youtube-Client-Version': clientVersion,
          'X-Goog-Visitor-Id': visitorData,
        },
      );

  /// Audio-only renditions for [videoId]. Retries once with a fresh
  /// visitor id when YouTube answers with a bot check.
  Future<List<AudioStreamCandidate>> audioStreams(String videoId) async {
    for (var attempt = 0; attempt < 2; attempt++) {
      final vd = await visitorData(refresh: attempt > 0);
      final json = await player(videoId, vd);
      final error = playabilityError(json);
      if (error == null) {
        final streams = parseAudio(json);
        if (streams.isNotEmpty) return streams;
        throw StreamResolveException('No direct audio streams for $videoId');
      }
      if (attempt == 0 && error.isBotCheck) continue;
      throw StreamResolveException(error.message);
    }
    throw StreamResolveException('YouTube blocked playback for $videoId');
  }

  /// `null` when `playabilityStatus.status == "OK"`.
  static PlayabilityError? playabilityError(Map<String, dynamic> json) {
    final ps = json['playabilityStatus'];
    final status = ps is Map ? ps['status']?.toString() : null;
    if (status == 'OK') return null;
    final reason = ps is Map ? ps['reason']?.toString() : null;
    return PlayabilityError(status ?? 'UNKNOWN', reason);
  }

  static final RegExp _codecs = RegExp(r'codecs="([^"]+)"');

  /// `streamingData.adaptiveFormats` → audio-only candidates with direct urls
  /// (entries that only carry `signatureCipher` are skipped).
  static List<AudioStreamCandidate> parseAudio(Map<String, dynamic> json) {
    final sd = json['streamingData'];
    if (sd is! Map) return const [];
    final formats = sd['adaptiveFormats'];
    if (formats is! List) return const [];
    final out = <AudioStreamCandidate>[];
    for (final f in formats.whereType<Map<dynamic, dynamic>>()) {
      final mime = f['mimeType']?.toString() ?? '';
      final url = f['url']?.toString();
      final itag = f['itag'];
      if (!mime.startsWith('audio/') || url == null || itag is! int) continue;
      final uri = Uri.tryParse(url);
      if (uri == null) continue;
      final bps = (f['averageBitrate'] as num?) ?? (f['bitrate'] as num?) ?? 0;
      out.add(AudioStreamCandidate(
        itag: itag,
        bitrateKbps: (bps / 1000).round(),
        codec: _codecs.firstMatch(mime)?.group(1) ?? mime,
        container: mime.startsWith('audio/webm') ? 'webm' : 'mp4',
        url: uri,
        sizeBytes: int.tryParse(f['contentLength']?.toString() ?? ''),
      ));
    }
    return out;
  }
}

class PlayabilityError {
  const PlayabilityError(this.status, this.reason);

  final String status;
  final String? reason;

  /// "Sign in to confirm you're not a bot" → refresh the visitor id.
  bool get isBotCheck => status == 'LOGIN_REQUIRED' && (reason ?? '').toLowerCase().contains('bot');

  String get message => switch (status) {
        'LOGIN_REQUIRED' when isBotCheck => 'YouTube is asking to confirm you\'re not a bot. Try again in a minute.',
        'LOGIN_REQUIRED' => 'This video needs a signed-in YouTube account.',
        'UNPLAYABLE' || 'ERROR' => reason ?? 'This video isn\'t available.',
        _ => reason ?? 'YouTube refused to play this video ($status).',
      };
}
