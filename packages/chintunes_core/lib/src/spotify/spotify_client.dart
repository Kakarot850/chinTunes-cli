import 'dart:convert';

import 'package:dio/dio.dart';

import '../http/dio_factory.dart';
import '../models/track.dart';

/// Port of `syncer/providers/spotify.py` — metadata only (no audio).
///
/// 1. `GET https://open.spotify.com/oembed?url=<track>` → title + thumbnail.
/// 2. `GET https://open.spotify.com/embed/track/<id>` → first `"artists":[{"name":"…"}`.
///
/// Audio is resolved by matching on YouTube (CLI parity: non-JioSaavn sources
/// download via `ytsearch1:<title> <artist> audio`).
class SpotifyClient {
  SpotifyClient({Dio? dio}) : _dio = dio ?? createDio();

  final Dio _dio;
  static final RegExp _artistPattern = RegExp(r'"artists":\[\{"name":"([^"]+)"');

  static String? trackIdFromUrl(String url) {
    final m = RegExp(r'/track/([A-Za-z0-9]+)').firstMatch(url);
    return m?.group(1);
  }

  Future<Track?> track(String trackId) async {
    final clean = 'https://open.spotify.com/track/$trackId';
    var title = 'Spotify Track';
    var artist = 'Unknown Artist';
    String? image;

    try {
      final res = await _dio.get<String>(
        'https://open.spotify.com/oembed',
        queryParameters: {'url': clean},
      );
      final json = jsonDecode(res.data ?? '{}');
      if (json is Map) {
        final t = json['title']?.toString();
        if (t != null && t.isNotEmpty) title = t;
        image = json['thumbnail_url']?.toString();
      }
    } catch (_) {}

    try {
      final res = await _dio.get<String>('https://open.spotify.com/embed/track/$trackId');
      final m = _artistPattern.firstMatch(res.data ?? '');
      if (m != null) artist = m.group(1)!;
    } catch (_) {}

    if (title == 'Spotify Track' && artist == 'Unknown Artist') return null;
    return Track(
      id: trackId,
      source: TrackSource.spotify,
      title: title.trim(),
      artist: artist.trim(),
      album: title.trim(),
      imageUrl: image,
      webUrl: clean,
    );
  }
}
