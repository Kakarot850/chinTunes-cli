import 'jiosaavn/jiosaavn_client.dart';
import 'link_router.dart';
import 'models/collection.dart';
import 'models/home_feed.dart';
import 'models/track.dart';
import 'spotify/spotify_client.dart';
import 'youtube/youtube_source.dart';

class CatalogException implements Exception {
  CatalogException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Opens collections and share links across providers
/// (port of `provider.fetch_collection(url)` for every registered provider).
class CatalogService {
  CatalogService({
    required JioSaavnClient jiosaavn,
    required YouTubeSource youtube,
    required SpotifyClient spotify,
  })  : _jiosaavn = jiosaavn,
        _youtube = youtube,
        _spotify = spotify;

  final JioSaavnClient _jiosaavn;
  final YouTubeSource _youtube;
  final SpotifyClient _spotify;

  Future<HomeFeed> homeFeed({String language = 'hindi'}) => _jiosaavn.homeFeed(language: language);

  Future<MediaCollection> open(CollectionSummary summary) async {
    MediaCollection? result;
    if (summary.source == TrackSource.youtube) {
      result = await _youtube.playlist(summary.id);
    } else {
      switch (summary.type) {
        case CollectionType.album:
          result = await _jiosaavn.album(token: summary.token, id: summary.id);
        case CollectionType.playlist:
          result = await _jiosaavn.playlist(id: summary.id, token: summary.token);
        case CollectionType.artist:
          final token = summary.token;
          if (token == null) throw CatalogException('Artist link missing');
          result = await _jiosaavn.artist(token: token);
        case CollectionType.song:
          final songs = await _jiosaavn.songDetails([summary.id]);
          if (songs.isNotEmpty) {
            result = MediaCollection(summary: summary, tracks: songs);
          }
        case CollectionType.unknown:
          result = null;
      }
    }
    if (result == null) throw CatalogException('Could not load "${summary.title}"');
    return result;
  }

  /// Resolves a pasted share link into a playable collection.
  Future<MediaCollection> openLink(String url) async {
    final target = LinkRouter.parse(url);
    if (target == null) throw CatalogException('Unsupported link');

    switch (target.source) {
      case TrackSource.jiosaavn:
        if (target.type == CollectionType.song) {
          final song = await _jiosaavn.songByToken(target.id);
          if (song == null) throw CatalogException('Song not found');
          return _single(song);
        }
        final summary = CollectionSummary(id: '', type: target.type, title: 'JioSaavn', token: target.id, webUrl: url);
        final MediaCollection? col = switch (target.type) {
          CollectionType.album => await _jiosaavn.album(token: target.id),
          CollectionType.artist => await _jiosaavn.artist(token: target.id),
          _ => await _jiosaavn.playlist(token: target.id),
        };
        if (col == null) throw CatalogException('Could not load ${summary.type.name} from link');
        return col;
      case TrackSource.spotify:
        final track = await _spotify.track(target.id);
        if (track == null) throw CatalogException('Spotify track not found');
        return _single(track);
      case TrackSource.youtube:
        if (target.type == CollectionType.playlist) {
          final col = await _youtube.playlist(target.id);
          if (col == null) throw CatalogException('YouTube playlist not found');
          return col;
        }
        final track = await _youtube.video(target.id) ??
            Track(id: target.id, source: TrackSource.youtube, title: 'YouTube video', webUrl: url);
        return _single(track);
      case TrackSource.local:
        throw CatalogException('Unsupported link');
    }
  }

  MediaCollection _single(Track t) => MediaCollection(
        summary: CollectionSummary(
          id: t.id,
          type: CollectionType.song,
          source: t.source,
          title: t.title,
          subtitle: t.artist,
          imageUrl: t.imageUrl,
          webUrl: t.webUrl,
        ),
        tracks: [t],
      );
}
