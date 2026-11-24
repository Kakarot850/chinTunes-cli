import 'dart:convert';

import 'package:dio/dio.dart';

import '../http/dio_factory.dart';
import '../jiosaavn/jiosaavn_client.dart';
import '../models/collection.dart';
import '../models/track.dart';
import '../util/html_text.dart';
import '../util/image_url.dart';
import '../youtube/youtube_source.dart';
import 'remote_playlist.dart';

class ImportException implements Exception {
  ImportException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Imports public playlists / albums from JioSaavn, YouTube (Music),
/// Spotify, Deezer and Apple Music, without user login.
///
/// | Service     | Source of truth (verified live 2026-11-24)                        |
/// |-------------|-------------------------------------------------------------------|
/// | Spotify     | `open.spotify.com/embed/{playlist|album}/<id>` → `__NEXT_DATA__`   |
/// | Deezer      | public API `api.deezer.com/{playlist|album}/<id>` (+ `next` pages) |
/// | Apple Music | page `serialized-server-data` JSON (`trackLockup` sections)        |
/// | JioSaavn    | `webapi.get&token=` (album) / playlist token                       |
/// | YouTube     | youtube_explode playlist (public / unlisted)                       |
///
/// Spotify / Deezer / Apple tracks are metadata-only and play through a
/// YouTube or JioSaavn match (`StreamResolver`).
class PlaylistImporter {
  PlaylistImporter({required JioSaavnClient jiosaavn, required YouTubeSource youtube, Dio? dio})
      : _jiosaavn = jiosaavn,
        _youtube = youtube,
        _dio = dio ?? createDio(receiveTimeout: const Duration(seconds: 20));

  final JioSaavnClient _jiosaavn;
  final YouTubeSource _youtube;
  final Dio _dio;

  /// Max tracks pulled from a single playlist (Deezer paging / YouTube).
  static const int maxTracks = 1000;

  static const List<PlaylistService> supported = PlaylistService.values;

  // ------------------------------------------------------------- parsing

  static bool _isShortLink(Uri uri) {
    final h = uri.host.toLowerCase();
    return h == 'spotify.link' ||
        h.endsWith('.app.link') ||
        h == 'link.deezer.com' ||
        h == 'deezer.page.link' ||
        h == 'dzr.page.link';
  }

  /// Recognises playlist / album links. Returns null for anything else
  /// (short links must be expanded with [resolve] first).
  static PlaylistRef? parseUrl(String input) {
    var raw = input.trim();
    if (raw.isEmpty) return null;
    // Share sheets often prepend text: take the first URL.
    final m = RegExp(r'https?://\S+').firstMatch(raw);
    if (m != null) raw = m.group(0)!;
    if (!raw.contains('://')) raw = 'https://$raw';
    final uri = Uri.tryParse(raw);
    if (uri == null || uri.host.isEmpty) return null;
    final host = uri.host.toLowerCase();
    final segs = uri.pathSegments.where((s) => s.isNotEmpty).toList();

    if (host.endsWith('spotify.com')) {
      final i = segs.indexWhere((s) => s == 'playlist' || s == 'album');
      if (i < 0 || i + 1 >= segs.length) return null;
      return PlaylistRef(
        service: PlaylistService.spotify,
        kind: segs[i] == 'album' ? RemoteKind.album : RemoteKind.playlist,
        id: segs[i + 1],
        url: raw,
      );
    }
    if (host.endsWith('deezer.com')) {
      final i = segs.indexWhere((s) => s == 'playlist' || s == 'album');
      if (i < 0 || i + 1 >= segs.length || int.tryParse(segs[i + 1]) == null) return null;
      return PlaylistRef(
        service: PlaylistService.deezer,
        kind: segs[i] == 'album' ? RemoteKind.album : RemoteKind.playlist,
        id: segs[i + 1],
        url: raw,
      );
    }
    if (host == 'music.apple.com' || host == 'itunes.apple.com') {
      final i = segs.indexWhere((s) => s == 'playlist' || s == 'album');
      if (i < 0 || segs.length < i + 2) return null;
      return PlaylistRef(
        service: PlaylistService.appleMusic,
        kind: segs[i] == 'album' ? RemoteKind.album : RemoteKind.playlist,
        id: segs.last,
        url: raw,
      );
    }
    if (host.contains('jiosaavn.com') || host.contains('saavn.com')) {
      final isAlbum = segs.contains('album');
      final isPlaylist = segs.contains('featured') || segs.contains('playlist');
      if ((!isAlbum && !isPlaylist) || segs.isEmpty) return null;
      return PlaylistRef(
        service: PlaylistService.jiosaavn,
        kind: isAlbum ? RemoteKind.album : RemoteKind.playlist,
        id: segs.last,
        url: raw,
      );
    }
    if (host.contains('youtube.com') || host == 'youtu.be') {
      final list = uri.queryParameters['list'];
      // RD… lists are auto-generated mixes, not importable playlists.
      if (list == null || list.isEmpty || list.startsWith('RD')) return null;
      return PlaylistRef(service: PlaylistService.youtube, kind: RemoteKind.playlist, id: list, url: raw);
    }
    return null;
  }

