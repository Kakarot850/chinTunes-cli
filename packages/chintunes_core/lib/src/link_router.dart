import 'models/collection.dart';
import 'models/track.dart';
import 'util/image_url.dart';

/// A parsed share link (port of `ProviderRegistry.get_provider_for_url`).
class LinkTarget {
  const LinkTarget({required this.source, required this.type, required this.id, required this.url});

  final TrackSource source;
  final CollectionType type;

  /// JioSaavn token, YouTube video/playlist id, or Spotify track id.
  final String id;
  final String url;

  @override
  String toString() => 'LinkTarget(${source.name}, ${type.name}, $id)';
}

abstract final class LinkRouter {
  static bool looksLikeUrl(String input) {
    final s = input.trim().toLowerCase();
    return s.startsWith('http://') ||
        s.startsWith('https://') ||
        s.contains('jiosaavn.com/') ||
        s.contains('youtu.be/') ||
        s.contains('youtube.com/') ||
        s.contains('spotify.com/');
  }

  static LinkTarget? parse(String input) {
    var raw = input.trim();
    if (raw.isEmpty) return null;
    if (!raw.contains('://')) raw = 'https://$raw';
    final uri = Uri.tryParse(raw);
    if (uri == null || uri.host.isEmpty) return null;
    final host = uri.host.toLowerCase();
    final path = uri.path.toLowerCase();

    if (host.contains('jiosaavn.com') || host.contains('saavn.com')) {
      final token = lastPathSegment(raw);
      if (token == null) return null;
      final type = path.contains('/song/')
          ? CollectionType.song
          : path.contains('/album/')
              ? CollectionType.album
              : path.contains('/artist/')
                  ? CollectionType.artist
                  : CollectionType.playlist; // /featured/, /playlist/, /s/playlist/
      return LinkTarget(source: TrackSource.jiosaavn, type: type, id: token, url: raw);
    }

    if (host.contains('spotify.com')) {
      final m = RegExp(r'/track/([A-Za-z0-9]+)').firstMatch(uri.path);
      if (m == null) return null; // CLI only supports Spotify tracks.
      return LinkTarget(source: TrackSource.spotify, type: CollectionType.song, id: m.group(1)!, url: raw);
    }

    if (host.contains('youtu.be')) {
      final id = uri.pathSegments.isEmpty ? null : uri.pathSegments.first;
      if (id == null || id.isEmpty) return null;
      return LinkTarget(source: TrackSource.youtube, type: CollectionType.song, id: id, url: raw);
    }

    if (host.contains('youtube.com')) {
      final v = uri.queryParameters['v'];
      if (v != null && v.isNotEmpty) {
        return LinkTarget(source: TrackSource.youtube, type: CollectionType.song, id: v, url: raw);
      }
      final list = uri.queryParameters['list'];
      if (list != null && list.isNotEmpty) {
        return LinkTarget(source: TrackSource.youtube, type: CollectionType.playlist, id: list, url: raw);
      }
      final shorts = RegExp(r'/shorts/([A-Za-z0-9_-]+)').firstMatch(uri.path);
      if (shorts != null) {
        return LinkTarget(source: TrackSource.youtube, type: CollectionType.song, id: shorts.group(1)!, url: raw);
      }
    }
    return null;
  }
}
