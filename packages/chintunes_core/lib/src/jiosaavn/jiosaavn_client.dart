import 'dart:convert';

import 'package:dio/dio.dart';

import '../http/dio_factory.dart';
import '../models/collection.dart';
import '../models/home_feed.dart';
import '../models/track.dart';
import '../util/html_text.dart';
import 'jiosaavn_parser.dart';

class JioSaavnException implements Exception {
  JioSaavnException(this.message);
  final String message;

  @override
  String toString() => 'JioSaavnException: $message';
}

/// Dart port of `syncer/providers/jiosaavn.py` plus the browse endpoints the
/// app needs (trending, launch data, artist/album/playlist detail).
///
/// All calls go to `https://www.jiosaavn.com/api.php` with
/// `_format=json&_marker=0&api_version=4` and a `ctx` of `wap6dot0` (search,
/// collections — returns `encrypted_media_url`) or `web6dot0` (details, lyrics).
class JioSaavnClient {
  JioSaavnClient({Dio? dio}) : _dio = dio ?? createDio(baseUrl: baseUrl);

  static const String baseUrl = 'https://www.jiosaavn.com';
  final Dio _dio;

  Future<Object?> _call(
    String call,
    Map<String, Object?> params, {
    String ctx = 'web6dot0',
  }) async {
    final response = await _dio.get<String>(
      '/api.php',
      queryParameters: <String, Object?>{
        '__call': call,
        '_format': 'json',
        '_marker': '0',
        'api_version': '4',
        'ctx': ctx,
        ...params,
      },
      options: Options(responseType: ResponseType.plain),
    );
    final body = response.data?.trim() ?? '';
    if (body.isEmpty) return null;
    try {
      return jsonDecode(body);
    } on FormatException {
      throw JioSaavnException('Non-JSON response for $call');
    }
  }

  Map<String, dynamic> _asMap(Object? v) =>
      v is Map ? Map<String, dynamic>.from(v) : const <String, dynamic>{};

  // ---------------------------------------------------------------- search

  /// `search.getResults` — songs with encrypted media urls (CLI `search_songs`).
  Future<List<Track>> searchSongs(String query, {int page = 1, int limit = 20}) async {
    final json = await _call(
      'search.getResults',
      {'q': query, 'p': page, 'n': limit},
      ctx: 'wap6dot0',
    );
    return JioSaavnParser.songs(_asMap(json)['results']);
  }

  Future<List<CollectionSummary>> searchAlbums(String query, {int page = 1, int limit = 10}) async {
    final json = await _call('search.getAlbumResults', {'q': query, 'p': page, 'n': limit}, ctx: 'wap6dot0');
    return JioSaavnParser.summaries(_asMap(json)['results'], type: CollectionType.album);
  }

  Future<List<CollectionSummary>> searchPlaylists(String query, {int page = 1, int limit = 10}) async {
    final json = await _call('search.getPlaylistResults', {'q': query, 'p': page, 'n': limit}, ctx: 'wap6dot0');
    return JioSaavnParser.summaries(_asMap(json)['results'], type: CollectionType.playlist);
  }

  Future<List<CollectionSummary>> searchArtists(String query, {int page = 1, int limit = 10}) async {
    final json = await _call('search.getArtistResults', {'q': query, 'p': page, 'n': limit}, ctx: 'wap6dot0');
    return JioSaavnParser.summaries(_asMap(json)['results'], type: CollectionType.artist);
  }

  // --------------------------------------------------------------- details

  /// `song.getDetails&pids=` — refreshes stream urls for tracks that came from
  /// payloads without `encrypted_media_url` (autocomplete, launch data).
  Future<List<Track>> songDetails(List<String> ids) async {
    if (ids.isEmpty) return const [];
    final json = await _call('song.getDetails', {'pids': ids.join(',')});
    final map = _asMap(json);
    if (map['songs'] is List) return JioSaavnParser.songs(map['songs']);
    // api_version=3 shape: {"<id>": {...}}
    return JioSaavnParser.songs(map.values.toList());
  }

  /// `webapi.get&type=song` by perma-url token (CLI single-song path).
  Future<Track?> songByToken(String token) async {
    final json = await _call('webapi.get', {'token': token, 'type': 'song', 'includeMetaTags': 0});
    final songs = JioSaavnParser.songs(_asMap(json)['songs']);
    return songs.isEmpty ? null : songs.first;
  }

  Future<MediaCollection?> album({String? token, String? id}) async {
    if (token != null && token.isNotEmpty) {
      final json = await _call(
        'webapi.get',
        {'token': token, 'type': 'album', 'p': 1, 'n': 250, 'includeMetaTags': 0},
        ctx: 'wap6dot0',
      );
      final parsed = JioSaavnParser.collection(json, CollectionType.album);
      if (parsed != null) return parsed;
    }
    if (id != null && id.isNotEmpty) {
      final json = await _call('content.getAlbumDetails', {'albumid': id});
      return JioSaavnParser.collection(json, CollectionType.album);
    }
    return null;
  }

  /// Prefers `playlist.getDetails&listid=` — `webapi.get&type=playlist` returns
  /// an empty body for `/featured/` tokens (bug B-002, reproduced 2026-11-24).
  Future<MediaCollection?> playlist({String? id, String? token, int limit = 250}) async {
    if (id != null && id.isNotEmpty) {
      final json = await _call('playlist.getDetails', {'listid': id, 'p': 1, 'n': limit});
      final parsed = JioSaavnParser.collection(json, CollectionType.playlist);
      if (parsed != null) return parsed;
    }
    if (token != null && token.isNotEmpty) {
      final json = await _call(
        'webapi.get',
        {'token': token, 'type': 'playlist', 'p': 1, 'n': limit, 'includeMetaTags': 0},
        ctx: 'wap6dot0',
      );
      return JioSaavnParser.collection(json, CollectionType.playlist);
    }
    return null;
  }

  Future<MediaCollection?> artist({required String token}) async {
    final json = await _call('webapi.get', {
      'token': token,
      'type': 'artist',
      'p': 0,
      'n_song': 25,
      'n_album': 20,
      'includeMetaTags': 0,
    });
    return JioSaavnParser.artist(json);
  }

  // ---------------------------------------------------------------- browse

  Future<List<Track>> trending({String language = 'hindi'}) async {
    final json = await _call('content.getTrending', {'entity_type': 'song', 'entity_language': language});
    return JioSaavnParser.songs(json);
  }

  Future<HomeFeed> homeFeed({String language = 'hindi'}) async {
    final results = await Future.wait<Object?>([
      _call('webapi.getLaunchData', const {}).catchError((Object _) => null),
      trending(language: language).catchError((Object _) => const <Track>[]),
    ]);
    return HomeFeed(
      sections: JioSaavnParser.launchSections(results[0]),
      trending: results[1] as List<Track>,
    );
  }

  // ---------------------------------------------------------------- lyrics

  /// `lyrics.getLyrics` — plain (unsynced) studio lyrics (CLI `fetch_lyrics`).
  Future<String?> lyrics(String songId) async {
    final json = await _call('lyrics.getLyrics', {'lyrics_id': songId});
    final raw = _asMap(json)['lyrics']?.toString();
    if (raw == null || raw.trim().isEmpty) return null;
    return unescapeHtml(brToNewlines(raw));
  }
}