  /// [parseUrl], following Spotify / Deezer short links (`spotify.link`,
  /// `link.deezer.com`, `deezer.page.link`) to their final URL first.
  Future<PlaylistRef?> resolve(String input) async {
    final direct = parseUrl(input);
    if (direct != null) return direct;
    final m = RegExp(r'https?://\S+').firstMatch(input.trim());
    final uri = Uri.tryParse(m?.group(0) ?? input.trim());
    if (uri == null || !_isShortLink(uri)) return null;
    try {
      final res = await _dio.getUri<String>(
        uri,
        options: Options(responseType: ResponseType.plain, followRedirects: true, maxRedirects: 5),
      );
      final expanded = parseUrl(res.realUri.toString());
      if (expanded != null) return expanded;
      // Some short links land on an HTML page with the target in a meta/link tag.
      final inPage = RegExp(r'https://(?:open\.spotify\.com|www\.deezer\.com)/[^"\s<>]+').firstMatch(res.data ?? '');
      return inPage == null ? null : parseUrl(inPage.group(0)!);
    } catch (_) {
      return null;
    }
  }

  // ------------------------------------------------------------- fetching

  Future<RemotePlaylist> fetch(PlaylistRef ref) async {
    switch (ref.service) {
      case PlaylistService.spotify:
        final res = await _get('https://open.spotify.com/embed/${ref.kind.name}/${ref.id}');
        return parseSpotifyEmbed(res, ref);
      case PlaylistService.deezer:
        return _fetchDeezer(ref);
      case PlaylistService.appleMusic:
        final res = await _get(ref.url);
        return parseAppleMusicPage(res, ref);
      case PlaylistService.jiosaavn:
        final MediaCollection? col = ref.kind == RemoteKind.album
            ? await _jiosaavn.album(token: ref.id)
            : await _jiosaavn.playlist(token: ref.id, limit: 500);
        if (col == null) throw ImportException('JioSaavn didn\'t return this ${ref.kind.name}. Check the link is public.');
        return RemotePlaylist(ref: ref, title: col.summary.title, tracks: col.tracks, imageUrl: col.summary.imageUrl);
      case PlaylistService.youtube:
        final col = await _youtube.playlist(ref.id, limit: maxTracks);
        if (col == null) throw ImportException('YouTube didn\'t return this playlist. Private playlists need sign-in.');
        return RemotePlaylist(
          ref: ref,
          title: col.summary.title,
          tracks: col.tracks,
          imageUrl: col.summary.imageUrl,
          owner: col.summary.subtitle,
        );
    }
  }

  Future<RemotePlaylist> importUrl(String url) async {
    final ref = await resolve(url);
    if (ref == null) {
      throw ImportException('That link isn\'t a supported playlist or album. '
          'Paste a Spotify, YouTube, JioSaavn, Deezer or Apple Music playlist link.');
    }
    final playlist = await fetch(ref);
    if (playlist.tracks.isEmpty) throw ImportException('"${playlist.title}" has no playable songs.');
    return playlist;
  }

  Future<String> _get(String url) async {
    try {
      final res = await _dio.get<String>(url, options: Options(responseType: ResponseType.plain));
      return res.data ?? '';
    } on DioException catch (e) {
      final code = e.response?.statusCode;
      if (code == 404) throw ImportException('This playlist doesn\'t exist or is private.');
      throw ImportException('Couldn\'t reach the service. Check your connection and try again.');
    }
  }

  Future<Map<String, dynamic>> _getJson(String url) async {
    final body = await _get(url);
    final decoded = jsonDecode(body.isEmpty ? '{}' : body);
    if (decoded is! Map) throw ImportException('Unexpected response from the service.');
    return Map<String, dynamic>.from(decoded);
  }

