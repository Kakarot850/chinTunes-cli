import 'package:youtube_explode_dart/youtube_explode_dart.dart' as yt;

import '../data/data_mode.dart';
import '../data/stream_selection.dart';
import '../models/collection.dart';
import '../models/resolved_stream.dart';
import '../models/track.dart';
import '../util/artist_name.dart';
import 'youtube_source.dart';

/// [YouTubeSource] backed by `youtube_explode_dart`.
///
/// Gotcha: YouTube changes its player regularly; when extraction breaks,
/// bump `youtube_explode_dart` first (see BUG_REPORT.md B-005).
class YoutubeExplodeSource implements YouTubeSource {
  YoutubeExplodeSource() : _yt = yt.YoutubeExplode();

  final yt.YoutubeExplode _yt;

  Track _toTrack(yt.Video v) => Track(
        id: v.id.value,
        source: TrackSource.youtube,
        title: v.title,
        artist: cleanArtistName(v.author),
        album: 'YouTube',
        durationSec: v.duration?.inSeconds,
        imageUrl: v.thumbnails.highResUrl,
        webUrl: 'https://www.youtube.com/watch?v=${v.id.value}',
      );

  @override
  Future<List<Track>> search(String query, {int limit = 10}) async {
    final results = await _yt.search.search(query);
    return results.take(limit).map(_toTrack).toList();
  }

  @override
  Future<Track?> video(String videoId) async {
    final v = await _yt.videos.get(videoId);
    return _toTrack(v);
  }

  @override
  Future<ResolvedStream> resolveAudio(String videoId, {DataMode mode = DataMode.high}) async {
    // Only stream *metadata* is fetched here; audio-only renditions are the
    // only candidates, so video bytes are never requested.
    final manifest = await _yt.videos.streamsClient.getManifest(videoId);
    final candidates = manifest.audioOnly
        .map((s) => AudioStreamCandidate(
              itag: s.tag,
              bitrateKbps: s.bitrate.kiloBitsPerSecond.round(),
              codec: s.audioCodec,
              container: s.container.name,
              url: s.url,
              sizeBytes: s.size.totalBytes,
            ))
        .toList();
    final pick = StreamSelector.pickYouTube(candidates, mode);
    if (pick == null) throw StreamResolveException('No audio-only stream for $videoId');
    return ResolvedStream(
      uri: pick.url,
      sourceLabel: 'YouTube',
      bitrateKbps: pick.bitrateKbps,
      codec: pick.isOpus ? 'Opus' : 'AAC',
      container: pick.container,
      itag: pick.itag,
      sizeBytes: pick.sizeBytes,
      expires: true,
    );
  }

  @override
  Future<MediaCollection?> playlist(String playlistId, {int limit = 200}) async {
    final meta = await _yt.playlists.get(playlistId);
    final videos = await _yt.playlists.getVideos(playlistId).take(limit).toList();
    return MediaCollection(
      summary: CollectionSummary(
        id: playlistId,
        type: CollectionType.playlist,
        source: TrackSource.youtube,
        title: meta.title,
        subtitle: meta.author,
        imageUrl: videos.isEmpty ? null : videos.first.thumbnails.highResUrl,
        webUrl: 'https://www.youtube.com/playlist?list=$playlistId',
      ),
      tracks: videos.map(_toTrack).toList(),
    );
  }

  @override
  void close() => _yt.close();
}
