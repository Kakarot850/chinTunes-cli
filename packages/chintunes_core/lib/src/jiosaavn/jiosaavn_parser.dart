import '../models/collection.dart';
import '../models/home_feed.dart';
import '../models/track.dart';
import '../util/html_text.dart';
import '../util/image_url.dart';
import 'jiosaavn_crypto.dart';

/// JSON → model mapping for JioSaavn `api.php` payloads (api_version=4).
abstract final class JioSaavnParser {
  static Map<String, dynamic> _map(Object? v) =>
      v is Map ? Map<String, dynamic>.from(v) : const <String, dynamic>{};

  static List<Map<String, dynamic>> _list(Object? v) =>
      v is List ? v.whereType<Map<dynamic, dynamic>>().map(Map<String, dynamic>.from).toList() : const [];

  static String _str(Object? v) => v == null ? '' : v.toString();

  /// Artist resolution order. Fixes CLI bug B-001: the CLI used `subtitle`,
  /// which is `"Artists - Album"`, so the album leaked into the artist tag.
  static String _artistOf(Map<String, dynamic> raw, Map<String, dynamic> mi) {
    final primary = _list(_map(mi['artistMap'])['primary_artists'])
        .map((a) => unescapeHtml(_str(a['name'])))
        .where((n) => n.isNotEmpty)
        .toList();
    if (primary.isNotEmpty) return primary.join(', ');

    final flat = unescapeHtml(_str(mi['primary_artists'] ?? mi['singers']));
    if (flat.isNotEmpty) return flat;

    final subtitle = unescapeHtml(_str(raw['subtitle']));
    if (subtitle.isNotEmpty) {
      final idx = subtitle.lastIndexOf(' - ');
      return idx > 0 ? subtitle.substring(0, idx).trim() : subtitle;
    }
    final music = unescapeHtml(_str(mi['music']));
    return music.isNotEmpty ? music : 'Unknown';
  }

  static Track song(Map<String, dynamic> raw) {
    final mi = _map(raw['more_info']);
    final title = unescapeHtml(_str(raw['title'] ?? raw['song']));
    final album = unescapeHtml(_str(mi['album'] ?? raw['album']));
    return Track(
      id: _str(raw['id']),
      source: TrackSource.jiosaavn,
      title: title,
      artist: _artistOf(raw, mi),
      album: album.isEmpty ? title : album,
      albumId: _str(mi['album_id']).isEmpty ? null : _str(mi['album_id']),
      durationSec: int.tryParse(_str(mi['duration'] ?? raw['duration'])),
      year: _str(raw['year']).isEmpty ? null : _str(raw['year']),
      imageUrl: upscaleSaavnImage(_str(raw['image'])),
      mediaUrl: JioSaavnCrypto.decryptMediaUrl(_str(mi['encrypted_media_url'])),
      has320: _str(mi['320kbps']).toLowerCase() == 'true',
      hasLyrics: _str(mi['has_lyrics']).toLowerCase() == 'true',
      webUrl: forceHttps(_str(raw['perma_url'] ?? raw['url'])),
      language: _str(raw['language']).isEmpty ? null : _str(raw['language']),
    );
  }

  static List<Track> songs(Object? list) => _list(list)
      .where((m) => (m['type'] ?? 'song') == 'song')
      .map(song)
      .where((t) => t.id.isNotEmpty)
      .toList();

  static CollectionSummary summary(Map<String, dynamic> raw, {CollectionType? type}) {
    final mi = _map(raw['more_info']);
    final perma = forceHttps(_str(raw['perma_url'] ?? raw['url']));
    final resolvedType = type ?? collectionTypeFrom(raw['type']);
    var subtitle = unescapeHtml(_str(raw['subtitle'] ?? raw['description'] ?? raw['role']));
    if (subtitle.isEmpty && resolvedType == CollectionType.artist) subtitle = 'Artist';
    return CollectionSummary(
      id: _str(raw['id'] ?? raw['artistId']),
      type: resolvedType,
      title: unescapeHtml(_str(raw['title'] ?? raw['name'])),
      subtitle: subtitle,
      imageUrl: upscaleSaavnImage(_str(raw['image'])),
      webUrl: perma,
      token: lastPathSegment(perma),
      songCount: int.tryParse(_str(mi['song_count'] ?? raw['list_count'])),
    );
  }

  static List<CollectionSummary> summaries(Object? list, {CollectionType? type}) =>
      _list(list).map((m) => summary(m, type: type)).where((s) => s.id.isNotEmpty).toList();

  /// Album or playlist detail payload (`webapi.get` / `playlist.getDetails`).
  static MediaCollection? collection(Object? json, CollectionType type) {
    final raw = _map(json);
    if (_str(raw['title']).isEmpty) return null;
    return MediaCollection(
      summary: summary(raw, type: type),
      tracks: songs(raw['list']),
      description: unescapeHtml(_str(raw['header_desc'])).isEmpty
          ? null
          : unescapeHtml(_str(raw['header_desc'])),
    );
  }

  /// Artist detail payload (`webapi.get&type=artist`).
  static MediaCollection? artist(Object? json) {
    final raw = _map(json);
    if (_str(raw['name']).isEmpty) return null;
    final perma = forceHttps(_str(_map(raw['urls'])['overview']));
    return MediaCollection(
      summary: CollectionSummary(
        id: _str(raw['artistId']),
        type: CollectionType.artist,
        title: unescapeHtml(_str(raw['name'])),
        subtitle: unescapeHtml(_str(raw['subtitle'])),
        imageUrl: upscaleSaavnImage(_str(raw['image'])),
        webUrl: perma,
        token: lastPathSegment(perma),
      ),
      tracks: songs(raw['topSongs']),
      related: summaries(raw['topAlbums'], type: CollectionType.album),
    );
  }

  /// `webapi.getLaunchData` → ordered home sections.
  static List<HomeSection> launchSections(Object? json) {
    final raw = _map(json);
    final modules = _map(raw['modules']);
    const wanted = ['charts', 'top_playlists', 'new_albums', 'new_trending'];
    final entries = <({int position, HomeSection section})>[];
    for (final key in wanted) {
      final items = summaries(raw[key]);
      if (items.isEmpty) continue;
      final module = _map(modules[key]);
      final title = unescapeHtml(_str(module['title']));
      entries.add((
        position: int.tryParse(_str(module['position'])) ?? 99,
        section: HomeSection(key: key, title: title.isEmpty ? _fallbackTitle(key) : title, items: items),
      ));
    }
    entries.sort((a, b) => a.position.compareTo(b.position));
    return entries.map((e) => e.section).toList();
  }

  static String _fallbackTitle(String key) => switch (key) {
        'charts' => 'Top Charts',
        'top_playlists' => 'Editorial Picks',
        'new_albums' => 'New Releases',
        'new_trending' => 'Trending Now',
        _ => key,
      };
}
