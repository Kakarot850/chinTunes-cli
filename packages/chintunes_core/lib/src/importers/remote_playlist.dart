import '../models/track.dart';

/// Streaming services whose public playlists / albums can be imported.
///
/// Tidal is not supported: its API needs registered developer credentials
/// (BUG_REPORT.md B-044).
enum PlaylistService {
  jiosaavn('JioSaavn'),
  youtube('YouTube'),
  spotify('Spotify'),
  deezer('Deezer'),
  appleMusic('Apple Music');

  const PlaylistService(this.label);
  final String label;

  static PlaylistService fromName(String? name) =>
      PlaylistService.values.firstWhere((s) => s.name == name, orElse: () => PlaylistService.youtube);
}

enum RemoteKind { playlist, album }

/// Identifies a remote playlist / album; persisted with synced playlists.
class PlaylistRef {
  const PlaylistRef({required this.service, required this.kind, required this.id, required this.url});

  final PlaylistService service;
  final RemoteKind kind;

  /// Service id (Spotify base62, Deezer numeric, Apple `pl.…` / album id,
  /// JioSaavn perma-url token, YouTube `list=` id).
  final String id;
  final String url;

  Map<String, dynamic> toJson() => {'service': service.name, 'kind': kind.name, 'id': id, 'url': url};

  factory PlaylistRef.fromJson(Map<dynamic, dynamic> json) => PlaylistRef(
        service: PlaylistService.fromName(json['service']?.toString()),
        kind: json['kind'] == 'album' ? RemoteKind.album : RemoteKind.playlist,
        id: json['id']?.toString() ?? '',
        url: json['url']?.toString() ?? '',
      );

  @override
  String toString() => 'PlaylistRef(${service.name}/${kind.name}/$id)';
}

/// A fetched remote playlist (tracks in remote order).
class RemotePlaylist {
  const RemotePlaylist({
    required this.ref,
    required this.title,
    required this.tracks,
    this.imageUrl,
    this.owner,
    this.truncated = false,
  });

  final PlaylistRef ref;
  final String title;
  final List<Track> tracks;
  final String? imageUrl;
  final String? owner;

  /// True when the service only exposed the first N tracks (Spotify embed
  /// and Apple Music page data cap long playlists).
  final bool truncated;
}

/// What a sync changed.
class PlaylistDiff {
  const PlaylistDiff({required this.added, required this.removed, required this.kept});

  final List<Track> added;
  final List<Track> removed;
  final int kept;

  bool get hasChanges => added.isNotEmpty || removed.isNotEmpty;

  /// Compares by `Track.uid` (stable per service).
  static PlaylistDiff compute(List<Track> before, List<Track> after) {
    final beforeIds = {for (final t in before) t.uid};
    final afterIds = {for (final t in after) t.uid};
    return PlaylistDiff(
      added: [for (final t in after) if (!beforeIds.contains(t.uid)) t],
      removed: [for (final t in before) if (!afterIds.contains(t.uid)) t],
      kept: after.where((t) => beforeIds.contains(t.uid)).length,
    );
  }

  String get summary {
    if (!hasChanges) return 'Up to date';
    final parts = [
      if (added.isNotEmpty) '+${added.length} new',
      if (removed.isNotEmpty) '−${removed.length} removed',
    ];
    return parts.join(', ');
  }
}
