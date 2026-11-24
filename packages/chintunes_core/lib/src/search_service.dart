import 'jiosaavn/jiosaavn_client.dart';
import 'models/collection.dart';
import 'models/search_results.dart';
import 'models/track.dart';
import 'youtube/youtube_source.dart';

/// Multi-source search. Each source is isolated: one failing provider adds an
/// entry to [SearchResults.errors] instead of failing the whole query.
class SearchService {
  SearchService({required JioSaavnClient jiosaavn, required YouTubeSource youtube, this.includeYouTube = true})
      : _jiosaavn = jiosaavn,
        _youtube = youtube;

  final JioSaavnClient _jiosaavn;
  final YouTubeSource _youtube;
  final bool includeYouTube;

  Future<SearchResults> search(String query, {SearchFilter filter = SearchFilter.songs}) async {
    final q = query.trim();
    if (q.isEmpty) return SearchResults.empty;
    final errors = <String>[];

    Future<List<T>> guard<T>(String label, Future<List<T>> Function() run) async {
      try {
        return await run();
      } catch (e) {
        errors.add('$label: $e');
        return <T>[];
      }
    }

    switch (filter) {
      case SearchFilter.songs:
        final songsF = guard<Track>('JioSaavn', () => _jiosaavn.searchSongs(q));
        final ytF = includeYouTube
            ? guard<Track>('YouTube', () => _youtube.search(q, limit: 8))
            : Future.value(<Track>[]);
        final songs = await songsF;
        final yt = await ytF;
        return SearchResults(songs: songs, youtube: yt, errors: errors);
      case SearchFilter.collections:
        final albumsF = guard<CollectionSummary>('Albums', () => _jiosaavn.searchAlbums(q));
        final playlistsF = guard<CollectionSummary>('Playlists', () => _jiosaavn.searchPlaylists(q));
        final albums = await albumsF;
        final playlists = await playlistsF;
        return SearchResults(collections: _interleave(albums, playlists), errors: errors);
      case SearchFilter.artists:
        final artists = await guard<CollectionSummary>('Artists', () => _jiosaavn.searchArtists(q));
        return SearchResults(artists: artists, errors: errors);
    }
  }

  static List<T> _interleave<T>(List<T> a, List<T> b) {
    final out = <T>[];
    for (var i = 0; i < a.length || i < b.length; i++) {
      if (i < a.length) out.add(a[i]);
      if (i < b.length) out.add(b[i]);
    }
    return out;
  }
}
