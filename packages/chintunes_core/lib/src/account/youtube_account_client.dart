import 'package:googleapis/youtube/v3.dart' as yt;
import 'package:http/http.dart' as http;

import '../models/collection.dart';
import '../models/track.dart';
import 'youtube_library_mapper.dart';

class YouTubePage<T> {
  const YouTubePage(this.items, {this.nextPageToken});

  final List<T> items;
  final String? nextPageToken;
}

/// Signed-in user's YouTube library via YouTube Data API v3
/// (scope `https://www.googleapis.com/auth/youtube.readonly`).
///
/// Quota: every `list` call costs 1 unit (10,000 units/day per Cloud project).
/// The deprecated `watchHistory` playlist is NOT used: history comes from
/// local plays plus a Google Takeout import (see `TakeoutHistoryParser`).
class YouTubeAccountClient {
  YouTubeAccountClient(http.Client authenticatedClient) : _api = yt.YouTubeApi(authenticatedClient);

  YouTubeAccountClient.withApi(this._api);

  final yt.YouTubeApi _api;

  static const List<String> _videoParts = ['snippet', 'contentDetails'];

  static String? _thumb(yt.ThumbnailDetails? t) =>
      t?.high?.url ?? t?.standard?.url ?? t?.medium?.url ?? t?.default_?.url ?? t?.maxres?.url;

  static TaggedTrack? mapVideo(yt.Video v) {
    final id = v.id;
    final s = v.snippet;
    if (id == null || s == null || s.title == null) return null;
    final track = YouTubeLibraryMapper.trackFrom(
      videoId: id,
      rawTitle: s.title!,
      channelTitle: s.channelTitle ?? '',
      durationSec: YouTubeLibraryMapper.parseIsoDuration(v.contentDetails?.duration),
      imageUrl: _thumb(s.thumbnails),
      year: s.publishedAt?.year.toString(),
    );
    return TaggedTrack(
      track,
      isMusic: YouTubeLibraryMapper.isMusic(
        categoryId: s.categoryId,
        channelTitle: s.channelTitle,
        title: s.title,
      ),
    );
  }

  static TaggedTrack? mapPlaylistItem(yt.PlaylistItem item) {
    final s = item.snippet;
    final id = item.contentDetails?.videoId ?? s?.resourceId?.videoId;
    final title = s?.title;
    if (id == null || title == null || title == 'Deleted video' || title == 'Private video') return null;
    final channel = s?.videoOwnerChannelTitle ?? '';
    return TaggedTrack(
      YouTubeLibraryMapper.trackFrom(
        videoId: id,
        rawTitle: title,
        channelTitle: channel,
        imageUrl: _thumb(s?.thumbnails),
      ),
      isMusic: YouTubeLibraryMapper.isMusic(channelTitle: channel, title: title),
    );
  }

  /// `videos.list(myRating: 'like')` — liked music + videos, newest first.
  Future<YouTubePage<TaggedTrack>> likedVideos({String? pageToken, int maxResults = 50}) async {
    final res = await _api.videos.list(
      _videoParts,
      myRating: 'like',
      maxResults: maxResults,
      pageToken: pageToken,
    );
    return YouTubePage(
      (res.items ?? const <yt.Video>[]).map(mapVideo).whereType<TaggedTrack>().toList(),
      nextPageToken: res.nextPageToken,
    );
  }

  /// Fetches up to [limit] liked items across pages.
  Future<List<TaggedTrack>> allLikedVideos({int limit = 200}) async {
    final out = <TaggedTrack>[];
    String? token;
    do {
      final page = await likedVideos(pageToken: token);
      out.addAll(page.items);
      token = page.nextPageToken;
    } while (token != null && out.length < limit);
    return out.take(limit).toList();
  }

  /// `playlists.list(mine: true)`.
  Future<List<CollectionSummary>> myPlaylists({int limit = 100}) async {
    final out = <CollectionSummary>[];
    String? token;
    do {
      final res = await _api.playlists.list(
        ['snippet', 'contentDetails'],
        mine: true,
        maxResults: 50,
        pageToken: token,
      );
      for (final p in res.items ?? const <yt.Playlist>[]) {
        final id = p.id;
        if (id == null) continue;
        out.add(CollectionSummary(
          id: id,
          type: CollectionType.playlist,
          source: TrackSource.youtube,
          title: p.snippet?.title ?? 'Playlist',
          subtitle: p.snippet?.channelTitle ?? '',
          imageUrl: _thumb(p.snippet?.thumbnails),
          webUrl: 'https://www.youtube.com/playlist?list=$id',
          songCount: p.contentDetails?.itemCount,
        ));
      }
      token = res.nextPageToken;
    } while (token != null && out.length < limit);
    return out;
  }

  /// `playlistItems.list` (works for private playlists, unlike scraping).
  Future<MediaCollection> playlist(CollectionSummary summary, {int limit = 200}) async {
    final tracks = <Track>[];
    String? token;
    do {
      final res = await _api.playlistItems.list(
        ['snippet', 'contentDetails'],
        playlistId: summary.id,
        maxResults: 50,
        pageToken: token,
      );
      tracks.addAll((res.items ?? const <yt.PlaylistItem>[])
          .map(mapPlaylistItem)
          .whereType<TaggedTrack>()
          .map((t) => t.track));
      token = res.nextPageToken;
    } while (token != null && tracks.length < limit);
    return MediaCollection(summary: summary, tracks: tracks.take(limit).toList());
  }
}