  Future<RemotePlaylist> _fetchDeezer(PlaylistRef ref) async {
    final json = await _getJson('https://api.deezer.com/${ref.kind.name}/${ref.id}');
    final error = json['error'];
    if (error is Map) {
      throw ImportException(error['code'] == 800
          ? 'This Deezer ${ref.kind.name} doesn\'t exist or is private.'
          : 'Deezer: ${error['message'] ?? 'request failed'}');
    }
    final base = parseDeezer(json, ref);
    final tracks = [...base.tracks];
    var next = (json['tracks'] is Map) ? (json['tracks'] as Map<dynamic, dynamic>)['next']?.toString() : null;
    while (next != null && tracks.length < maxTracks) {
      final page = await _getJson(next);
      tracks.addAll(deezerTracks(page['data'], albumTitle: base.ref.kind == RemoteKind.album ? base.title : null, albumCover: base.imageUrl));
      next = page['next']?.toString();
    }
    return RemotePlaylist(ref: ref, title: base.title, tracks: tracks, imageUrl: base.imageUrl, owner: base.owner);
  }

  // --------------------------------------------------- service parsers (pure)

  static Map<String, dynamic> _jsonScript(String html, String id) {
    final m = RegExp('<script[^>]*id="$id"[^>]*>(.*?)</script>', dotAll: true).firstMatch(html);
    if (m == null) throw ImportException('The playlist page format changed; please update chinTunes.');
    final decoded = jsonDecode(m.group(1)!);
    return decoded is Map ? Map<String, dynamic>.from(decoded) : <String, dynamic>{};
  }

  static String _clean(String s) => unescapeHtml(s.replaceAll(' ', ' ')).replaceAll(RegExp(r'\s+'), ' ').trim();

  /// Spotify embed page → playlist / album.
  static RemotePlaylist parseSpotifyEmbed(String html, PlaylistRef ref) {
    final data = _jsonScript(html, '__NEXT_DATA__');
    Object? node = data;
    for (final key in ['props', 'pageProps', 'state', 'data', 'entity']) {
      node = node is Map ? node[key] : null;
    }
    if (node is! Map) throw ImportException('Spotify didn\'t return this playlist. Is it public?');
    final entity = node;
    final sources = (entity['coverArt'] is Map) ? (entity['coverArt'] as Map<dynamic, dynamic>)['sources'] : null;
    final cover = (sources is List && sources.isNotEmpty && sources.first is Map)
        ? (sources.first as Map<dynamic, dynamic>)['url']?.toString()
        : null;
    final list = entity['trackList'];
    final tracks = <Track>[];
    if (list is List) {
      for (final t in list.whereType<Map<dynamic, dynamic>>()) {
        final uri = t['uri']?.toString() ?? '';
        final id = uri.startsWith('spotify:track:') ? uri.substring('spotify:track:'.length) : null;
        final title = _clean(t['title']?.toString() ?? '');
        if (id == null || title.isEmpty) continue;
        final ms = t['duration'];
        tracks.add(Track(
          id: id,
          source: TrackSource.spotify,
          title: title,
          artist: _clean(t['subtitle']?.toString() ?? 'Unknown'),
          album: ref.kind == RemoteKind.album ? _clean(entity['name']?.toString() ?? '') : '',
          durationSec: ms is num ? (ms / 1000).round() : null,
          imageUrl: cover,
          webUrl: 'https://open.spotify.com/track/$id',
        ));
      }
    }
    return RemotePlaylist(
      ref: ref,
      title: _clean(entity['name']?.toString() ?? entity['title']?.toString() ?? 'Spotify playlist'),
      tracks: tracks,
      imageUrl: cover,
      owner: entity['subtitle']?.toString(),
      // The embed exposes at most ~100 tracks of long playlists.
      truncated: tracks.length >= 100,
    );
  }

  static List<Track> deezerTracks(Object? data, {String? albumTitle, String? albumCover}) {
    if (data is! List) return const [];
    final out = <Track>[];
    for (final t in data.whereType<Map<dynamic, dynamic>>()) {
      if (t['readable'] == false) continue; // region-blocked on Deezer itself
      final id = t['id']?.toString();
      final title = _clean(t['title']?.toString() ?? '');
      if (id == null || title.isEmpty) continue;
      final artist = t['artist'] is Map ? (t['artist'] as Map<dynamic, dynamic>)['name']?.toString() : null;
      final album = t['album'] is Map ? t['album'] as Map<dynamic, dynamic> : const <dynamic, dynamic>{};
      final dur = t['duration'];
      out.add(Track(
        id: id,
        source: TrackSource.deezer,
        title: title,
        artist: _clean(artist ?? 'Unknown'),
        album: _clean(album['title']?.toString() ?? albumTitle ?? ''),
        durationSec: dur is num ? dur.toInt() : int.tryParse('$dur'),
        imageUrl: forceHttps(album['cover_xl']?.toString() ?? album['cover_big']?.toString() ?? albumCover),
        webUrl: 'https://www.deezer.com/track/$id',
      ));
    }
    return out;
  }

