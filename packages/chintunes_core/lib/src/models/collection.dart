import 'track.dart';

enum CollectionType { album, playlist, artist, song, unknown }

CollectionType collectionTypeFrom(Object? raw) {
  switch (raw?.toString()) {
    case 'album':
      return CollectionType.album;
    case 'playlist':
      return CollectionType.playlist;
    case 'artist':
      return CollectionType.artist;
    case 'song':
      return CollectionType.song;
    default:
      return CollectionType.unknown;
  }
}

/// A browsable item (album / playlist / artist / single song card).
class CollectionSummary {
  const CollectionSummary({
    required this.id,
    required this.type,
    required this.title,
    this.source = TrackSource.jiosaavn,
    this.subtitle = '',
    this.imageUrl,
    this.webUrl,
    this.token,
    this.songCount,
  });

  final String id;
  final CollectionType type;
  final String title;
  final TrackSource source;
  final String subtitle;
  final String? imageUrl;
  final String? webUrl;

  /// JioSaavn perma-url token (last path segment), used by `webapi.get`.
  final String? token;
  final int? songCount;

  @override
  bool operator ==(Object other) =>
      other is CollectionSummary &&
      other.id == id &&
      other.type == type &&
      other.source == source;

  @override
  int get hashCode => Object.hash(id, type, source);
}

/// A fully loaded collection with its tracks.
class MediaCollection {
  const MediaCollection({
    required this.summary,
    required this.tracks,
    this.description,
    this.related = const [],
  });

  final CollectionSummary summary;
  final List<Track> tracks;
  final String? description;

  /// For artists: top albums. Empty otherwise.
  final List<CollectionSummary> related;

  bool get isSingle => summary.type == CollectionType.song;
}
