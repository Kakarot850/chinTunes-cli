import 'collection.dart';
import 'track.dart';

/// Search filter chips in the UI.
enum SearchFilter { songs, collections, artists }

class SearchResults {
  const SearchResults({
    this.songs = const [],
    this.youtube = const [],
    this.collections = const [],
    this.artists = const [],
    this.errors = const [],
  });

  /// JioSaavn songs (320 kbps capable).
  final List<Track> songs;

  /// YouTube fallback songs (CLI parity: yt-dlp `ytsearch`).
  final List<Track> youtube;

  /// Albums + playlists.
  final List<CollectionSummary> collections;
  final List<CollectionSummary> artists;

  /// Per-source failures that did not abort the whole search.
  final List<String> errors;

  bool get isEmpty =>
      songs.isEmpty && youtube.isEmpty && collections.isEmpty && artists.isEmpty;

  static const empty = SearchResults();
}