  /// Deezer `/playlist/<id>` or `/album/<id>` first page.
  static RemotePlaylist parseDeezer(Map<String, dynamic> json, PlaylistRef ref) {
    final isAlbum = ref.kind == RemoteKind.album;
    final title = _clean(json['title']?.toString() ?? 'Deezer ${ref.kind.name}');
    final cover = forceHttps((isAlbum ? json['cover_xl'] : json['picture_xl'])?.toString());
    final tracksNode = json['tracks'] is Map ? (json['tracks'] as Map<dynamic, dynamic>)['data'] : null;
    final owner = isAlbum
        ? (json['artist'] is Map ? (json['artist'] as Map<dynamic, dynamic>)['name']?.toString() : null)
        : (json['creator'] is Map ? (json['creator'] as Map<dynamic, dynamic>)['name']?.toString() : null);
    return RemotePlaylist(
      ref: ref,
      title: title,
      tracks: deezerTracks(tracksNode, albumTitle: isAlbum ? title : null, albumCover: cover),
      imageUrl: cover,
      owner: owner,
    );
  }

  static String? _appleArt(Object? artwork) {
    if (artwork is! Map) return null;
    final dict = artwork['dictionary'];
    final url = dict is Map ? dict['url']?.toString() : null;
    if (url == null) return null;
    return url
        .replaceAll('{w}', '500')
        .replaceAll('{h}', '500')
        .replaceAll('{c}', 'bb')
        .replaceAll('{f}', 'jpg')
        .replaceAll('bbbb', 'bb');
  }

  /// Apple Music playlist / album page → tracks (`trackLockup` items).
  static RemotePlaylist parseAppleMusicPage(String html, PlaylistRef ref) {
    final data = _jsonScript(html, 'serialized-server-data');
    final pages = data['data'];
    final page = (pages is List && pages.isNotEmpty && pages.first is Map) ? (pages.first as Map<dynamic, dynamic>)['data'] : null;
    final sections = page is Map ? page['sections'] : null;
    if (sections is! List) throw ImportException('Apple Music didn\'t return this playlist. Is it public?');
    String title = 'Apple Music ${ref.kind.name}';
    String? cover;
    final tracks = <Track>[];
    for (final s in sections.whereType<Map<dynamic, dynamic>>()) {
      final items = s['items'];
      if (items is! List) continue;
      final kind = s['itemKind']?.toString();
      if (kind == 'containerDetailHeaderLockup' && items.isNotEmpty && items.first is Map) {
        final h = items.first as Map<dynamic, dynamic>;
        title = _clean(h['title']?.toString() ?? title);
        cover = _appleArt(h['artwork']);
      } else if (kind == 'trackLockup') {
        for (final it in items.whereType<Map<dynamic, dynamic>>()) {
          final cd = it['contentDescriptor'];
          final ids = cd is Map ? cd['identifiers'] : null;
          final id = ids is Map ? ids['storeAdamID']?.toString() : null;
          final t = _clean(it['title']?.toString() ?? '');
          if (id == null || t.isEmpty) continue;
          final tertiary = it['tertiaryLinks'];
          final album = (tertiary is List && tertiary.isNotEmpty && tertiary.first is Map)
              ? (tertiary.first as Map<dynamic, dynamic>)['title']?.toString()
              : null;
          final ms = it['duration'];
          tracks.add(Track(
            id: id,
            source: TrackSource.appleMusic,
            title: t,
            artist: _clean(it['artistName']?.toString() ?? 'Unknown'),
            album: _clean(album ?? (ref.kind == RemoteKind.album ? title : '')),
            durationSec: ms is num ? (ms / 1000).round() : null,
            imageUrl: _appleArt(it['artwork']) ?? cover,
            webUrl: cd is Map ? cd['url']?.toString() : null,
          ));
        }
      }
    }
    return RemotePlaylist(
      ref: ref,
      title: title,
      tracks: tracks,
      imageUrl: cover,
      // The server-rendered page lists the first ~100 songs of long playlists.
      truncated: tracks.length >= 100,
    );
  }
}
