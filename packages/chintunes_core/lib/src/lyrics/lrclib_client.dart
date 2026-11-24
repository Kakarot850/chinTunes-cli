import 'dart:convert';

import 'package:dio/dio.dart';

import '../http/dio_factory.dart';
import '../models/lyrics.dart';
import 'lrc_parser.dart';

/// LRCLIB client (port of `LyricsEngine.query_lrclib`).
///
/// - `GET /api/get?track_name&artist_name&duration` → exact match (needs duration).
/// - `GET /api/search?track_name&artist_name` → list; prefer items with `syncedLyrics`.
class LrclibClient {
  LrclibClient({Dio? dio})
      : _dio = dio ??
            createDio(
              baseUrl: baseUrl,
              // LRCLIB asks clients to identify themselves.
              userAgent: 'chinTunes/0.1 (Android music player)',
            );

  static const String baseUrl = 'https://lrclib.net';
  final Dio _dio;

  Object? _decode(Object? data) {
    if (data is String) return data.isEmpty ? null : jsonDecode(data);
    return data;
  }

  Lyrics? _fromItem(Map<dynamic, dynamic> item, String source) {
    final syncedRaw = item['syncedLyrics']?.toString();
    final synced = LrcParser.parse(syncedRaw);
    final plain = item['plainLyrics']?.toString() ?? LrcParser.stripTimestamps(syncedRaw);
    if (synced.isEmpty && (plain == null || plain.trim().isEmpty)) return null;
    return Lyrics(plain: plain, synced: synced, source: source);
  }

  Future<Lyrics?> getExact({
    required String title,
    required String artist,
    required int durationSec,
  }) async {
    try {
      final res = await _dio.get<String>('/api/get', queryParameters: {
        'track_name': title,
        'artist_name': artist,
        'duration': durationSec,
      });
      final json = _decode(res.data);
      if (json is Map) return _fromItem(json, 'LRCLIB (Exact Match)');
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) return null;
      rethrow;
    }
    return null;
  }

  /// Returns synced lyrics if any result has them, else the first plain result.
  Future<Lyrics?> search({required String title, String? artist}) async {
    final res = await _dio.get<String>('/api/search', queryParameters: {
      'track_name': title,
      if (artist != null && artist.isNotEmpty) 'artist_name': artist,
    });
    final json = _decode(res.data);
    if (json is! List) return null;
    final items = json.whereType<Map<dynamic, dynamic>>().toList();
    for (final item in items) {
      if ((item['syncedLyrics']?.toString() ?? '').isNotEmpty) {
        return _fromItem(item, 'LRCLIB (Synced)');
      }
    }
    for (final item in items) {
      if ((item['plainLyrics']?.toString() ?? '').isNotEmpty) {
        return Lyrics(plain: item['plainLyrics'].toString(), source: 'LRCLIB (Plain)');
      }
    }
    return null;
  }
}
